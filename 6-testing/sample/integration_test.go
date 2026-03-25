package integration_test

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"testing"

	// Testcontainers for Go
	// go get github.com/testcontainers/testcontainers-go
	// go get github.com/testcontainers/testcontainers-go/modules/postgres
	// go get github.com/lib/pq

	_ "github.com/lib/pq"
)

// =============================================================================
// Testcontainers を使った PostgreSQL 統合テスト
// =============================================================================
// ローカル開発環境や CI (Cloud Build) 環境で、実際の PostgreSQL コンテナを
// 起動して CRUD 操作を検証する統合テストのサンプルです。
//
// Testcontainers の利点:
//   - テスト専用の使い捨て DB コンテナを自動で起動・破棄
//   - Cloud SQL の接続情報が不要（ローカル完結）
//   - CI でも同じテストがそのまま動作
//
// 実行:
//   go test -v -tags=integration ./integration/...
//
// Cloud Build での実行:
//   Cloud Build の Docker-in-Docker サポートにより、
//   Cloud Build ステップ内で Testcontainers を使用可能。
//   cloudbuild.yaml の例は 4-infra-pipeline を参照。
// =============================================================================

// --- DDL (テスト用スキーマ) ---
// 2-database-migration/scripts/ の DDL と同期させる

const createTableSQL = `
CREATE TABLE IF NOT EXISTS accounts (
    id                   VARCHAR(18) PRIMARY KEY,
    name                 VARCHAR(255) NOT NULL,
    account_type         VARCHAR(100),
    industry             VARCHAR(100),
    annual_revenue       NUMERIC(18,2),
    number_of_employees  INTEGER,
    phone                VARCHAR(40),
    website              TEXT,
    billing_city         VARCHAR(255),
    owner_id             VARCHAR(18),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted           BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS contacts (
    id          VARCHAR(18) PRIMARY KEY,
    account_id  VARCHAR(18),
    last_name   VARCHAR(80) NOT NULL,
    first_name  VARCHAR(40),
    email       VARCHAR(254),
    phone       VARCHAR(40),
    do_not_call BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
);
`

// testDB はテスト用のデータベース接続を保持します。
// TestMain で初期化され、全テストで共有されます。
var testDB *sql.DB

// TestMain はテストスイート全体のセットアップ・ティアダウンを行います。
func TestMain(m *testing.M) {
	// =================================================================
	// Testcontainers を使用する場合のセットアップ例:
	//
	// ctx := context.Background()
	//
	// pgContainer, err := postgres.Run(ctx,
	//     "postgres:16-alpine",
	//     postgres.WithDatabase("sfdc_migration_test"),
	//     postgres.WithUsername("test_user"),
	//     postgres.WithPassword("test_password"),
	//     postgres.BasicWaitStrategies(),
	// )
	// if err != nil {
	//     log.Fatalf("Failed to start PostgreSQL container: %v", err)
	// }
	// defer pgContainer.Terminate(ctx)
	//
	// connStr, err := pgContainer.ConnectionString(ctx, "sslmode=disable")
	// if err != nil {
	//     log.Fatalf("Failed to get connection string: %v", err)
	// }
	// =================================================================

	// 簡易版: 環境変数から接続情報を取得
	connStr := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		getEnvOrDefault("DB_HOST", "localhost"),
		getEnvOrDefault("DB_PORT", "5432"),
		getEnvOrDefault("DB_USER", "test_user"),
		getEnvOrDefault("DB_PASSWORD", "test_password"),
		getEnvOrDefault("DB_NAME", "sfdc_migration_test"),
	)

	var err error
	testDB, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Printf("SKIP: PostgreSQL に接続できません (統合テストをスキップ): %v", err)
		os.Exit(0) // テストをスキップ（CI でDB接続がない場合にも対応）
	}

	if err = testDB.Ping(); err != nil {
		log.Printf("SKIP: PostgreSQL に接続できません (統合テストをスキップ): %v", err)
		os.Exit(0)
	}

	// スキーマの初期化
	if _, err = testDB.Exec(createTableSQL); err != nil {
		log.Fatalf("Failed to create tables: %v", err)
	}

	// テスト実行
	exitCode := m.Run()

	// クリーンアップ
	testDB.Close()
	os.Exit(exitCode)
}

// =============================================================================
// 統合テスト: Account CRUD
// =============================================================================

func TestIntegration_CreateAndGetAccount(t *testing.T) {
	if testDB == nil {
		t.Skip("DB 接続が利用できないためスキップ")
	}
	ctx := context.Background()

	// Arrange: テストデータの準備
	cleanup(t, "accounts", "TEST_INT_001")

	// Act: INSERT
	_, err := testDB.ExecContext(ctx,
		`INSERT INTO accounts (id, name, industry, annual_revenue, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, NOW(), NOW())`,
		"TEST_INT_001", "統合テスト株式会社", "Technology", 5000000.75,
	)
	if err != nil {
		t.Fatalf("INSERT failed: %v", err)
	}

	// Assert: SELECT で取得して検証
	var (
		id            string
		name          string
		industry      sql.NullString
		annualRevenue sql.NullFloat64
	)
	err = testDB.QueryRowContext(ctx,
		"SELECT id, name, industry, annual_revenue FROM accounts WHERE id = $1",
		"TEST_INT_001",
	).Scan(&id, &name, &industry, &annualRevenue)

	if err != nil {
		t.Fatalf("SELECT failed: %v", err)
	}

	if id != "TEST_INT_001" {
		t.Errorf("id = %q, want %q", id, "TEST_INT_001")
	}
	if name != "統合テスト株式会社" {
		t.Errorf("name = %q, want %q", name, "統合テスト株式会社")
	}
	if !industry.Valid || industry.String != "Technology" {
		t.Errorf("industry = %v, want %q", industry, "Technology")
	}
	if !annualRevenue.Valid || annualRevenue.Float64 != 5000000.75 {
		t.Errorf("annual_revenue = %v, want %v", annualRevenue, 5000000.75)
	}
}

func TestIntegration_ContactForeignKey(t *testing.T) {
	if testDB == nil {
		t.Skip("DB 接続が利用できないためスキップ")
	}
	ctx := context.Background()

	// Arrange: 親 Account を作成
	cleanup(t, "contacts", "TEST_CONTACT_001")
	cleanup(t, "accounts", "TEST_ACCT_FK")

	_, err := testDB.ExecContext(ctx,
		`INSERT INTO accounts (id, name, created_at, updated_at)
		 VALUES ($1, $2, NOW(), NOW())`,
		"TEST_ACCT_FK", "FK テスト親アカウント",
	)
	if err != nil {
		t.Fatalf("INSERT account failed: %v", err)
	}

	// Act: 子 Contact を作成（FK 参照あり）
	_, err = testDB.ExecContext(ctx,
		`INSERT INTO contacts (id, account_id, last_name, created_at, updated_at)
		 VALUES ($1, $2, $3, NOW(), NOW())`,
		"TEST_CONTACT_001", "TEST_ACCT_FK", "山田",
	)
	if err != nil {
		t.Fatalf("INSERT contact failed: %v", err)
	}

	// Assert: 親を削除すると子の account_id が NULL になる (ON DELETE SET NULL)
	_, err = testDB.ExecContext(ctx, "DELETE FROM accounts WHERE id = $1", "TEST_ACCT_FK")
	if err != nil {
		t.Fatalf("DELETE account failed: %v", err)
	}

	var accountID sql.NullString
	err = testDB.QueryRowContext(ctx,
		"SELECT account_id FROM contacts WHERE id = $1", "TEST_CONTACT_001",
	).Scan(&accountID)
	if err != nil {
		t.Fatalf("SELECT contact failed: %v", err)
	}

	if accountID.Valid {
		t.Errorf("account_id should be NULL after parent deletion, got %q", accountID.String)
	}
}

func TestIntegration_BulkInsertPerformance(t *testing.T) {
	if testDB == nil {
		t.Skip("DB 接続が利用できないためスキップ")
	}
	ctx := context.Background()

	const batchSize = 1000

	// Arrange: トランザクションでバッチインサート
	tx, err := testDB.BeginTx(ctx, nil)
	if err != nil {
		t.Fatalf("BEGIN failed: %v", err)
	}
	defer tx.Rollback() // テスト後にロールバック（クリーンアップ）

	stmt, err := tx.PrepareContext(ctx,
		`INSERT INTO accounts (id, name, industry, created_at, updated_at)
		 VALUES ($1, $2, $3, NOW(), NOW())
		 ON CONFLICT (id) DO NOTHING`,
	)
	if err != nil {
		t.Fatalf("PREPARE failed: %v", err)
	}
	defer stmt.Close()

	// Act: 1000 件の一括挿入
	for i := 0; i < batchSize; i++ {
		id := fmt.Sprintf("BULK_%06d", i)
		name := fmt.Sprintf("バルク挿入テスト企業 %d", i)
		_, err := stmt.ExecContext(ctx, id, name, "Technology")
		if err != nil {
			t.Fatalf("INSERT #%d failed: %v", i, err)
		}
	}

	// Assert: 件数の確認
	var count int
	err = tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM accounts WHERE id LIKE 'BULK_%'").Scan(&count)
	if err != nil {
		t.Fatalf("COUNT failed: %v", err)
	}
	if count != batchSize {
		t.Errorf("inserted count = %d, want %d", count, batchSize)
	}

	t.Logf("✅ %d 件のバルクインサート成功", count)
	// tx.Rollback() は defer で実行される（テストデータのクリーンアップ）
}

// --- ヘルパー関数 ---

func cleanup(t *testing.T, table, id string) {
	t.Helper()
	// contacts が accounts を参照している場合、contacts を先に削除
	if table == "accounts" {
		testDB.Exec("DELETE FROM contacts WHERE account_id = $1", id)
	}
	testDB.Exec(fmt.Sprintf("DELETE FROM %s WHERE id = $1", table), id)
}

func getEnvOrDefault(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}
