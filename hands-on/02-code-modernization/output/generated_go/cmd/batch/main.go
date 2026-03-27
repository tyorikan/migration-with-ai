// Package main は Cloud Run Jobs で実行される月次集計バッチのエントリーポイント。
//
// Apex の MonthlyReportBatch（Database.Batchable<sObject>）を Go に変換。
//   - start()  → PostgreSQL カーソルベースのページネーション
//   - execute() → goroutine による並列処理（sync.WaitGroup）
//   - finish() → 集計結果の DB 書き込み + ログ出力
//
// Cloud Scheduler: 毎月1日 AM2:00 (cron: 0 2 1 * *)
//
// 環境変数:
//
//	BATCH_SIZE    — 1バッチあたりの処理件数（デフォルト: 200）
//	TARGET_MONTH  — 集計対象月 YYYY-MM（デフォルト: 前月）
//	DATABASE_URL  — PostgreSQL 接続文字列
package main

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"os"
	"sync"
	"time"

	"daily-report-api/internal/config"

	_ "github.com/lib/pq"
)

// ============================================================
// MonthlySummary — Apex の MonthlySummary 内部クラスに対応
// ============================================================

// MonthlySummary は店舗ごとの月次集計結果。
type MonthlySummary struct {
	AccountID              string `json:"accountId"`
	AccountName            string `json:"accountName"`
	StoreCode              string `json:"storeCode"`
	VisitCount             int    `json:"visitCount"`
	GradeA                 int    `json:"gradeA"`
	GradeB                 int    `json:"gradeB"`
	GradeC                 int    `json:"gradeC"`
	GradeD                 int    `json:"gradeD"`
	TotalCounselingMinutes int    `json:"totalCounselingMinutes"`
	FollowUpTotal          int    `json:"followUpTotal"`
	FollowUpOverdue        int    `json:"followUpOverdue"`

	// 内部: 日報 ID 重複排除用（LEFT JOIN による行膨張対策）
	seenReports map[string]bool `json:"-"`
}

// ============================================================
// reportRow — DB から取得した日報 + カウンセリング記録
// ============================================================

type reportRow struct {
	ReportID         string
	AccountID        string
	AccountName      string
	StoreCode        string
	OverallCondition string
	// カウンセリング記録（JOIN 結果）
	CRDurationMinutes  sql.NullInt64
	CRFollowUpRequired sql.NullBool
	CRFollowUpDate     sql.NullString
}

func main() {
	// ============================================================
	// ロガー初期化
	// ============================================================
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	logger.Info("monthly report batch started")

	// ============================================================
	// 環境変数の読み込み（config パッケージで共通化）
	// ============================================================
	batchSize := config.GetEnvInt("BATCH_SIZE", 200)
	targetMonth := getTargetMonth()
	monthStart := targetMonth
	monthEnd := targetMonth.AddDate(0, 1, -1)

	logger.Info("batch parameters",
		slog.String("targetMonth", targetMonth.Format("2006-01")),
		slog.String("monthStart", monthStart.Format("2006-01-02")),
		slog.String("monthEnd", monthEnd.Format("2006-01-02")),
		slog.Int("batchSize", batchSize),
	)

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

	ctx := context.Background()

	// ============================================================
	// Phase 1: start() — 対象件数の取得
	// Apex: Database.getQueryLocator(SELECT ... FROM DailyReport__c)
	// ============================================================
	totalCount, err := countReports(ctx, db, monthStart, monthEnd)
	if err != nil {
		logger.Error("failed to count reports", slog.String("error", err.Error()))
		os.Exit(1)
	}

	logger.Info("target reports found", slog.Int("totalCount", totalCount))

	if totalCount == 0 {
		logger.Info("no reports to process, exiting")
		os.Exit(0)
	}

	// ============================================================
	// Phase 2: execute() — バッチ処理（ページネーション + 並列集計）
	// Apex: execute(bc, List<DailyReport__c>)
	// ============================================================
	summaryMap := make(map[string]*MonthlySummary)
	var mu sync.Mutex
	var wg sync.WaitGroup
	var processErrors []string

	totalPages := (totalCount + batchSize - 1) / batchSize

	for page := 0; page < totalPages; page++ {
		offset := page * batchSize

		wg.Add(1)
		go func(pageNum, off int) {
			defer wg.Done()

			logger.Info("processing batch",
				slog.Int("page", pageNum+1),
				slog.Int("totalPages", totalPages),
				slog.Int("offset", off),
			)

			rows, err := fetchReportBatch(ctx, db, monthStart, monthEnd, batchSize, off)
			if err != nil {
				mu.Lock()
				processErrors = append(processErrors, fmt.Sprintf("page %d: %v", pageNum+1, err))
				mu.Unlock()
				logger.Error("batch fetch failed",
					slog.Int("page", pageNum+1),
					slog.String("error", err.Error()),
				)
				return
			}

			// 集計（Apex execute() のループに対応）
			mu.Lock()
			for _, row := range rows {
				aggregateRow(summaryMap, row)
			}
			mu.Unlock()

			logger.Info("batch completed",
				slog.Int("page", pageNum+1),
				slog.Int("rowsProcessed", len(rows)),
			)
		}(page, offset)
	}

	wg.Wait()

	// ============================================================
	// Phase 3: finish() — 集計結果の出力 + DB 書き込み
	// Apex: finish(bc)
	// ============================================================
	logger.Info("===== 月次サマリーレポート =====",
		slog.String("period", fmt.Sprintf("%s ～ %s",
			monthStart.Format("2006-01-02"), monthEnd.Format("2006-01-02"))),
	)

	for _, s := range summaryMap {
		logger.Info("store summary",
			slog.String("storeCode", s.StoreCode),
			slog.String("accountName", s.AccountName),
			slog.Int("visitCount", s.VisitCount),
			slog.Int("counselingMinutes", s.TotalCounselingMinutes),
			slog.Int("gradeA", s.GradeA),
			slog.Int("gradeB", s.GradeB),
			slog.Int("gradeC", s.GradeC),
			slog.Int("gradeD", s.GradeD),
			slog.Int("followUpTotal", s.FollowUpTotal),
			slog.Int("followUpOverdue", s.FollowUpOverdue),
		)
	}

	// 集計結果を DB に保存
	if err := saveSummaries(ctx, db, summaryMap, targetMonth); err != nil {
		logger.Error("failed to save summaries", slog.String("error", err.Error()))
		// 部分失敗: ログに記録して続行
		processErrors = append(processErrors, fmt.Sprintf("save summaries: %v", err))
	}

	logger.Info("batch completed",
		slog.Int("storeCount", len(summaryMap)),
		slog.Int("errorCount", len(processErrors)),
	)

	if len(processErrors) > 0 {
		logger.Warn("batch completed with errors")
		for _, e := range processErrors {
			logger.Error("batch error", slog.String("detail", e))
		}
		os.Exit(1) // Cloud Run Jobs に失敗を通知
	}

	logger.Info("monthly report batch finished successfully")
}

// ============================================================
// DB 操作関数
// ============================================================

// countReports は対象期間の承認済み日報件数を取得する。
func countReports(ctx context.Context, db *sql.DB, monthStart, monthEnd time.Time) (int, error) {
	query := `
		SELECT COUNT(*)
		FROM daily_reports
		WHERE status = '承認済'
		  AND report_date >= $1
		  AND report_date <= $2
	`
	var count int
	err := db.QueryRowContext(ctx, query,
		monthStart.Format("2006-01-02"),
		monthEnd.Format("2006-01-02"),
	).Scan(&count)
	return count, err
}

// fetchReportBatch はページネーションで日報 + カウンセリング記録を取得する。
// Apex: Database.QueryLocator → execute() に渡されるバッチに対応。
func fetchReportBatch(ctx context.Context, db *sql.DB, monthStart, monthEnd time.Time, limit, offset int) ([]reportRow, error) {
	query := `
		SELECT
			dr.id,
			dr.account_id,
			a.name AS account_name,
			a.store_code,
			dr.overall_condition,
			cr.duration_minutes,
			cr.follow_up_required,
			cr.follow_up_date
		FROM daily_reports dr
		JOIN accounts a ON dr.account_id = a.id
		LEFT JOIN counseling_records cr ON cr.daily_report_id = dr.id
		WHERE dr.status = '承認済'
		  AND dr.report_date >= $1
		  AND dr.report_date <= $2
		ORDER BY dr.id, cr.id
		LIMIT $3 OFFSET $4
	`

	rows, err := db.QueryContext(ctx, query,
		monthStart.Format("2006-01-02"),
		monthEnd.Format("2006-01-02"),
		limit, offset,
	)
	if err != nil {
		return nil, fmt.Errorf("fetchReportBatch: query failed: %w", err)
	}
	defer rows.Close()

	var results []reportRow
	for rows.Next() {
		var r reportRow
		if err := rows.Scan(
			&r.ReportID, &r.AccountID, &r.AccountName, &r.StoreCode,
			&r.OverallCondition,
			&r.CRDurationMinutes, &r.CRFollowUpRequired, &r.CRFollowUpDate,
		); err != nil {
			return nil, fmt.Errorf("fetchReportBatch: scan failed: %w", err)
		}
		results = append(results, r)
	}

	return results, rows.Err()
}

// aggregateRow は 1 行分のデータを集計マップに加算する。
// Apex: execute() 内のループに対応。
//
// Issue 1 修正: LEFT JOIN で同一日報に複数カウンセリング記録があると行が膨張するため、
// seenReports マップで日報 ID 単位の重複排除を行う。
// VisitCount と評価分布（GradeA-D）は日報単位、カウンセリング集計は行単位。
func aggregateRow(summaryMap map[string]*MonthlySummary, row reportRow) {
	summary, exists := summaryMap[row.AccountID]
	if !exists {
		summary = &MonthlySummary{
			AccountID:   row.AccountID,
			AccountName: row.AccountName,
			StoreCode:   row.StoreCode,
			seenReports: make(map[string]bool),
		}
		summaryMap[row.AccountID] = summary
	}

	// 日報単位のカウント（重複排除）
	if !summary.seenReports[row.ReportID] {
		summary.seenReports[row.ReportID] = true
		summary.VisitCount++

		// 評価分布も日報単位でカウント
		switch row.OverallCondition {
		case "A":
			summary.GradeA++
		case "B":
			summary.GradeB++
		case "C":
			summary.GradeC++
		case "D":
			summary.GradeD++
		}
	}

	// カウンセリング記録の集計（行単位 — 各カウンセリング記録ごとに加算）
	if row.CRDurationMinutes.Valid {
		summary.TotalCounselingMinutes += int(row.CRDurationMinutes.Int64)
	}

	if row.CRFollowUpRequired.Valid && row.CRFollowUpRequired.Bool {
		summary.FollowUpTotal++
		if row.CRFollowUpDate.Valid && row.CRFollowUpDate.String != "" {
			followUpDate, err := time.Parse("2006-01-02", row.CRFollowUpDate.String)
			if err == nil && followUpDate.Before(time.Now()) {
				summary.FollowUpOverdue++
			}
		}
	}
}

// saveSummaries は集計結果を monthly_summaries テーブルに UPSERT で保存する。
// Apex: finish() の System.debug に対応（本番では DB 保存）。
// 冪等性: ON CONFLICT で同月・同店舗の再実行に対応。
func saveSummaries(ctx context.Context, db *sql.DB, summaryMap map[string]*MonthlySummary, targetMonth time.Time) error {
	query := `
		INSERT INTO monthly_summaries (
			id, account_id, target_month,
			visit_count, grade_a, grade_b, grade_c, grade_d,
			total_counseling_minutes, follow_up_total, follow_up_overdue,
			created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $12)
		ON CONFLICT (account_id, target_month) DO UPDATE SET
			visit_count = EXCLUDED.visit_count,
			grade_a = EXCLUDED.grade_a,
			grade_b = EXCLUDED.grade_b,
			grade_c = EXCLUDED.grade_c,
			grade_d = EXCLUDED.grade_d,
			total_counseling_minutes = EXCLUDED.total_counseling_minutes,
			follow_up_total = EXCLUDED.follow_up_total,
			follow_up_overdue = EXCLUDED.follow_up_overdue,
			updated_at = EXCLUDED.updated_at
	`

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("saveSummaries: begin tx failed: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	stmt, err := tx.PrepareContext(ctx, query)
	if err != nil {
		return fmt.Errorf("saveSummaries: prepare failed: %w", err)
	}
	defer stmt.Close()

	now := time.Now()
	monthStr := targetMonth.Format("2006-01")

	for _, s := range summaryMap {
		id := fmt.Sprintf("MS-%s-%s", monthStr, s.StoreCode)
		_, err := stmt.ExecContext(ctx,
			id, s.AccountID, monthStr,
			s.VisitCount, s.GradeA, s.GradeB, s.GradeC, s.GradeD,
			s.TotalCounselingMinutes, s.FollowUpTotal, s.FollowUpOverdue,
			now,
		)
		if err != nil {
			return fmt.Errorf("saveSummaries: insert %s failed: %w", s.StoreCode, err)
		}
	}

	return tx.Commit()
}

// ============================================================
// ヘルパー関数
// ============================================================

// getTargetMonth は TARGET_MONTH 環境変数を解析し、未指定時は前月を返す。
func getTargetMonth() time.Time {
	targetMonthStr := os.Getenv("TARGET_MONTH")
	if targetMonthStr != "" {
		t, err := time.Parse("2006-01", targetMonthStr)
		if err == nil {
			return t
		}
		slog.Warn("invalid TARGET_MONTH, using last month",
			slog.String("value", targetMonthStr),
		)
	}
	// デフォルト: 前月の1日
	now := time.Now()
	return time.Date(now.Year(), now.Month()-1, 1, 0, 0, 0, 0, time.UTC)
}
