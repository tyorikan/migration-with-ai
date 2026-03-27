-- ============================================================
-- SV 業務日報システム — PostgreSQL DDL
-- SFDC メタデータから AI (Gemini) によって自動生成された期待出力
-- ============================================================

-- 1. フランチャイズ店舗（Account）
CREATE TABLE accounts (
    id              VARCHAR(18) PRIMARY KEY,
    name            VARCHAR(255) NOT NULL,
    store_code      VARCHAR(10)  NOT NULL UNIQUE,
    region          VARCHAR(40)  NOT NULL,
    open_date       DATE,
    is_active       BOOLEAN      DEFAULT true,
    phone           VARCHAR(40),
    billing_city    VARCHAR(40),
    billing_state   VARCHAR(80),
    last_visit_date DATE,
    created_at      TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE  accounts IS 'フランチャイズ店舗（SFDC: Account）';
COMMENT ON COLUMN accounts.store_code IS '店舗コード（例: TK-001）';
COMMENT ON COLUMN accounts.region IS 'エリア（関東/関西/中部/九州/東北/北海道）';

-- 2. 店舗担当者（Contact）
CREATE TABLE contacts (
    id              VARCHAR(18) PRIMARY KEY,
    first_name      VARCHAR(40),
    last_name       VARCHAR(80)  NOT NULL,
    email           VARCHAR(254),
    phone           VARCHAR(40),
    title           VARCHAR(128),
    account_id      VARCHAR(18)  REFERENCES accounts(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE  contacts IS '店舗担当者（SFDC: Contact）';
COMMENT ON COLUMN contacts.account_id IS '所属店舗（Lookup → Account）';
CREATE INDEX idx_contacts_account_id ON contacts(account_id);

-- 3. 業務日報（DailyReport__c）
CREATE TABLE daily_reports (
    id                  VARCHAR(18)  PRIMARY KEY,
    name                VARCHAR(20)  NOT NULL,
    report_date         DATE         NOT NULL,
    supervisor_id       VARCHAR(18)  NOT NULL,
    account_id          VARCHAR(18)  NOT NULL REFERENCES accounts(id) ON DELETE SET NULL,
    visit_start_time    TIMESTAMPTZ  NOT NULL,
    visit_end_time      TIMESTAMPTZ  NOT NULL,
    visit_purpose       VARCHAR(40)  NOT NULL,
    overall_condition   VARCHAR(10)  NOT NULL,
    summary             TEXT,
    next_action         TEXT,
    status              VARCHAR(20)  NOT NULL DEFAULT '下書き',
    approved_by         VARCHAR(18),
    approved_date       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_daily_reports_status
        CHECK (status IN ('下書き', '提出済', '承認済', '差戻し')),
    CONSTRAINT chk_daily_reports_condition
        CHECK (overall_condition IN ('A', 'B', 'C', 'D')),
    CONSTRAINT chk_daily_reports_purpose
        CHECK (visit_purpose IN ('定期巡回', '緊急対応', '新規オープン支援', '研修', '監査'))
);
COMMENT ON TABLE  daily_reports IS '業務日報（SFDC: DailyReport__c）';
COMMENT ON COLUMN daily_reports.supervisor_id IS 'スーパーバイザー（SFDC: User への Lookup）';
COMMENT ON COLUMN daily_reports.overall_condition IS '店舗総合評価（A/B/C/D）';
CREATE INDEX idx_daily_reports_account_id   ON daily_reports(account_id);
CREATE INDEX idx_daily_reports_report_date  ON daily_reports(report_date);
CREATE INDEX idx_daily_reports_status       ON daily_reports(status);
CREATE INDEX idx_daily_reports_supervisor   ON daily_reports(supervisor_id);

-- 4. カウンセリング記録（CounselingRecord__c）
CREATE TABLE counseling_records (
    id                  VARCHAR(18)  PRIMARY KEY,
    name                VARCHAR(20)  NOT NULL,
    daily_report_id     VARCHAR(18)  NOT NULL REFERENCES daily_reports(id) ON DELETE CASCADE,
    contact_id          VARCHAR(18)  NOT NULL REFERENCES contacts(id) ON DELETE SET NULL,
    category            VARCHAR(40)  NOT NULL,
    detail              TEXT         NOT NULL,
    duration_minutes    INTEGER      NOT NULL,
    follow_up_required  BOOLEAN      DEFAULT false,
    follow_up_date      DATE,
    follow_up_note      TEXT,
    created_at          TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_counseling_category
        CHECK (category IN ('業務改善', '人材育成', 'クレーム対応', '売上分析', '衛生管理', 'その他')),
    CONSTRAINT chk_duration_positive
        CHECK (duration_minutes > 0)
);
COMMENT ON TABLE  counseling_records IS 'カウンセリング記録（SFDC: CounselingRecord__c / Master-Detail → DailyReport__c）';
COMMENT ON COLUMN counseling_records.daily_report_id IS '親の業務日報（Master-Detail → ON DELETE CASCADE）';
COMMENT ON COLUMN counseling_records.contact_id IS '対象担当者（Lookup → Contact）';
CREATE INDEX idx_counseling_daily_report_id ON counseling_records(daily_report_id);
CREATE INDEX idx_counseling_contact_id      ON counseling_records(contact_id);
CREATE INDEX idx_counseling_category        ON counseling_records(category);
CREATE INDEX idx_counseling_follow_up       ON counseling_records(follow_up_required, follow_up_date)
    WHERE follow_up_required = true;
