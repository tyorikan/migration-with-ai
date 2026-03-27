-- ============================================================
-- SV 業務日報システム — PostgreSQL 変換済みクエリ集
-- SOQL から AI (Gemini) によって自動変換
-- 生成日時: 2026-03-27
-- ============================================================
-- 変換ルール:
--   リレーション参照（ドット記法）→ JOIN + ON 句
--   THIS_MONTH  → date_trunc('month', CURRENT_DATE)
--   TODAY       → CURRENT_DATE
--   LAST_N_DAYS → CURRENT_DATE - INTERVAL 'N days'
--   テーブル名・カラム名は DDL の snake_case 命名に準拠
-- ============================================================


-- ============================================================
-- Q1: 特定エリアの提出済み日報一覧（リレーション参照）
-- ============================================================
-- 変換ポイント:
--   Account__r.Name, Account__r.StoreCode__c, Account__r.Region__c
--   → JOIN accounts a ON dr.account_id = a.id
--   Account__r.Region__c = '関東' → a.region = '関東'
-- ============================================================
SELECT
    dr.id,
    dr.name,
    dr.report_date,
    a.name            AS account_name,
    a.store_code      AS account_store_code,
    a.region          AS account_region,
    dr.overall_condition,
    dr.status
FROM daily_reports dr
JOIN accounts a ON dr.account_id = a.id
WHERE a.region = '関東'
  AND dr.status = '提出済'
ORDER BY dr.report_date DESC
LIMIT 50;

-- 推奨インデックス（既存 DDL で対応済み）:
--   idx_accounts_region          ON accounts(region)
--   idx_daily_reports_status     ON daily_reports(status)
--   idx_daily_reports_account_id ON daily_reports(account_id)
-- 追加提案:
--   複合インデックスで WHERE + ORDER BY を効率化
-- CREATE INDEX idx_dr_status_report_date ON daily_reports(status, report_date DESC);


-- ============================================================
-- Q2: 今月の店舗別訪問回数と平均評価（集計クエリ）
-- ============================================================
-- 変換ポイント:
--   THIS_MONTH → date_trunc('month', CURRENT_DATE)
--   COUNT(Id)  → COUNT(dr.id)
--   Account__r → JOIN accounts
-- ============================================================
SELECT
    dr.account_id,
    a.name            AS account_name,
    a.store_code      AS account_store_code,
    COUNT(dr.id)      AS visit_count,
    COUNT(dr.overall_condition) AS condition_count
FROM daily_reports dr
JOIN accounts a ON dr.account_id = a.id
WHERE dr.report_date >= date_trunc('month', CURRENT_DATE)
  AND dr.status IN ('提出済', '承認済')
GROUP BY dr.account_id, a.name, a.store_code
HAVING COUNT(dr.id) > 0
ORDER BY visit_count DESC;

-- 推奨インデックス（既存 DDL で対応済み）:
--   idx_daily_reports_report_date ON daily_reports(report_date)
--   idx_daily_reports_status      ON daily_reports(status)
--   idx_daily_reports_account_id  ON daily_reports(account_id)
-- 追加提案:
--   集計クエリの WHERE 効率化用複合インデックス
-- CREATE INDEX idx_dr_date_status ON daily_reports(report_date, status);


-- ============================================================
-- Q3: フォローアップが未完了のカウンセリング記録（子→親リレーション）
-- ============================================================
-- 変換ポイント:
--   DailyReport__r.Name → JOIN daily_reports dr ON cr.daily_report_id = dr.id
--   DailyReport__r.Account__r.Name → 多段 JOIN（dr → accounts）
--   Contact__r.LastName → JOIN contacts c ON cr.contact_id = c.id
--   TODAY → CURRENT_DATE
-- ============================================================
SELECT
    cr.id,
    cr.name,
    cr.category,
    cr.detail,
    cr.duration_minutes,
    cr.follow_up_date,
    cr.follow_up_note,
    dr.name           AS daily_report_name,
    dr.report_date    AS daily_report_date,
    a.name            AS account_name,
    c.last_name       AS contact_last_name,
    c.email           AS contact_email
FROM counseling_records cr
JOIN daily_reports dr ON cr.daily_report_id = dr.id
JOIN accounts a       ON dr.account_id = a.id
JOIN contacts c       ON cr.contact_id = c.id
WHERE cr.follow_up_required = true
  AND cr.follow_up_date <= CURRENT_DATE
  AND dr.status = '承認済'
ORDER BY cr.follow_up_date ASC;

-- 推奨インデックス（既存 DDL で対応済み）:
--   idx_counseling_follow_up        ON counseling_records(follow_up_required, follow_up_date) WHERE follow_up_required = true
--   idx_counseling_daily_report_id  ON counseling_records(daily_report_id)
--   idx_counseling_contact_id       ON counseling_records(contact_id)
--   idx_daily_reports_status        ON daily_reports(status)


-- ============================================================
-- Q4: 過去30日間のカウンセリング分類別集計
-- ============================================================
-- 変換ポイント:
--   LAST_N_DAYS:30 → CURRENT_DATE - INTERVAL '30 days'
--   DailyReport__r.ReportDate__c → JOIN daily_reports で dr.report_date
--   DailyReport__r.Status__c → dr.status
--   COUNT(Id) → COUNT(cr.id)
--   SUM(DurationMinutes__c) → SUM(cr.duration_minutes)
-- ============================================================
SELECT
    cr.category,
    COUNT(cr.id)              AS record_count,
    SUM(cr.duration_minutes)  AS total_duration_minutes
FROM counseling_records cr
JOIN daily_reports dr ON cr.daily_report_id = dr.id
WHERE dr.report_date >= CURRENT_DATE - INTERVAL '30 days'
  AND dr.status = '承認済'
GROUP BY cr.category
ORDER BY total_duration_minutes DESC;

-- 推奨インデックス（既存 DDL で対応済み）:
--   idx_counseling_daily_report_id ON counseling_records(daily_report_id)
--   idx_counseling_category        ON counseling_records(category)
--   idx_daily_reports_report_date  ON daily_reports(report_date)
--   idx_daily_reports_status       ON daily_reports(status)
-- 追加提案:
--   日報側の WHERE 効率化用複合インデックス
-- CREATE INDEX idx_dr_date_status ON daily_reports(report_date, status);


-- ============================================================
-- Q5: 評価が C 以下の店舗で最新の日報を取得
-- ============================================================
-- 変換ポイント:
--   LAST_N_DAYS:90 → CURRENT_DATE - INTERVAL '90 days'
--   Account__r.Name, Account__r.StoreCode__c → JOIN accounts
-- ============================================================
SELECT
    dr.id,
    dr.name,
    dr.report_date,
    a.name            AS account_name,
    a.store_code      AS account_store_code,
    dr.overall_condition,
    dr.summary,
    dr.next_action
FROM daily_reports dr
JOIN accounts a ON dr.account_id = a.id
WHERE dr.overall_condition IN ('C', 'D')
  AND dr.report_date >= CURRENT_DATE - INTERVAL '90 days'
  AND dr.status = '承認済'
ORDER BY dr.report_date DESC
LIMIT 100;

-- 推奨インデックス（既存 DDL で対応済み）:
--   idx_daily_reports_account_id   ON daily_reports(account_id)
--   idx_daily_reports_report_date  ON daily_reports(report_date)
--   idx_daily_reports_status       ON daily_reports(status)
-- 追加提案:
--   Q5 の WHERE 条件に特化した複合インデックス
-- CREATE INDEX idx_dr_condition_date_status
--     ON daily_reports(overall_condition, report_date DESC, status);
