-- ============================================================
-- SFDC → PostgreSQL データ移行 整合性検証 SQL
-- 対象: accounts, contacts, daily_reports, counseling_records
-- 生成日時: 2026-03-27
-- ============================================================
-- 使い方:
--   1. SFDC 側の件数を事前に取得しておく
--   2. 本 SQL を PostgreSQL 上で実行
--   3. 各クエリの結果を SFDC 側と突合する
--   結果が 0 件 = 問題なし（孤立・NULL・不正値チェック）
-- ============================================================

-- ************************************************************
-- 1. レコード件数チェック
--    SFDC 側の件数と突合して差異がないことを確認する
-- ************************************************************

SELECT 'accounts'           AS table_name, COUNT(*) AS record_count FROM accounts
UNION ALL
SELECT 'contacts'           AS table_name, COUNT(*) AS record_count FROM contacts
UNION ALL
SELECT 'daily_reports'      AS table_name, COUNT(*) AS record_count FROM daily_reports
UNION ALL
SELECT 'counseling_records' AS table_name, COUNT(*) AS record_count FROM counseling_records
ORDER BY table_name;

-- ************************************************************
-- 2. 孤立レコードチェック
--    外部キー先が存在しないレコードを検出する
--    → 結果が 0 件であること
-- ************************************************************

-- 2-1. contacts: 所属店舗 (account_id) が accounts に存在しない
SELECT c.id, c.last_name, c.account_id
FROM   contacts c
LEFT JOIN accounts a ON c.account_id = a.id
WHERE  c.account_id IS NOT NULL
  AND  a.id IS NULL;

-- 2-2. daily_reports: 訪問先店舗 (account_id) が accounts に存在しない
SELECT dr.id, dr.name, dr.account_id
FROM   daily_reports dr
LEFT JOIN accounts a ON dr.account_id = a.id
WHERE  a.id IS NULL;

-- 2-3. counseling_records: 親の日報 (daily_report_id) が daily_reports に存在しない
SELECT cr.id, cr.name, cr.daily_report_id
FROM   counseling_records cr
LEFT JOIN daily_reports dr ON cr.daily_report_id = dr.id
WHERE  dr.id IS NULL;

-- 2-4. counseling_records: 対象担当者 (contact_id) が contacts に存在しない
SELECT cr.id, cr.name, cr.contact_id
FROM   counseling_records cr
LEFT JOIN contacts ct ON cr.contact_id = ct.id
WHERE  cr.contact_id IS NOT NULL
  AND  ct.id IS NULL;

-- ************************************************************
-- 3. NULL チェック
--    NOT NULL 制約カラムに NULL が混入していないか検証
--    → 結果が 0 件であること
-- ************************************************************

-- 3-1. accounts
SELECT 'accounts' AS table_name, id,
       CASE WHEN name       IS NULL THEN 'name'
            WHEN store_code  IS NULL THEN 'store_code'
            WHEN region      IS NULL THEN 'region'
       END AS null_column
FROM   accounts
WHERE  name IS NULL OR store_code IS NULL OR region IS NULL;

-- 3-2. contacts
SELECT 'contacts' AS table_name, id,
       CASE WHEN last_name IS NULL THEN 'last_name'
       END AS null_column
FROM   contacts
WHERE  last_name IS NULL;

-- 3-3. daily_reports
SELECT 'daily_reports' AS table_name, id,
       CASE WHEN name              IS NULL THEN 'name'
            WHEN report_date       IS NULL THEN 'report_date'
            WHEN supervisor_id     IS NULL THEN 'supervisor_id'
            WHEN account_id        IS NULL THEN 'account_id'
            WHEN visit_start_time  IS NULL THEN 'visit_start_time'
            WHEN visit_end_time    IS NULL THEN 'visit_end_time'
            WHEN visit_purpose     IS NULL THEN 'visit_purpose'
            WHEN overall_condition IS NULL THEN 'overall_condition'
            WHEN status            IS NULL THEN 'status'
       END AS null_column
FROM   daily_reports
WHERE  name IS NULL
    OR report_date IS NULL
    OR supervisor_id IS NULL
    OR account_id IS NULL
    OR visit_start_time IS NULL
    OR visit_end_time IS NULL
    OR visit_purpose IS NULL
    OR overall_condition IS NULL
    OR status IS NULL;

-- 3-4. counseling_records
SELECT 'counseling_records' AS table_name, id,
       CASE WHEN name             IS NULL THEN 'name'
            WHEN daily_report_id  IS NULL THEN 'daily_report_id'
            WHEN contact_id       IS NULL THEN 'contact_id'
            WHEN category         IS NULL THEN 'category'
            WHEN detail           IS NULL THEN 'detail'
            WHEN duration_minutes IS NULL THEN 'duration_minutes'
       END AS null_column
FROM   counseling_records
WHERE  name IS NULL
    OR daily_report_id IS NULL
    OR contact_id IS NULL
    OR category IS NULL
    OR detail IS NULL
    OR duration_minutes IS NULL;

-- ************************************************************
-- 4. Picklist 値チェック
--    CHECK 制約外の不正な値が存在しないか検証
--    → 結果が 0 件であること
-- ************************************************************

-- 4-1. accounts.region
SELECT id, name, region AS invalid_value, 'accounts.region' AS check_target
FROM   accounts
WHERE  region NOT IN ('関東', '関西', '中部', '九州', '東北', '北海道');

-- 4-2. daily_reports.visit_purpose
SELECT id, name, visit_purpose AS invalid_value, 'daily_reports.visit_purpose' AS check_target
FROM   daily_reports
WHERE  visit_purpose NOT IN ('定期巡回', '緊急対応', '新規オープン支援', '研修', '監査');

-- 4-3. daily_reports.overall_condition
SELECT id, name, overall_condition AS invalid_value, 'daily_reports.overall_condition' AS check_target
FROM   daily_reports
WHERE  overall_condition NOT IN ('A', 'B', 'C', 'D');

-- 4-4. daily_reports.status
SELECT id, name, status AS invalid_value, 'daily_reports.status' AS check_target
FROM   daily_reports
WHERE  status NOT IN ('下書き', '提出済', '承認済', '差戻し');

-- 4-5. counseling_records.category
SELECT id, name, category AS invalid_value, 'counseling_records.category' AS check_target
FROM   counseling_records
WHERE  category NOT IN ('業務改善', '人材育成', 'クレーム対応', '売上分析', '衛生管理', 'その他');

-- 4-6. counseling_records.duration_minutes (> 0 制約)
SELECT id, name, duration_minutes AS invalid_value, 'counseling_records.duration_minutes' AS check_target
FROM   counseling_records
WHERE  duration_minutes <= 0;

-- ************************************************************
-- 5. カウンセリング記録の整合性
--    日報に紐づくカウンセリング記録件数を検証
-- ************************************************************

-- 5-1. 日報ごとのカウンセリング記録件数サマリー
--      SFDC 側と件数を突合する
SELECT dr.id            AS daily_report_id,
       dr.name          AS daily_report_name,
       dr.report_date,
       COUNT(cr.id)     AS counseling_count
FROM   daily_reports dr
LEFT JOIN counseling_records cr ON cr.daily_report_id = dr.id
GROUP BY dr.id, dr.name, dr.report_date
ORDER BY dr.report_date, dr.name;

-- 5-2. カウンセリング記録がゼロ件の日報
--      業務日報には通常 1 件以上のカウンセリング記録が紐づくことを期待
SELECT dr.id, dr.name, dr.report_date
FROM   daily_reports dr
LEFT JOIN counseling_records cr ON cr.daily_report_id = dr.id
WHERE  cr.id IS NULL
ORDER BY dr.report_date;

-- 5-3. フォローアップ必要だが期限未設定のカウンセリング記録
SELECT cr.id, cr.name, cr.daily_report_id, cr.category
FROM   counseling_records cr
WHERE  cr.follow_up_required = true
  AND  cr.follow_up_date IS NULL;

-- 5-4. フォローアップ期限超過（本日時点）のカウンセリング記録
SELECT cr.id, cr.name, cr.daily_report_id, cr.category,
       cr.follow_up_date,
       CURRENT_DATE - cr.follow_up_date AS overdue_days
FROM   counseling_records cr
WHERE  cr.follow_up_required = true
  AND  cr.follow_up_date < CURRENT_DATE
ORDER BY overdue_days DESC;

-- ************************************************************
-- 6. データ品質サマリーレポート
--    全検証結果を 1 クエリで集約する（ダッシュボード用）
-- ************************************************************

SELECT '1. レコード件数'       AS check_category,
       'accounts'               AS detail,
       COUNT(*)::TEXT            AS result
FROM   accounts
UNION ALL
SELECT '1. レコード件数', 'contacts', COUNT(*)::TEXT FROM contacts
UNION ALL
SELECT '1. レコード件数', 'daily_reports', COUNT(*)::TEXT FROM daily_reports
UNION ALL
SELECT '1. レコード件数', 'counseling_records', COUNT(*)::TEXT FROM counseling_records
UNION ALL
SELECT '2. 孤立レコード', 'contacts→accounts',
       COUNT(*)::TEXT
FROM   contacts c LEFT JOIN accounts a ON c.account_id = a.id
WHERE  c.account_id IS NOT NULL AND a.id IS NULL
UNION ALL
SELECT '2. 孤立レコード', 'daily_reports→accounts',
       COUNT(*)::TEXT
FROM   daily_reports dr LEFT JOIN accounts a ON dr.account_id = a.id
WHERE  a.id IS NULL
UNION ALL
SELECT '2. 孤立レコード', 'counseling→daily_reports',
       COUNT(*)::TEXT
FROM   counseling_records cr LEFT JOIN daily_reports dr ON cr.daily_report_id = dr.id
WHERE  dr.id IS NULL
UNION ALL
SELECT '2. 孤立レコード', 'counseling→contacts',
       COUNT(*)::TEXT
FROM   counseling_records cr LEFT JOIN contacts ct ON cr.contact_id = ct.id
WHERE  cr.contact_id IS NOT NULL AND ct.id IS NULL
UNION ALL
SELECT '4. 不正 Picklist', 'accounts.region',
       COUNT(*)::TEXT
FROM   accounts WHERE region NOT IN ('関東', '関西', '中部', '九州', '東北', '北海道')
UNION ALL
SELECT '4. 不正 Picklist', 'daily_reports.visit_purpose',
       COUNT(*)::TEXT
FROM   daily_reports WHERE visit_purpose NOT IN ('定期巡回', '緊急対応', '新規オープン支援', '研修', '監査')
UNION ALL
SELECT '4. 不正 Picklist', 'daily_reports.status',
       COUNT(*)::TEXT
FROM   daily_reports WHERE status NOT IN ('下書き', '提出済', '承認済', '差戻し')
UNION ALL
SELECT '4. 不正 Picklist', 'counseling_records.category',
       COUNT(*)::TEXT
FROM   counseling_records WHERE category NOT IN ('業務改善', '人材育成', 'クレーム対応', '売上分析', '衛生管理', 'その他')
UNION ALL
SELECT '5. フォローアップ漏れ', '期限未設定',
       COUNT(*)::TEXT
FROM   counseling_records WHERE follow_up_required = true AND follow_up_date IS NULL
UNION ALL
SELECT '5. フォローアップ漏れ', '期限超過',
       COUNT(*)::TEXT
FROM   counseling_records WHERE follow_up_required = true AND follow_up_date < CURRENT_DATE
ORDER BY check_category, detail;
