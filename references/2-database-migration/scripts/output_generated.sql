```sql
CREATE TABLE account (
    id VARCHAR(18) PRIMARY KEY,
    name VARCHAR(255),
    type VARCHAR(255),
    annual_revenue NUMERIC,
    created_date TIMESTAMP
);

COMMENT ON TABLE account IS '取引先';
COMMENT ON COLUMN account.id IS '取引先 ID';
COMMENT ON COLUMN account.name IS '取引先名';
COMMENT ON COLUMN account.type IS '種別';
COMMENT ON COLUMN account.annual_revenue IS '年間売上';
COMMENT ON COLUMN account.created_date IS '作成日';

CREATE TABLE contact (
    id VARCHAR(18) PRIMARY KEY,
    account_id VARCHAR(18),
    last_name VARCHAR(80),
    first_name VARCHAR(40),
    email VARCHAR(255),
    do_not_call BOOLEAN,
    CONSTRAINT fk_contact_account_id FOREIGN KEY (account_id) REFERENCES account(id)
);

COMMENT ON TABLE contact IS '責任者';
COMMENT ON COLUMN contact.id IS '責任者 ID';
COMMENT ON COLUMN contact.account_id IS '取引先 ID';
COMMENT ON COLUMN contact.last_name IS '姓';
COMMENT ON COLUMN contact.first_name IS '名';
COMMENT ON COLUMN contact.email IS 'メール';
COMMENT ON COLUMN contact.do_not_call IS '電話拒否';
```