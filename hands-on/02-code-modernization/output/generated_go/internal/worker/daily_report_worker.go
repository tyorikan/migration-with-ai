// Package worker はイベント駆動アーキテクチャのワーカー側を提供する。
// 日報提出イベントを受信し、以下の処理をアトミックに実行する:
//   1. 店舗の最終訪問日を更新
//   2. フォローアップが必要なカウンセリング記録に対してタスクを作成
//
// 冪等性: 同じイベントが複数回届いても安全な設計。
//   - 最終訪問日: UPSERT（同じ日付なら上書きしても同値）
//   - タスク: counseling_record_id による重複チェック
package worker

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"daily-report-api/internal/event"

	"github.com/google/uuid"
)

// ============================================================
// ワーカーインターフェース
// ============================================================

// EventWorker はイベントを処理するワーカーのインターフェース。
type EventWorker interface {
	HandleReportSubmitted(ctx context.Context, data []byte) error
}

// ============================================================
// DailyReportWorker 実装
// ============================================================

// DailyReportWorker は日報提出イベントを処理するワーカー。
// Apex Trigger の after update ロジックに対応する。
type DailyReportWorker struct {
	db     *sql.DB
	logger *slog.Logger
}

// NewDailyReportWorker は DailyReportWorker の新しいインスタンスを生成する。
func NewDailyReportWorker(db *sql.DB, logger *slog.Logger) *DailyReportWorker {
	return &DailyReportWorker{db: db, logger: logger}
}

// HandleReportSubmitted は日報提出イベントを処理する。
// Apex Trigger の for ループ内ロジックをイベント単位で実行。
//
// 冪等性の保証:
//   - 最終訪問日: report_date が同じなら結果は同じ（冪等）
//   - タスク: counseling_record_id と daily_report_id の組み合わせで重複チェック
func (w *DailyReportWorker) HandleReportSubmitted(ctx context.Context, data []byte) error {
	// イベントのデシリアライズ
	var evt event.ReportSubmittedEvent
	if err := json.Unmarshal(data, &evt); err != nil {
		return fmt.Errorf("HandleReportSubmitted: unmarshal failed: %w", err)
	}

	w.logger.Info("processing report.submitted event",
		slog.String("eventId", evt.EventID),
		slog.String("reportId", evt.ReportID),
		slog.String("accountId", evt.AccountID),
	)

	// トランザクション内でアトミックに処理
	tx, err := w.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("HandleReportSubmitted: begin tx failed: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	// 1. 店舗の最終訪問日を更新
	//    Apex: acc.put('LastVisitDate__c', newReport.ReportDate__c)
	//    冪等性: 同じ report_date で何度更新しても同じ結果
	if err := w.updateLastVisitDate(ctx, tx, evt.AccountID, evt.ReportDate); err != nil {
		return err
	}

	// 2. フォローアップタスクの作成
	//    Apex: SELECT ... WHERE FollowUpRequired__c = true → insert Task
	if err := w.createFollowUpTasks(ctx, tx, evt); err != nil {
		return err
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("HandleReportSubmitted: commit failed: %w", err)
	}

	w.logger.Info("event processed successfully",
		slog.String("eventId", evt.EventID),
		slog.String("reportId", evt.ReportID),
	)

	return nil
}

// ============================================================
// プライベートメソッド
// ============================================================

// updateLastVisitDate は店舗の最終訪問日を更新する。
// Apex Trigger の以下のロジックに対応:
//
//	acc.put('LastVisitDate__c', newReport.ReportDate__c)
//
// last_visit_date カラムは Step 1 の DDL (accounts テーブル) で定義済み。
func (w *DailyReportWorker) updateLastVisitDate(ctx context.Context, tx *sql.Tx, accountID, reportDate string) error {
	query := `
		UPDATE accounts
		SET last_visit_date = GREATEST(COALESCE(last_visit_date, '1970-01-01'::date), $1::date),
		    updated_at = NOW()
		WHERE id = $2
	`

	result, err := tx.ExecContext(ctx, query, reportDate, accountID)
	if err != nil {
		return fmt.Errorf("updateLastVisitDate: update failed: %w", err)
	}

	rowsAffected, _ := result.RowsAffected()
	w.logger.Info("last visit date updated",
		slog.String("accountId", accountID),
		slog.String("reportDate", reportDate),
		slog.Int64("rowsAffected", rowsAffected),
	)

	return nil
}

// createFollowUpTasks はカウンセリング記録からフォローアップタスクを作成する。
// Apex: SELECT CounselingRecord__c → insert Task に対応。
// 冪等性: counseling_record_id + daily_report_id の組み合わせで重複チェック。
func (w *DailyReportWorker) createFollowUpTasks(ctx context.Context, tx *sql.Tx, evt event.ReportSubmittedEvent) error {
	// 1. フォローアップが必要なカウンセリング記録を取得
	selectQuery := `
		SELECT cr.id, cr.contact_id, cr.category,
		       cr.follow_up_date, cr.follow_up_note,
		       c.last_name AS contact_last_name
		FROM counseling_records cr
		JOIN contacts c ON cr.contact_id = c.id
		WHERE cr.daily_report_id = $1
		  AND cr.follow_up_required = true
	`

	rows, err := tx.QueryContext(ctx, selectQuery, evt.ReportID)
	if err != nil {
		return fmt.Errorf("createFollowUpTasks: select failed: %w", err)
	}
	defer rows.Close()

	// 2. タスクを作成
	// follow_up_tasks テーブルに INSERT（冪等性のため ON CONFLICT DO NOTHING）
	insertQuery := `
		INSERT INTO follow_up_tasks (
			id, subject, description, owner_id, contact_id,
			daily_report_id, counseling_record_id,
			due_date, priority, status
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		ON CONFLICT (counseling_record_id, daily_report_id) DO NOTHING
	`

	taskCount := 0
	for rows.Next() {
		var (
			crID            string
			contactID       string
			category        string
			followUpDate    sql.NullString
			followUpNote    sql.NullString
			contactLastName string
		)

		if err := rows.Scan(&crID, &contactID, &category, &followUpDate, &followUpNote, &contactLastName); err != nil {
			return fmt.Errorf("createFollowUpTasks: scan failed: %w", err)
		}

		// Apex: t.Subject = 'フォローアップ: ' + cr.Category__c + ' - ' + cr.Contact__r.LastName
		subject := fmt.Sprintf("フォローアップ: %s - %s", category, contactLastName)

		// Apex: cr.FollowUpDate__c != null ? cr.FollowUpDate__c : Date.today().addDays(7)
		dueDate := time.Now().AddDate(0, 0, 7).Format("2006-01-02")
		if followUpDate.Valid && followUpDate.String != "" {
			dueDate = followUpDate.String
		}

		var description *string
		if followUpNote.Valid {
			description = &followUpNote.String
		}

		taskID := uuid.New().String()[:18]

		_, err := tx.ExecContext(ctx, insertQuery,
			taskID, subject, description, evt.SupervisorID, contactID,
			evt.ReportID, crID,
			dueDate, "High", "Not Started",
		)
		if err != nil {
			return fmt.Errorf("createFollowUpTasks: insert task failed: %w", err)
		}

		taskCount++
	}

	if err := rows.Err(); err != nil {
		return fmt.Errorf("createFollowUpTasks: rows iteration failed: %w", err)
	}

	w.logger.Info("follow-up tasks created",
		slog.String("reportId", evt.ReportID),
		slog.Int("taskCount", taskCount),
	)

	return nil
}
