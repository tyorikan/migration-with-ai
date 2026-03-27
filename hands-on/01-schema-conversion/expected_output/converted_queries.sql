-- ============================================================
-- SOQL → PostgreSQL SQL 変換結果（期待出力）
-- AI (Gemini) による変換 + インデックス提案
-- ============================================================

-- Q1: 特定エリアの提出済み日報一覧（リレーション参照 → JOIN）
-- 元 SOQL: SELECT ... FROM DailyReport__c WHERE Account__r.Region__c = '関東' ...
SELECT
    dr.id,
    dr.name         AS report_number,
    dr.report_date,
    a.name          AS account_name,
    a.store_code,
    a.region,
    dr.overall_condition,
    dr.status
FROM daily_reports dr
JOIN accounts a ON dr.account_id = a.id
WHERE a.region = '関東'
  AND dr.status = '提出済'
ORDER BY dr.report_date DESC
LIMIT 50;

-- 推奨インデックス（既に ddl.sql で作成済み）:
-- CREATE INDEX idx_daily_reports_status ON daily_reports(status);


-- Q2: 今月の店舗別訪問回数（集計クエリ + THIS_MONTH 変換）
-- 元 SOQL: ... WHERE ReportDate__c >= THIS_MONTH ...
SELECT
    dr.account_id,
    a.name          AS account_name,
    a.store_code,
    COUNT(dr.id)    AS visit_count
FROM daily_reports dr
JOIN accounts a ON dr.account_id = a.id
WHERE dr.report_date >= date_trunc('month', CURRENT_DATE)
  AND dr.status IN ('提出済', '承認済')
GROUP BY dr.account_id, a.name, a.store_code
HAVING COUNT(dr.id) > 0
ORDER BY visit_count DESC;

-- 推奨インデックス:
-- CREATE INDEX idx_daily_reports_date_status ON daily_reports(report_date, status);


-- Q3: フォローアップ未完了のカウンセリング記録（子→親リレーション → 多段 JOIN）
-- 元 SOQL: ... DailyReport__r.Account__r.Name ...
SELECT
    cr.id,
    cr.name           AS record_number,
    cr.category,
    cr.detail,
    cr.duration_minutes,
    cr.follow_up_date,
    cr.follow_up_note,
    dr.name           AS report_number,
    dr.report_date,
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

-- 推奨インデックス（部分インデックス、既に ddl.sql で作成済み）:
-- CREATE INDEX idx_counseling_follow_up ON counseling_records(follow_up_required, follow_up_date)
--     WHERE follow_up_required = true;


-- Q4: 過去30日間のカウンセリング分類別集計（LAST_N_DAYS:30 変換）
-- 元 SOQL: ... WHERE DailyReport__r.ReportDate__c >= LAST_N_DAYS:30 ...
SELECT
    cr.category,
    COUNT(cr.id)              AS record_count,
    SUM(cr.duration_minutes)  AS total_minutes
FROM counseling_records cr
JOIN daily_reports dr ON cr.daily_report_id = dr.id
WHERE dr.report_date >= CURRENT_DATE - INTERVAL '30 days'
  AND dr.status = '承認済'
GROUP BY cr.category
ORDER BY total_minutes DESC;


-- Q5: 評価 C 以下の店舗の直近日報（LAST_N_DAYS:90 変換）
-- 元 SOQL: ... WHERE OverallCondition__c IN ('C', 'D') AND ReportDate__c >= LAST_N_DAYS:90 ...
SELECT
    dr.id,
    dr.name           AS report_number,
    dr.report_date,
    a.name            AS account_name,
    a.store_code,
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

-- 推奨インデックス:
-- CREATE INDEX idx_daily_reports_condition_date ON daily_reports(overall_condition, report_date)
--     WHERE overall_condition IN ('C', 'D');
