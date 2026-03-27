// Package repository はデータアクセス層を提供する。
// database/sql + lib/pq を使用して PostgreSQL に接続し、
// usecase 層が定義するインターフェースを実装する。
package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"daily-report-api/internal/model"
)

// DailyReportRepository はデータアクセス層のインターフェース。
// usecase 層から参照され、依存性を逆転させる（クリーンアーキテクチャの依存性ルール）。
type DailyReportRepository interface {
	ListReports(ctx context.Context, filter model.ListReportsFilter) ([]model.DailyReport, error)
	GetReportByID(ctx context.Context, id string) (*model.DailyReport, error)
	CreateReportWithCounselings(ctx context.Context, report *model.DailyReport, counselings []model.CounselingRecord) error
	UpdateReportStatus(ctx context.Context, report *model.DailyReport) error
	DeleteReport(ctx context.Context, id string) error
}

// dailyReportRepo は DailyReportRepository の PostgreSQL 実装。
type dailyReportRepo struct {
	db *sql.DB
}

// NewDailyReportRepository は DailyReportRepository の新しいインスタンスを生成する。
func NewDailyReportRepository(db *sql.DB) DailyReportRepository {
	return &dailyReportRepo{db: db}
}

// ListReports は検索条件に基づいて日報一覧を取得する。
// SOQL の動的クエリ構築を、Go のパラメータ化クエリで安全に再実装。
func (r *dailyReportRepo) ListReports(ctx context.Context, filter model.ListReportsFilter) ([]model.DailyReport, error) {
	query := `
		SELECT
			dr.id, dr.name, dr.report_date, dr.supervisor_id,
			dr.account_id, dr.visit_start_time, dr.visit_end_time,
			dr.visit_purpose, dr.overall_condition,
			dr.summary, dr.next_action, dr.status,
			dr.approved_by, dr.approved_date,
			dr.created_at, dr.updated_at,
			a.name, a.store_code, a.region
		FROM daily_reports dr
		JOIN accounts a ON dr.account_id = a.id
	`

	var conditions []string
	var args []interface{}
	argIdx := 1

	if filter.Status != "" {
		conditions = append(conditions, fmt.Sprintf("dr.status = $%d", argIdx))
		args = append(args, filter.Status)
		argIdx++
	}
	if filter.Region != "" {
		conditions = append(conditions, fmt.Sprintf("a.region = $%d", argIdx))
		args = append(args, filter.Region)
		argIdx++
	}
	if filter.DateFrom != "" {
		conditions = append(conditions, fmt.Sprintf("dr.report_date >= $%d", argIdx))
		args = append(args, filter.DateFrom)
		argIdx++
	}
	if filter.DateTo != "" {
		conditions = append(conditions, fmt.Sprintf("dr.report_date <= $%d", argIdx))
		args = append(args, filter.DateTo)
		argIdx++
	}

	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}
	query += " ORDER BY dr.report_date DESC LIMIT 200"

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("ListReports: query failed: %w", err)
	}
	defer rows.Close()

	var reports []model.DailyReport
	for rows.Next() {
		var dr model.DailyReport
		err := rows.Scan(
			&dr.ID, &dr.Name, &dr.ReportDate, &dr.SupervisorID,
			&dr.AccountID, &dr.VisitStartTime, &dr.VisitEndTime,
			&dr.VisitPurpose, &dr.OverallCondition,
			&dr.Summary, &dr.NextAction, &dr.Status,
			&dr.ApprovedBy, &dr.ApprovedDate,
			&dr.CreatedAt, &dr.UpdatedAt,
			&dr.AccountName, &dr.AccountStoreCode, &dr.AccountRegion,
		)
		if err != nil {
			return nil, fmt.Errorf("ListReports: scan failed: %w", err)
		}
		reports = append(reports, dr)
	}

	return reports, rows.Err()
}

// GetReportByID は指定 ID の日報を 1 件取得する。
func (r *dailyReportRepo) GetReportByID(ctx context.Context, id string) (*model.DailyReport, error) {
	query := `
		SELECT id, name, report_date, supervisor_id, account_id,
		       visit_start_time, visit_end_time, visit_purpose,
		       overall_condition, summary, next_action, status,
		       approved_by, approved_date, created_at, updated_at
		FROM daily_reports
		WHERE id = $1
	`

	var dr model.DailyReport
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&dr.ID, &dr.Name, &dr.ReportDate, &dr.SupervisorID, &dr.AccountID,
		&dr.VisitStartTime, &dr.VisitEndTime, &dr.VisitPurpose,
		&dr.OverallCondition, &dr.Summary, &dr.NextAction, &dr.Status,
		&dr.ApprovedBy, &dr.ApprovedDate, &dr.CreatedAt, &dr.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return nil, nil // 見つからない場合は nil を返す
	}
	if err != nil {
		return nil, fmt.Errorf("GetReportByID: query failed: %w", err)
	}

	return &dr, nil
}

// CreateReportWithCounselings は日報とカウンセリング記録をトランザクション内でアトミックに作成する。
// Apex の insert report → insert records をトランザクションで保証する。
func (r *dailyReportRepo) CreateReportWithCounselings(ctx context.Context, report *model.DailyReport, counselings []model.CounselingRecord) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("CreateReportWithCounselings: begin tx failed: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck // commit 成功時は no-op

	// 1. 日報の INSERT
	reportQuery := `
		INSERT INTO daily_reports (
			id, name, report_date, supervisor_id, account_id,
			visit_start_time, visit_end_time, visit_purpose,
			overall_condition, summary, next_action, status
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		RETURNING created_at, updated_at
	`
	err = tx.QueryRowContext(ctx, reportQuery,
		report.ID, report.Name, report.ReportDate, report.SupervisorID, report.AccountID,
		report.VisitStartTime, report.VisitEndTime, report.VisitPurpose,
		report.OverallCondition, report.Summary, report.NextAction, report.Status,
	).Scan(&report.CreatedAt, &report.UpdatedAt)
	if err != nil {
		return fmt.Errorf("CreateReportWithCounselings: insert report failed: %w", err)
	}

	// 2. カウンセリング記録の一括 INSERT
	if len(counselings) > 0 {
		counselingQuery := `
			INSERT INTO counseling_records (
				id, name, daily_report_id, contact_id, category,
				detail, duration_minutes, follow_up_required,
				follow_up_date, follow_up_note
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		`
		stmt, err := tx.PrepareContext(ctx, counselingQuery)
		if err != nil {
			return fmt.Errorf("CreateReportWithCounselings: prepare counseling failed: %w", err)
		}
		defer stmt.Close()

		for i := range counselings {
			counselings[i].DailyReportID = report.ID
			_, err = stmt.ExecContext(ctx,
				counselings[i].ID, counselings[i].Name,
				counselings[i].DailyReportID, counselings[i].ContactID,
				counselings[i].Category, counselings[i].Detail,
				counselings[i].DurationMinutes, counselings[i].FollowUpRequired,
				counselings[i].FollowUpDate, counselings[i].FollowUpNote,
			)
			if err != nil {
				return fmt.Errorf("CreateReportWithCounselings: insert counseling[%d] failed: %w", i, err)
			}
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("CreateReportWithCounselings: commit failed: %w", err)
	}

	return nil
}

// UpdateReportStatus は日報のステータスを更新する。
func (r *dailyReportRepo) UpdateReportStatus(ctx context.Context, report *model.DailyReport) error {
	query := `
		UPDATE daily_reports
		SET status = $1, approved_by = $2, approved_date = $3, updated_at = $4
		WHERE id = $5
	`
	now := time.Now()
	report.UpdatedAt = now

	_, err := r.db.ExecContext(ctx, query,
		report.Status, report.ApprovedBy, report.ApprovedDate, report.UpdatedAt, report.ID,
	)
	if err != nil {
		return fmt.Errorf("UpdateReportStatus: update failed: %w", err)
	}

	return nil
}

// DeleteReport は日報を削除する。
// カウンセリング記録は ON DELETE CASCADE で自動削除される。
func (r *dailyReportRepo) DeleteReport(ctx context.Context, id string) error {
	query := `DELETE FROM daily_reports WHERE id = $1`
	result, err := r.db.ExecContext(ctx, query, id)
	if err != nil {
		return fmt.Errorf("DeleteReport: delete failed: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("DeleteReport: rows affected failed: %w", err)
	}
	if rowsAffected == 0 {
		return fmt.Errorf("DeleteReport: report not found: %s", id)
	}

	return nil
}
