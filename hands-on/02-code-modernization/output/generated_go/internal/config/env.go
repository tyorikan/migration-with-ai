// Package config はアプリケーション共通の設定ヘルパーを提供する。
// cmd/server と cmd/batch の両方から利用される。
package config

import (
	"fmt"
	"os"
	"strconv"
)

// GetEnvOrDefault は環境変数を取得し、未設定時はデフォルト値を返す。
func GetEnvOrDefault(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

// GetEnvInt は環境変数を int で取得し、未設定時はデフォルト値を返す。
func GetEnvInt(key string, defaultVal int) int {
	val := os.Getenv(key)
	if val == "" {
		return defaultVal
	}
	v, err := strconv.Atoi(val)
	if err != nil {
		return defaultVal
	}
	return v
}

// BuildDSN は環境変数から PostgreSQL DSN を組み立てる。
// DATABASE_URL が設定されていればそれを使い、なければ個別の環境変数から構築する。
func BuildDSN() string {
	dsn := os.Getenv("DATABASE_URL")
	if dsn != "" {
		return dsn
	}

	host := GetEnvOrDefault("DB_HOST", "localhost")
	port := GetEnvOrDefault("DB_PORT", "5432")
	user := GetEnvOrDefault("DB_USER", "postgres")
	password := GetEnvOrDefault("DB_PASSWORD", "postgres")
	dbname := GetEnvOrDefault("DB_NAME", "daily_report")
	sslmode := GetEnvOrDefault("DB_SSLMODE", "disable")

	return fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s",
		host, port, user, password, dbname, sslmode)
}
