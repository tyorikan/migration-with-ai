// Package usecase_test は usecase 層のブラックボックステストを提供する。
// repository のインターフェースをモック化し、ビジネスロジックのみを検証する。
package usecase_test

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"strings"
	"testing"

	"daily-report-api/internal/model"
	"daily-report-api/internal/repository"
	"daily-report-api/internal/usecase"
)

// 未使用の import を防ぐ
var _ repository.DailyReportRepository = (*mockRepo)(nil)

// ============================================================
// Mock Repository
// ============================================================

type mockRepo struct {
	listReportsResult []model.DailyReport
	listReportsErr    error
	getReportResult   *model.DailyReport
	getReportErr      error
	createErr         error
	updateStatusErr   error
	deleteErr         error

	createCalled   bool
	updateCalled   bool
	deleteCalled   bool
	deleteCalledID string
}

func (m *mockRepo) ListReports(_ context.Context, _ model.ListReportsFilter) ([]model.DailyReport, error) {
	return m.listReportsResult, m.listReportsErr
}

func (m *mockRepo) GetReportByID(_ context.Context, _ string) (*model.DailyReport, error) {
	return m.getReportResult, m.getReportErr
}

func (m *mockRepo) CreateReportWithCounselings(_ context.Context, _ *model.DailyReport, _ []model.CounselingRecord) error {
	m.createCalled = true
	return m.createErr
}

func (m *mockRepo) UpdateReportStatus(_ context.Context, _ *model.DailyReport) error {
	m.updateCalled = true
	return m.updateStatusErr
}

func (m *mockRepo) DeleteReport(_ context.Context, id string) error {
	m.deleteCalled = true
	m.deleteCalledID = id
	return m.deleteErr
}

// ============================================================
// テストヘルパー
// ============================================================

func newTestLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
}

func validCreateRequest() model.CreateReportRequest {
	return model.CreateReportRequest{
		ReportDate:       "2025-01-15",
		SupervisorID:     "sup-001",
		AccountID:        "acc-001",
		VisitStartTime:   "2025-01-15T09:00:00Z",
		VisitEndTime:     "2025-01-15T10:00:00Z",
		VisitPurpose:     "定期巡回",
		OverallCondition: "A",
	}
}

// ============================================================
// ListReports テスト
// ============================================================

func TestListReports_Success(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{
		listReportsResult: []model.DailyReport{
			{ID: "r1", Name: "DR-0001", Status: "下書き"},
			{ID: "r2", Name: "DR-0002", Status: "提出済"},
		},
	}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	reports, err := uc.ListReports(context.Background(), model.ListReportsFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(reports) != 2 {
		t.Errorf("got %d reports, want 2", len(reports))
	}
}

func TestListReports_EmptyResult(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{listReportsResult: nil}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	reports, err := uc.ListReports(context.Background(), model.ListReportsFilter{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if reports != nil {
		t.Errorf("got %v, want nil", reports)
	}
}

func TestListReports_DBError(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{listReportsErr: errors.New("connection refused")}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	_, err := uc.ListReports(context.Background(), model.ListReportsFilter{})
	if err == nil {
		t.Fatal("expected error, got nil")
	}
}

func TestListReports_WithFilter(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{
		listReportsResult: []model.DailyReport{
			{ID: "r1", Status: "下書き"},
		},
	}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	filter := model.ListReportsFilter{
		Status:   "下書き",
		Region:   "関東",
		DateFrom: "2025-01-01",
		DateTo:   "2025-01-31",
	}
	reports, err := uc.ListReports(context.Background(), filter)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(reports) != 1 {
		t.Errorf("got %d reports, want 1", len(reports))
	}
}

// ============================================================
// CreateReport テスト
// ============================================================

func TestCreateReport_Success(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	report, err := uc.CreateReport(context.Background(), validCreateRequest())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if report == nil {
		t.Fatal("report should not be nil")
	}
	if report.Status != "下書き" {
		t.Errorf("Status = %q, want %q", report.Status, "下書き")
	}
	if !repo.createCalled {
		t.Error("repo.CreateReportWithCounselings was not called")
	}
}

func TestCreateReport_WithCounselingRecords(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	req := validCreateRequest()
	req.CounselingRecords = []model.CreateCounselingRequest{
		{ContactID: "c1", Category: "業務改善", Detail: "作業効率化", DurationMinutes: 30},
		{ContactID: "c2", Category: "人材育成", Detail: "OJT", DurationMinutes: 45},
	}

	report, err := uc.CreateReport(context.Background(), req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(report.CounselingRecords) != 2 {
		t.Errorf("got %d counseling records, want 2", len(report.CounselingRecords))
	}
}

func TestCreateReport_ValidationErrors(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		modify  func(*model.CreateReportRequest)
		wantErr string
	}{
		{
			name:    "ReportDate必須",
			modify:  func(r *model.CreateReportRequest) { r.ReportDate = "" },
			wantErr: "reportDate is required",
		},
		{
			name:    "SupervisorID必須",
			modify:  func(r *model.CreateReportRequest) { r.SupervisorID = "" },
			wantErr: "supervisorId is required",
		},
		{
			name:    "AccountID必須",
			modify:  func(r *model.CreateReportRequest) { r.AccountID = "" },
			wantErr: "accountId is required",
		},
		{
			name:    "VisitStartTime必須",
			modify:  func(r *model.CreateReportRequest) { r.VisitStartTime = "" },
			wantErr: "visitStartTime is required",
		},
		{
			name:    "VisitEndTime必須",
			modify:  func(r *model.CreateReportRequest) { r.VisitEndTime = "" },
			wantErr: "visitEndTime is required",
		},
		{
			name:    "不正なVisitPurpose",
			modify:  func(r *model.CreateReportRequest) { r.VisitPurpose = "お見舞い" },
			wantErr: "invalid visitPurpose",
		},
		{
			name:    "不正なOverallCondition",
			modify:  func(r *model.CreateReportRequest) { r.OverallCondition = "E" },
			wantErr: "invalid overallCondition",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			repo := &mockRepo{}
			uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

			req := validCreateRequest()
			tt.modify(&req)

			_, err := uc.CreateReport(context.Background(), req)
			if err == nil {
				t.Fatal("expected validation error")
			}
			if !errors.Is(err, usecase.ErrValidation) {
				t.Errorf("error should wrap ErrValidation, got: %v", err)
			}
			if !strings.Contains(err.Error(), tt.wantErr) {
				t.Errorf("error = %q, want containing %q", err.Error(), tt.wantErr)
			}
		})
	}
}

func TestCreateReport_CounselingValidation(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		cr      model.CreateCounselingRequest
		wantErr string
	}{
		{
			name:    "ContactID必須",
			cr:      model.CreateCounselingRequest{ContactID: "", Category: "業務改善", Detail: "test", DurationMinutes: 30},
			wantErr: "contactId is required",
		},
		{
			name:    "不正なCategory",
			cr:      model.CreateCounselingRequest{ContactID: "c1", Category: "不正", Detail: "test", DurationMinutes: 30},
			wantErr: "category is invalid",
		},
		{
			name:    "Detail必須",
			cr:      model.CreateCounselingRequest{ContactID: "c1", Category: "業務改善", Detail: "", DurationMinutes: 30},
			wantErr: "detail is required",
		},
		{
			name:    "DurationMinutesが0",
			cr:      model.CreateCounselingRequest{ContactID: "c1", Category: "業務改善", Detail: "test", DurationMinutes: 0},
			wantErr: "durationMinutes must be positive",
		},
		{
			name:    "DurationMinutesが負",
			cr:      model.CreateCounselingRequest{ContactID: "c1", Category: "業務改善", Detail: "test", DurationMinutes: -10},
			wantErr: "durationMinutes must be positive",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			repo := &mockRepo{}
			uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

			req := validCreateRequest()
			req.CounselingRecords = []model.CreateCounselingRequest{tt.cr}

			_, err := uc.CreateReport(context.Background(), req)
			if err == nil {
				t.Fatal("expected validation error")
			}
			if !errors.Is(err, usecase.ErrValidation) {
				t.Errorf("error should wrap ErrValidation, got: %v", err)
			}
			if !strings.Contains(err.Error(), tt.wantErr) {
				t.Errorf("error = %q, want containing %q", err.Error(), tt.wantErr)
			}
		})
	}
}

func TestCreateReport_DBError(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{createErr: errors.New("unique constraint violation")}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	_, err := uc.CreateReport(context.Background(), validCreateRequest())
	if err == nil {
		t.Fatal("expected error")
	}
}

// ============================================================
// UpdateStatus テスト
// ============================================================

func TestUpdateStatus_DraftToSubmitted(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{
		getReportResult: &model.DailyReport{ID: "r1", Status: "下書き"},
	}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	report, err := uc.UpdateStatus(context.Background(), "r1", model.UpdateStatusRequest{Status: "提出済"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if report.Status != "提出済" {
		t.Errorf("Status = %q, want %q", report.Status, "提出済")
	}
}

func TestUpdateStatus_SubmittedToApproved(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{
		getReportResult: &model.DailyReport{ID: "r1", Status: "提出済"},
	}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	report, err := uc.UpdateStatus(context.Background(), "r1", model.UpdateStatusRequest{
		Status:     "承認済",
		ApprovedBy: "mgr-001",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if report.Status != "承認済" {
		t.Errorf("Status = %q, want %q", report.Status, "承認済")
	}
	if report.ApprovedBy == nil || *report.ApprovedBy != "mgr-001" {
		t.Error("ApprovedBy should be set to mgr-001")
	}
	if report.ApprovedDate == nil {
		t.Error("ApprovedDate should be set")
	}
}

func TestUpdateStatus_SubmittedToRejected(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{
		getReportResult: &model.DailyReport{ID: "r1", Status: "提出済"},
	}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	report, err := uc.UpdateStatus(context.Background(), "r1", model.UpdateStatusRequest{Status: "差戻し"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if report.Status != "差戻し" {
		t.Errorf("Status = %q, want %q", report.Status, "差戻し")
	}
}

func TestUpdateStatus_RejectedToSubmitted(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{
		getReportResult: &model.DailyReport{ID: "r1", Status: "差戻し"},
	}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	report, err := uc.UpdateStatus(context.Background(), "r1", model.UpdateStatusRequest{Status: "提出済"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if report.Status != "提出済" {
		t.Errorf("Status = %q, want %q", report.Status, "提出済")
	}
}

func TestUpdateStatus_InvalidTransitions(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		current   string
		newStatus string
	}{
		{"下書き→承認済は不可", "下書き", "承認済"},
		{"下書き→差戻しは不可", "下書き", "差戻し"},
		{"提出済→下書きは不可", "提出済", "下書き"},
		{"承認済→任意は不可", "承認済", "提出済"},
		{"承認済→下書きは不可", "承認済", "下書き"},
		{"差戻し→承認済は不可", "差戻し", "承認済"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			repo := &mockRepo{
				getReportResult: &model.DailyReport{ID: "r1", Status: tt.current},
			}
			uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

			_, err := uc.UpdateStatus(context.Background(), "r1", model.UpdateStatusRequest{Status: tt.newStatus})
			if err == nil {
				t.Fatal("expected error for invalid transition")
			}
			if !errors.Is(err, usecase.ErrInvalidStatus) {
				t.Errorf("error should wrap ErrInvalidStatus, got: %v", err)
			}
		})
	}
}

func TestUpdateStatus_InvalidStatusValue(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	_, err := uc.UpdateStatus(context.Background(), "r1", model.UpdateStatusRequest{Status: "完了"})
	if err == nil {
		t.Fatal("expected validation error")
	}
	if !errors.Is(err, usecase.ErrValidation) {
		t.Errorf("error should wrap ErrValidation, got: %v", err)
	}
}

func TestUpdateStatus_NotFound(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{getReportResult: nil}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	_, err := uc.UpdateStatus(context.Background(), "nonexistent", model.UpdateStatusRequest{Status: "提出済"})
	if err == nil {
		t.Fatal("expected error")
	}
	if !errors.Is(err, usecase.ErrNotFound) {
		t.Errorf("error should be ErrNotFound, got: %v", err)
	}
}

func TestUpdateStatus_DBError_GetReport(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{getReportErr: errors.New("db connection lost")}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	_, err := uc.UpdateStatus(context.Background(), "r1", model.UpdateStatusRequest{Status: "提出済"})
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestUpdateStatus_DBError_Update(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{
		getReportResult: &model.DailyReport{ID: "r1", Status: "下書き"},
		updateStatusErr: errors.New("db write error"),
	}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	_, err := uc.UpdateStatus(context.Background(), "r1", model.UpdateStatusRequest{Status: "提出済"})
	if err == nil {
		t.Fatal("expected error")
	}
}

// ============================================================
// DeleteReport テスト
// ============================================================

func TestDeleteReport_Success(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{
		getReportResult: &model.DailyReport{ID: "r1", Status: "下書き"},
	}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	if err := uc.DeleteReport(context.Background(), "r1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !repo.deleteCalled {
		t.Error("repo.DeleteReport was not called")
	}
	if repo.deleteCalledID != "r1" {
		t.Errorf("deleteCalledID = %q, want %q", repo.deleteCalledID, "r1")
	}
}

func TestDeleteReport_NotDraft(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		status string
	}{
		{"提出済は削除不可", "提出済"},
		{"承認済は削除不可", "承認済"},
		{"差戻しは削除不可", "差戻し"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			repo := &mockRepo{
				getReportResult: &model.DailyReport{ID: "r1", Status: tt.status},
			}
			uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

			err := uc.DeleteReport(context.Background(), "r1")
			if err == nil {
				t.Fatal("expected error")
			}
			if !errors.Is(err, usecase.ErrDeleteNotAllowed) {
				t.Errorf("error should be ErrDeleteNotAllowed, got: %v", err)
			}
		})
	}
}

func TestDeleteReport_NotFound(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{getReportResult: nil}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	err := uc.DeleteReport(context.Background(), "nonexistent")
	if err == nil {
		t.Fatal("expected error")
	}
	if !errors.Is(err, usecase.ErrNotFound) {
		t.Errorf("error should be ErrNotFound, got: %v", err)
	}
}

func TestDeleteReport_DBError_GetReport(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{getReportErr: errors.New("db connection lost")}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	err := uc.DeleteReport(context.Background(), "r1")
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestDeleteReport_DBError_Delete(t *testing.T) {
	t.Parallel()
	repo := &mockRepo{
		getReportResult: &model.DailyReport{ID: "r1", Status: "下書き"},
		deleteErr:       errors.New("db constraint violation"),
	}
	uc := usecase.NewDailyReportUseCase(repo, newTestLogger())

	err := uc.DeleteReport(context.Background(), "r1")
	if err == nil {
		t.Fatal("expected error")
	}
}
