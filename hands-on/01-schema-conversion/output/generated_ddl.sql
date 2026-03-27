-- ============================================================
-- SV 業務日報システム — PostgreSQL DDL
-- SFDC メタデータから AI (Gemini) によって自動生成
-- 生成日時: 2026-03-27
-- ============================================================
-- 変換ルール:
--   テーブル名: snake_case, __c サフィックス除去
--   カラム名  : snake_case, __c サフィックス除去
--   Lookup    : FOREIGN KEY ... ON DELETE SET NULL
--   MasterDetail: FOREIGN KEY ... ON DELETE CASCADE, NOT NULL
--   Picklist  : CHECK 制約で値を制限
--   全テーブルに created_at / updated_at を付与
-- ============================================================

-- ============================================================
-- 1. フランチャイズ店舗（SFDC: Account）
-- 依存: なし（最上位テーブル）
-- ============================================================
CREATE TABLE accounts (
    id              VARCHAR(18)  PRIMARY KEY,
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
    updated_at      TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_accounts_region
        CHECK (region IN ('関東', '関西', '中部', '九州', '東北', '北海道'))
);

-- テーブルコメント
COMMENT ON TABLE  accounts IS 'フランチャイズ店舗（SFDC: Account）';

-- カラムコメント
COMMENT ON COLUMN accounts.id            IS 'レコードID';
COMMENT ON COLUMN accounts.name          IS '店舗名';
COMMENT ON COLUMN accounts.store_code    IS '店舗コード（例: TK-001）';
COMMENT ON COLUMN accounts.region        IS 'エリア（関東/関西/中部/九州/東北/北海道）';
COMMENT ON COLUMN accounts.open_date     IS '開店日';
COMMENT ON COLUMN accounts.is_active     IS '稼働中';
COMMENT ON COLUMN accounts.phone         IS '電話番号';
COMMENT ON COLUMN accounts.billing_city  IS '市区町村';
COMMENT ON COLUMN accounts.billing_state   IS '都道府県';
COMMENT ON COLUMN accounts.last_visit_date IS '最終訪問日（Trigger による自動更新）';
COMMENT ON COLUMN accounts.created_at      IS '作成日時';
COMMENT ON COLUMN accounts.updated_at      IS '更新日時';

-- インデックス: 検索頻度の高い列
-- ※ store_code は UNIQUE 制約で一意インデックスが自動生成されるため明示的なインデックスは不要
CREATE INDEX idx_accounts_region ON accounts(region);

-- ============================================================
-- 2. 店舗担当者（SFDC: Contact）
-- 依存: accounts（Lookup → Account）
-- ============================================================
CREATE TABLE contacts (
    id              VARCHAR(18)  PRIMARY KEY,
    first_name      VARCHAR(40),
    last_name       VARCHAR(80)  NOT NULL,
    email           VARCHAR(254),
    phone           VARCHAR(40),
    title           VARCHAR(128),
    account_id      VARCHAR(18)  REFERENCES accounts(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP
);

-- テーブルコメント
COMMENT ON TABLE  contacts IS '店舗担当者（SFDC: Contact）';

-- カラムコメント
COMMENT ON COLUMN contacts.id         IS 'レコードID';
COMMENT ON COLUMN contacts.first_name IS '名';
COMMENT ON COLUMN contacts.last_name  IS '姓';
COMMENT ON COLUMN contacts.email      IS 'メール';
COMMENT ON COLUMN contacts.phone      IS '電話番号';
COMMENT ON COLUMN contacts.title      IS '役職';
COMMENT ON COLUMN contacts.account_id IS '所属店舗（Lookup → Account / ON DELETE SET NULL）';
COMMENT ON COLUMN contacts.created_at  IS '作成日時';
COMMENT ON COLUMN contacts.updated_at  IS '更新日時';

-- インデックス: 外部キー列
CREATE INDEX idx_contacts_account_id ON contacts(account_id);

-- ============================================================
-- 3. 業務日報（SFDC: DailyReport__c）
-- 依存: accounts（Lookup → Account）
-- 備考: supervisor_id / approved_by は SFDC User への Lookup。
--       User テーブルは本 DDL のスコープ外のため FK 制約なし。
-- ============================================================
CREATE TABLE daily_reports (
    id                  VARCHAR(18)  PRIMARY KEY,
    name                VARCHAR(20)  NOT NULL,              -- AutoNumber: DR-{0000}
    report_date         DATE         NOT NULL,
    supervisor_id       VARCHAR(18)  NOT NULL,              -- Lookup → User（FK なし）
    account_id          VARCHAR(18)  NOT NULL
                        REFERENCES accounts(id) ON DELETE SET NULL,
    visit_start_time    TIMESTAMPTZ  NOT NULL,
    visit_end_time      TIMESTAMPTZ  NOT NULL,
    visit_purpose       VARCHAR(40)  NOT NULL,
    overall_condition   VARCHAR(10)  NOT NULL,
    summary             TEXT,
    next_action         TEXT,
    status              VARCHAR(20)  NOT NULL DEFAULT '下書き',
    approved_by         VARCHAR(18),                        -- Lookup → User（FK なし）
    approved_date       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ  DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_daily_reports_visit_purpose
        CHECK (visit_purpose IN ('定期巡回', '緊急対応', '新規オープン支援', '研修', '監査')),
    CONSTRAINT chk_daily_reports_overall_condition
        CHECK (overall_condition IN ('A', 'B', 'C', 'D')),
    CONSTRAINT chk_daily_reports_status
        CHECK (status IN ('下書き', '提出済', '承認済', '差戻し'))
);

-- テーブルコメント
COMMENT ON TABLE  daily_reports IS '業務日報（SFDC: DailyReport__c）';

-- カラムコメント
COMMENT ON COLUMN daily_reports.id                IS 'レコードID';
COMMENT ON COLUMN daily_reports.name              IS '日報番号（AutoNumber: DR-{0000}）';
COMMENT ON COLUMN daily_reports.report_date       IS '日報日付';
COMMENT ON COLUMN daily_reports.supervisor_id     IS 'スーパーバイザー（SFDC: User への Lookup）';
COMMENT ON COLUMN daily_reports.account_id        IS '訪問先店舗（Lookup → Account / ON DELETE SET NULL）';
COMMENT ON COLUMN daily_reports.visit_start_time  IS '訪問開始時刻';
COMMENT ON COLUMN daily_reports.visit_end_time    IS '訪問終了時刻';
COMMENT ON COLUMN daily_reports.visit_purpose     IS '訪問目的（定期巡回/緊急対応/新規オープン支援/研修/監査）';
COMMENT ON COLUMN daily_reports.overall_condition IS '店舗総合評価（A/B/C/D）';
COMMENT ON COLUMN daily_reports.summary           IS '所見・サマリー';
COMMENT ON COLUMN daily_reports.next_action       IS 'ネクストアクション';
COMMENT ON COLUMN daily_reports.status            IS 'ステータス（下書き/提出済/承認済/差戻し）';
COMMENT ON COLUMN daily_reports.approved_by       IS '承認者（SFDC: User への Lookup）';
COMMENT ON COLUMN daily_reports.approved_date     IS '承認日時';
COMMENT ON COLUMN daily_reports.created_at        IS '作成日時';
COMMENT ON COLUMN daily_reports.updated_at        IS '更新日時';

-- インデックス: 外部キー列 + 検索頻度の高い列
CREATE INDEX idx_daily_reports_account_id   ON daily_reports(account_id);
CREATE INDEX idx_daily_reports_supervisor   ON daily_reports(supervisor_id);
CREATE INDEX idx_daily_reports_report_date  ON daily_reports(report_date);
CREATE INDEX idx_daily_reports_status       ON daily_reports(status);

-- ============================================================
-- 4. カウンセリング記録（SFDC: CounselingRecord__c）
-- 依存: daily_reports（MasterDetail → DailyReport__c）
--       contacts（Lookup → Contact）
-- ============================================================
CREATE TABLE counseling_records (
    id                  VARCHAR(18)  PRIMARY KEY,
    name                VARCHAR(20)  NOT NULL,              -- AutoNumber: CR-{0000}
    daily_report_id     VARCHAR(18)  NOT NULL
                        REFERENCES daily_reports(id) ON DELETE CASCADE,
    contact_id          VARCHAR(18)  NOT NULL
                        REFERENCES contacts(id) ON DELETE SET NULL,
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

-- テーブルコメント
COMMENT ON TABLE  counseling_records IS 'カウンセリング記録（SFDC: CounselingRecord__c / MasterDetail → DailyReport__c）';

-- カラムコメント
COMMENT ON COLUMN counseling_records.id                IS 'レコードID';
COMMENT ON COLUMN counseling_records.name              IS '記録番号（AutoNumber: CR-{0000}）';
COMMENT ON COLUMN counseling_records.daily_report_id   IS '親の業務日報（MasterDetail → ON DELETE CASCADE）';
COMMENT ON COLUMN counseling_records.contact_id        IS '対象担当者（Lookup → Contact / ON DELETE SET NULL）';
COMMENT ON COLUMN counseling_records.category          IS 'カウンセリング分類（業務改善/人材育成/クレーム対応/売上分析/衛生管理/その他）';
COMMENT ON COLUMN counseling_records.detail            IS '内容詳細';
COMMENT ON COLUMN counseling_records.duration_minutes  IS '所要時間（分）';
COMMENT ON COLUMN counseling_records.follow_up_required IS 'フォローアップ要否';
COMMENT ON COLUMN counseling_records.follow_up_date    IS 'フォローアップ予定日';
COMMENT ON COLUMN counseling_records.follow_up_note    IS 'フォローアップメモ';
COMMENT ON COLUMN counseling_records.created_at        IS '作成日時';
COMMENT ON COLUMN counseling_records.updated_at        IS '更新日時';

-- インデックス: 外部キー列 + 検索頻度の高い列
CREATE INDEX idx_counseling_daily_report_id ON counseling_records(daily_report_id);
CREATE INDEX idx_counseling_contact_id      ON counseling_records(contact_id);
CREATE INDEX idx_counseling_category        ON counseling_records(category);
CREATE INDEX idx_counseling_follow_up       ON counseling_records(follow_up_required, follow_up_date)
    WHERE follow_up_required = true;
