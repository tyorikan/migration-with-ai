// Package repository_test は go-sqlmock を使った repository 層のテストを提供する。
// 実 DB 接続なしで SQL 発行パターンとエラーハンドリングを検証する。
package repository_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"

	"daily-report-api/internal/model"
	"daily-report-api/internal/repository"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

// ============================================================
// ヘルパー
// ============================================================

func newMockDB(t *testing.T) (*sql.DB, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("failed to create sqlmock: %v", err)
	}
	t.Cleanup(func() { db.Close() })
	return db, mock
}

var listReportCols = []string{
	"id", "name", "report_date", "supervisor_id",
	"account_id", "visit_start_time", "visit_end_time",
	"visit_purpose", "overall_condition",
	"summary", "next_action", "status",
	"approved_by", "approved_date",
	"created_at", "updated_at",
	"account_name", "store_code", "region",
}

var getReportCols = []string{
	"id", "name", "report_date", "supervisor_id", "account_id",
	"visit_start_time", "visit_end_time", "visit_purpose",
	"overall_condition", "summary", "next_action", "status",
	"approved_by", "approved_date", "created_at", "updated_at",
}

// ============================================================
// ListReports テスト
// ============================================================

func TestListReports_Success(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	now := time.Now()
	vs1 := time.Date(2025, 1, 15, 9, 0, 0, 0, time.UTC)
	ve1 := time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC)
	vs2 := time.Date(2025, 1, 16, 14, 0, 0, 0, time.UTC)
	ve2 := time.Date(2025, 1, 16, 15, 0, 0, 0, time.UTC)
	rows := sqlmock.NewRows(listReportCols).
		AddRow("r1", "DR-0001", "2025-01-15", "sup-1",
			"acc-1", vs1, ve1,
			"定期巡回", "A",
			nil, nil, "下書き",
			nil, nil,
			now, now,
			"テスト店舗", "ST-001", "関東").
		AddRow("r2", "DR-0002", "2025-01-16", "sup-2",
			"acc-2", vs2, ve2,
			"クレーム対応", "C",
			nil, nil, "提出済",
			nil, nil,
			now, now,
			"サンプル店舗", "ST-002", "関西")

	mock.ExpectQuery("SELECT").WillReturnRows(rows)

	results, err := repo.ListReports(context.Background(), model.ListReportsFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(results) != 2 {
		t.Errorf("got %d reports, want 2", len(results))
	}
	if results[0].ID != "r1" {
		t.Errorf("first report ID = %q, want %q", results[0].ID, "r1")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

func TestListReports_WithFilter(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	rows := sqlmock.NewRows(listReportCols)
	mock.ExpectQuery("SELECT").
		WithArgs("下書き", "関東", "2025-01-01", "2025-01-31").
		WillReturnRows(rows)

	filter := model.ListReportsFilter{
		Status:   "下書き",
		Region:   "関東",
		DateFrom: "2025-01-01",
		DateTo:   "2025-01-31",
	}
	results, err := repo.ListReports(context.Background(), filter)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(results) != 0 {
		t.Errorf("got %d, want 0", len(results))
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

func TestListReports_QueryError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectQuery("SELECT").WillReturnError(errors.New("connection refused"))

	_, err := repo.ListReports(context.Background(), model.ListReportsFilter{})
	if err == nil {
		t.Fatal("expected error")
	}
}

// ============================================================
// GetReportByID テスト
// ============================================================

func TestGetReportByID_Found(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	now := time.Now()
	vs := time.Date(2025, 1, 15, 9, 0, 0, 0, time.UTC)
	ve := time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC)
	rows := sqlmock.NewRows(getReportCols).
		AddRow("r1", "DR-0001", "2025-01-15", "sup-1", "acc-1",
			vs, ve, "定期巡回",
			"A", nil, nil, "下書き",
			nil, nil, now, now)

	mock.ExpectQuery("SELECT").WithArgs("r1").WillReturnRows(rows)

	report, err := repo.GetReportByID(context.Background(), "r1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if report == nil {
		t.Fatal("report should not be nil")
	}
	if report.ID != "r1" {
		t.Errorf("ID = %q, want %q", report.ID, "r1")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

func TestGetReportByID_NotFound(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectQuery("SELECT").WithArgs("nonexistent").
		WillReturnError(sql.ErrNoRows)

	report, err := repo.GetReportByID(context.Background(), "nonexistent")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if report != nil {
		t.Errorf("report should be nil for not found")
	}
}

func TestGetReportByID_DBError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectQuery("SELECT").WithArgs("r1").
		WillReturnError(errors.New("connection lost"))

	_, err := repo.GetReportByID(context.Background(), "r1")
	if err == nil {
		t.Fatal("expected error")
	}
}

// ============================================================
// CreateReportWithCounselings テスト
// ============================================================

func TestCreateReport_Success_NoCounselings(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	now := time.Now()
	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO daily_reports").
		WillReturnRows(sqlmock.NewRows([]string{"created_at", "updated_at"}).AddRow(now, now))
	mock.ExpectCommit()

	vStart := time.Date(2025, 1, 15, 9, 0, 0, 0, time.UTC)
	vEnd := time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC)
	report := &model.DailyReport{
		ID: "r1", Name: "DR-0001", ReportDate: "2025-01-15",
		SupervisorID: "sup-1", AccountID: "acc-1",
		VisitStartTime: vStart, VisitEndTime: vEnd,
		VisitPurpose: "定期巡回", OverallCondition: "A", Status: "下書き",
	}

	err := repo.CreateReportWithCounselings(context.Background(), report, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if report.CreatedAt.IsZero() {
		t.Error("CreatedAt should be set")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

func TestCreateReport_Success_WithCounselings(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	now := time.Now()
	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO daily_reports").
		WillReturnRows(sqlmock.NewRows([]string{"created_at", "updated_at"}).AddRow(now, now))
	mock.ExpectPrepare("INSERT INTO counseling_records")
	mock.ExpectExec("INSERT INTO counseling_records").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	vStart := time.Date(2025, 1, 15, 9, 0, 0, 0, time.UTC)
	vEnd := time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC)
	report := &model.DailyReport{
		ID: "r1", Name: "DR-0001", ReportDate: "2025-01-15",
		SupervisorID: "sup-1", AccountID: "acc-1",
		VisitStartTime: vStart, VisitEndTime: vEnd,
		VisitPurpose: "定期巡回", OverallCondition: "A", Status: "下書き",
	}
	counselings := []model.CounselingRecord{
		{ID: "cr1", Name: "CR-0001", ContactID: "c1", Category: "業務改善",
			Detail: "test", DurationMinutes: 30},
	}

	err := repo.CreateReportWithCounselings(context.Background(), report, counselings)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

func TestCreateReport_BeginTxError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectBegin().WillReturnError(errors.New("tx start failed"))

	report := &model.DailyReport{ID: "r1"}
	err := repo.CreateReportWithCounselings(context.Background(), report, nil)
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestCreateReport_InsertReportError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO daily_reports").
		WillReturnError(errors.New("unique constraint"))
	mock.ExpectRollback()

	report := &model.DailyReport{ID: "r1"}
	err := repo.CreateReportWithCounselings(context.Background(), report, nil)
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestCreateReport_PrepareCounselingError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	now := time.Now()
	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO daily_reports").
		WillReturnRows(sqlmock.NewRows([]string{"created_at", "updated_at"}).AddRow(now, now))
	mock.ExpectPrepare("INSERT INTO counseling_records").
		WillReturnError(errors.New("prepare failed"))
	mock.ExpectRollback()

	report := &model.DailyReport{ID: "r1"}
	counselings := []model.CounselingRecord{{ID: "cr1"}}

	err := repo.CreateReportWithCounselings(context.Background(), report, counselings)
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestCreateReport_InsertCounselingError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	now := time.Now()
	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO daily_reports").
		WillReturnRows(sqlmock.NewRows([]string{"created_at", "updated_at"}).AddRow(now, now))
	mock.ExpectPrepare("INSERT INTO counseling_records")
	mock.ExpectExec("INSERT INTO counseling_records").
		WillReturnError(errors.New("fk violation"))
	mock.ExpectRollback()

	report := &model.DailyReport{ID: "r1"}
	counselings := []model.CounselingRecord{{ID: "cr1"}}

	err := repo.CreateReportWithCounselings(context.Background(), report, counselings)
	if err == nil {
		t.Fatal("expected error")
	}
}

// ============================================================
// UpdateReportStatus テスト
// ============================================================

func TestUpdateReportStatus_Success(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectExec("UPDATE daily_reports").
		WillReturnResult(sqlmock.NewResult(0, 1))

	approvedBy := "mgr-001"
	approvedDate := time.Now()
	report := &model.DailyReport{
		ID:           "r1",
		Status:       "承認済",
		ApprovedBy:   &approvedBy,
		ApprovedDate: &approvedDate,
	}

	err := repo.UpdateReportStatus(context.Background(), report)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if report.UpdatedAt.IsZero() {
		t.Error("UpdatedAt should be set")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

func TestUpdateReportStatus_DBError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectExec("UPDATE daily_reports").
		WillReturnError(errors.New("deadlock"))

	report := &model.DailyReport{ID: "r1", Status: "提出済"}
	err := repo.UpdateReportStatus(context.Background(), report)
	if err == nil {
		t.Fatal("expected error")
	}
}

// ============================================================
// DeleteReport テスト
// ============================================================

func TestDeleteReport_Success(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectExec("DELETE FROM daily_reports").
		WithArgs("r1").
		WillReturnResult(sqlmock.NewResult(0, 1))

	err := repo.DeleteReport(context.Background(), "r1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

func TestDeleteReport_NotFound(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectExec("DELETE FROM daily_reports").
		WithArgs("nonexistent").
		WillReturnResult(sqlmock.NewResult(0, 0))

	err := repo.DeleteReport(context.Background(), "nonexistent")
	if err == nil {
		t.Fatal("expected error for not found")
	}
}

func TestDeleteReport_DBError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	repo := repository.NewDailyReportRepository(db)

	mock.ExpectExec("DELETE FROM daily_reports").
		WithArgs("r1").
		WillReturnError(errors.New("fk violation"))

	err := repo.DeleteReport(context.Background(), "r1")
	if err == nil {
		t.Fatal("expected error")
	}
}
