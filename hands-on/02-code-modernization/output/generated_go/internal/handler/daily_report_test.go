// Package handler_test は handler 層のブラックボックステストを提供する。
// httptest.NewRecorder で HTTP ステータスコードとレスポンスボディを検証する。
package handler_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"daily-report-api/internal/handler"
	"daily-report-api/internal/model"
	"daily-report-api/internal/usecase"
)

// ============================================================
// Mock UseCase
// ============================================================

type mockUseCase struct {
	listResult   []model.DailyReport
	listErr      error
	createResult *model.DailyReport
	createErr    error
	updateResult *model.DailyReport
	updateErr    error
	deleteErr    error
}

func (m *mockUseCase) ListReports(_ context.Context, _ model.ListReportsFilter) ([]model.DailyReport, error) {
	return m.listResult, m.listErr
}

func (m *mockUseCase) CreateReport(_ context.Context, _ model.CreateReportRequest) (*model.DailyReport, error) {
	return m.createResult, m.createErr
}

func (m *mockUseCase) UpdateStatus(_ context.Context, _ string, _ model.UpdateStatusRequest) (*model.DailyReport, error) {
	return m.updateResult, m.updateErr
}

func (m *mockUseCase) DeleteReport(_ context.Context, _ string) error {
	return m.deleteErr
}

// ============================================================
// ヘルパー
// ============================================================

func newTestLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
}

func setupHandler(uc usecase.DailyReportUseCase) *http.ServeMux {
	h := handler.NewDailyReportHandler(uc, newTestLogger())
	mux := http.NewServeMux()
	h.RegisterRoutes(mux)
	return mux
}

func toJSON(t *testing.T, v interface{}) *bytes.Buffer {
	t.Helper()
	buf := new(bytes.Buffer)
	if err := json.NewEncoder(buf).Encode(v); err != nil {
		t.Fatalf("failed to encode JSON: %v", err)
	}
	return buf
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
// ListReports ハンドラーテスト
// ============================================================

func TestHandlerListReports_Success(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{
		listResult: []model.DailyReport{
			{ID: "r1", Name: "DR-0001"},
		},
	}
	mux := setupHandler(uc)

	req := httptest.NewRequest(http.MethodGet, "/api/daily-reports?status=下書き&region=関東", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}

	var reports []model.DailyReport
	if err := json.NewDecoder(rec.Body).Decode(&reports); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if len(reports) != 1 {
		t.Errorf("got %d reports, want 1", len(reports))
	}
}

func TestHandlerListReports_EmptyReturnsArray(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{listResult: nil}
	mux := setupHandler(uc)

	req := httptest.NewRequest(http.MethodGet, "/api/daily-reports", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}

	var reports []model.DailyReport
	if err := json.NewDecoder(rec.Body).Decode(&reports); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if len(reports) != 0 {
		t.Errorf("got %d reports, want 0", len(reports))
	}
}

func TestHandlerListReports_InternalError(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{listErr: errors.New("db error")}
	mux := setupHandler(uc)

	req := httptest.NewRequest(http.MethodGet, "/api/daily-reports", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}

	var errResp model.ErrorResponse
	if err := json.NewDecoder(rec.Body).Decode(&errResp); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if errResp.Code != "INTERNAL_ERROR" {
		t.Errorf("code = %q, want %q", errResp.Code, "INTERNAL_ERROR")
	}
}

// ============================================================
// CreateReport ハンドラーテスト
// ============================================================

func TestHandlerCreateReport_Success(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{
		createResult: &model.DailyReport{ID: "new-1", Status: "下書き"},
	}
	mux := setupHandler(uc)

	body := toJSON(t, validCreateRequest())
	req := httptest.NewRequest(http.MethodPost, "/api/daily-reports", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusCreated)
	}

	var report model.DailyReport
	if err := json.NewDecoder(rec.Body).Decode(&report); err != nil {
		t.Fatalf("failed to decode: %v", err)
	}
	if report.ID != "new-1" {
		t.Errorf("ID = %q, want %q", report.ID, "new-1")
	}
}

func TestHandlerCreateReport_InvalidJSON(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{}
	mux := setupHandler(uc)

	body := bytes.NewBufferString("{invalid json")
	req := httptest.NewRequest(http.MethodPost, "/api/daily-reports", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}

	var errResp model.ErrorResponse
	json.NewDecoder(rec.Body).Decode(&errResp)
	if errResp.Code != "INVALID_JSON" {
		t.Errorf("code = %q, want %q", errResp.Code, "INVALID_JSON")
	}
}

func TestHandlerCreateReport_ValidationError(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{
		createErr: usecase.ErrValidation,
	}
	mux := setupHandler(uc)

	body := toJSON(t, model.CreateReportRequest{})
	req := httptest.NewRequest(http.MethodPost, "/api/daily-reports", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}

	var errResp model.ErrorResponse
	json.NewDecoder(rec.Body).Decode(&errResp)
	if errResp.Code != "VALIDATION_ERROR" {
		t.Errorf("code = %q, want %q", errResp.Code, "VALIDATION_ERROR")
	}
}

func TestHandlerCreateReport_InternalError(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{
		createErr: errors.New("db write failed"),
	}
	mux := setupHandler(uc)

	body := toJSON(t, validCreateRequest())
	req := httptest.NewRequest(http.MethodPost, "/api/daily-reports", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

// ============================================================
// UpdateReportStatus ハンドラーテスト
// ============================================================

func TestHandlerUpdateStatus_Success(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{
		updateResult: &model.DailyReport{ID: "r1", Status: "提出済"},
	}
	mux := setupHandler(uc)

	body := toJSON(t, model.UpdateStatusRequest{Status: "提出済"})
	req := httptest.NewRequest(http.MethodPatch, "/api/daily-reports/r1", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusOK)
	}
}

func TestHandlerUpdateStatus_NotFound(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{updateErr: usecase.ErrNotFound}
	mux := setupHandler(uc)

	body := toJSON(t, model.UpdateStatusRequest{Status: "提出済"})
	req := httptest.NewRequest(http.MethodPatch, "/api/daily-reports/nonexistent", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}

func TestHandlerUpdateStatus_InvalidStatus(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{updateErr: usecase.ErrInvalidStatus}
	mux := setupHandler(uc)

	body := toJSON(t, model.UpdateStatusRequest{Status: "承認済"})
	req := httptest.NewRequest(http.MethodPatch, "/api/daily-reports/r1", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}

	var errResp model.ErrorResponse
	json.NewDecoder(rec.Body).Decode(&errResp)
	if errResp.Code != "INVALID_STATUS" {
		t.Errorf("code = %q, want %q", errResp.Code, "INVALID_STATUS")
	}
}

func TestHandlerUpdateStatus_ValidationError(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{updateErr: usecase.ErrValidation}
	mux := setupHandler(uc)

	body := toJSON(t, model.UpdateStatusRequest{Status: "完了"})
	req := httptest.NewRequest(http.MethodPatch, "/api/daily-reports/r1", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestHandlerUpdateStatus_InvalidJSON(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{}
	mux := setupHandler(uc)

	body := bytes.NewBufferString("not json")
	req := httptest.NewRequest(http.MethodPatch, "/api/daily-reports/r1", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestHandlerUpdateStatus_InternalError(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{updateErr: errors.New("db error")}
	mux := setupHandler(uc)

	body := toJSON(t, model.UpdateStatusRequest{Status: "提出済"})
	req := httptest.NewRequest(http.MethodPatch, "/api/daily-reports/r1", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

// ============================================================
// DeleteReport ハンドラーテスト
// ============================================================

func TestHandlerDeleteReport_Success(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{}
	mux := setupHandler(uc)

	req := httptest.NewRequest(http.MethodDelete, "/api/daily-reports/r1", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusNoContent)
	}
}

func TestHandlerDeleteReport_NotFound(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{deleteErr: usecase.ErrNotFound}
	mux := setupHandler(uc)

	req := httptest.NewRequest(http.MethodDelete, "/api/daily-reports/nonexistent", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}

func TestHandlerDeleteReport_NotAllowed(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{deleteErr: usecase.ErrDeleteNotAllowed}
	mux := setupHandler(uc)

	req := httptest.NewRequest(http.MethodDelete, "/api/daily-reports/r1", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}

	var errResp model.ErrorResponse
	json.NewDecoder(rec.Body).Decode(&errResp)
	if errResp.Code != "DELETE_NOT_ALLOWED" {
		t.Errorf("code = %q, want %q", errResp.Code, "DELETE_NOT_ALLOWED")
	}
}

func TestHandlerDeleteReport_InternalError(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{deleteErr: errors.New("db error")}
	mux := setupHandler(uc)

	req := httptest.NewRequest(http.MethodDelete, "/api/daily-reports/r1", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

// ============================================================
// Content-Type テスト
// ============================================================

func TestHandlerListReports_ContentType(t *testing.T) {
	t.Parallel()
	uc := &mockUseCase{listResult: []model.DailyReport{}}
	mux := setupHandler(uc)

	req := httptest.NewRequest(http.MethodGet, "/api/daily-reports", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	ct := rec.Header().Get("Content-Type")
	expected := "application/json; charset=utf-8"
	if ct != expected {
		t.Errorf("Content-Type = %q, want %q", ct, expected)
	}
}
