// Package main はアプリケーションのエントリーポイント。
// 依存性注入（DI）を行い、各レイヤーを結合してサーバーを起動する。
package main

import (
	"database/sql"
	"fmt"
	"log/slog"
	"net/http"
	"os"

	"daily-report-api/internal/config"
	"daily-report-api/internal/handler"
	"daily-report-api/internal/repository"
	"daily-report-api/internal/usecase"

	_ "github.com/lib/pq" // PostgreSQL ドライバの登録
)

func main() {
	// ============================================================
	// 構造化ロガーの初期化
	// ============================================================
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	// ============================================================
	// DB 接続（config パッケージで DSN を共通構築）
	// ============================================================
	dsn := config.BuildDSN()

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		logger.Error("failed to open database", slog.String("error", err.Error()))
		os.Exit(1)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		logger.Error("failed to ping database", slog.String("error", err.Error()))
		os.Exit(1)
	}
	logger.Info("database connected")

	// ============================================================
	// 依存性注入（DI）— クリーンアーキテクチャのレイヤー結合
	// ============================================================
	// Repository（データアクセス層）
	repo := repository.NewDailyReportRepository(db)

	// UseCase（ビジネスロジック層）← Repository インターフェースを注入
	uc := usecase.NewDailyReportUseCase(repo, logger)

	// Handler（HTTP層）← UseCase インターフェースを注入
	h := handler.NewDailyReportHandler(uc, logger)

	// ============================================================
	// HTTP サーバーの起動
	// ============================================================
	mux := http.NewServeMux()

	// ヘルスチェック
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, `{"status":"ok"}`)
	})

	// 日報 API ルーティング
	h.RegisterRoutes(mux)

	port := config.GetEnvOrDefault("PORT", "8080")
	logger.Info("server starting", slog.String("port", port))

	if err := http.ListenAndServe(":"+port, mux); err != nil {
		logger.Error("server failed", slog.String("error", err.Error()))
		os.Exit(1)
	}
}
