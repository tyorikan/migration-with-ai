// Package config の環境変数ヘルパーテスト。
// t.Setenv() を使い並列安全に環境変数を操作する。
package config

import (
	"strings"
	"testing"
)

// ============================================================
// GetEnvOrDefault テスト
// ============================================================

func TestGetEnvOrDefault_Set(t *testing.T) {
	t.Setenv("TEST_ENV_KEY", "hello")
	if got := GetEnvOrDefault("TEST_ENV_KEY", "default"); got != "hello" {
		t.Errorf("GetEnvOrDefault() = %q, want %q", got, "hello")
	}
}

func TestGetEnvOrDefault_Unset(t *testing.T) {
	if got := GetEnvOrDefault("TEST_NO_SUCH_KEY_12345", "fallback"); got != "fallback" {
		t.Errorf("GetEnvOrDefault() = %q, want %q", got, "fallback")
	}
}

func TestGetEnvOrDefault_EmptyValue(t *testing.T) {
	t.Setenv("TEST_EMPTY_KEY", "")
	if got := GetEnvOrDefault("TEST_EMPTY_KEY", "default"); got != "default" {
		t.Errorf("空文字の場合はデフォルト値が返るべき: got %q", got)
	}
}

// ============================================================
// GetEnvInt テスト
// ============================================================

func TestGetEnvInt_ValidInt(t *testing.T) {
	t.Setenv("TEST_INT_KEY", "42")
	if got := GetEnvInt("TEST_INT_KEY", 0); got != 42 {
		t.Errorf("GetEnvInt() = %d, want %d", got, 42)
	}
}

func TestGetEnvInt_Unset(t *testing.T) {
	if got := GetEnvInt("TEST_NO_SUCH_INT_KEY", 99); got != 99 {
		t.Errorf("GetEnvInt() = %d, want %d", got, 99)
	}
}

func TestGetEnvInt_InvalidString(t *testing.T) {
	t.Setenv("TEST_INT_INVALID", "not-a-number")
	if got := GetEnvInt("TEST_INT_INVALID", 10); got != 10 {
		t.Errorf("不正な数値の場合はデフォルト値: got %d, want %d", got, 10)
	}
}

func TestGetEnvInt_NegativeValue(t *testing.T) {
	t.Setenv("TEST_INT_NEG", "-5")
	if got := GetEnvInt("TEST_INT_NEG", 0); got != -5 {
		t.Errorf("GetEnvInt() = %d, want %d", got, -5)
	}
}

// ============================================================
// BuildDSN テスト
// ============================================================

func TestBuildDSN_DatabaseURL(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:pass@host:5432/mydb")
	got := BuildDSN()
	if got != "postgres://user:pass@host:5432/mydb" {
		t.Errorf("DATABASE_URL 設定時はそのまま返すべき: got %q", got)
	}
}

func TestBuildDSN_IndividualEnvVars(t *testing.T) {
	// DATABASE_URL を未設定にして個別変数でテスト
	t.Setenv("DATABASE_URL", "")
	t.Setenv("DB_HOST", "myhost")
	t.Setenv("DB_PORT", "5433")
	t.Setenv("DB_USER", "appuser")
	t.Setenv("DB_PASSWORD", "secret")
	t.Setenv("DB_NAME", "appdb")
	t.Setenv("DB_SSLMODE", "require")

	got := BuildDSN()
	for _, want := range []string{"host=myhost", "port=5433", "user=appuser", "password=secret", "dbname=appdb", "sslmode=require"} {
		if !strings.Contains(got, want) {
			t.Errorf("BuildDSN() = %q, should contain %q", got, want)
		}
	}
}

func TestBuildDSN_DefaultValues(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	// DB_* を未設定にするため空に
	t.Setenv("DB_HOST", "")
	t.Setenv("DB_PORT", "")
	t.Setenv("DB_USER", "")
	t.Setenv("DB_PASSWORD", "")
	t.Setenv("DB_NAME", "")
	t.Setenv("DB_SSLMODE", "")

	got := BuildDSN()
	for _, want := range []string{"host=localhost", "port=5432", "user=postgres", "dbname=daily_report", "sslmode=disable"} {
		if !strings.Contains(got, want) {
			t.Errorf("BuildDSN() defaults: %q should contain %q", got, want)
		}
	}
}
