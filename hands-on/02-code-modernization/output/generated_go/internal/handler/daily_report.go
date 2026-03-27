// Package handler は HTTP リクエスト/レスポンスの処理を担当する。
// net/http の標準ライブラリのみを使用し、usecase 層のインターフェースに依存する。
package handler

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"daily-report-api/internal/model"
	"daily-report-api/internal/usecase"
)

// DailyReportHandler は日報の HTTP ハンドラー。
type DailyReportHandler struct {
	uc     usecase.DailyReportUseCase
	logger *slog.Logger
}

// NewDailyReportHandler は DailyReportHandler の新しいインスタンスを生成する。
func NewDailyReportHandler(uc usecase.DailyReportUseCase, logger *slog.Logger) *DailyReportHandler {
	return &DailyReportHandler{uc: uc, logger: logger}
}

// RegisterRoutes はルーティングを登録する。
// Apex の @RestResource(urlMapping='/api/daily-reports/*') に対応。
func (h *DailyReportHandler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/daily-reports", h.ListReports)
	mux.HandleFunc("POST /api/daily-reports", h.CreateReport)
	mux.HandleFunc("PATCH /api/daily-reports/{id}", h.UpdateReportStatus)
	mux.HandleFunc("DELETE /api/daily-reports/{id}", h.DeleteReport)
}

// ListReports は日報一覧を取得する。
// Apex: @HttpGet → getReports()
func (h *DailyReportHandler) ListReports(w http.ResponseWriter, r *http.Request) {
	filter := model.ListReportsFilter{
		Status:   r.URL.Query().Get("status"),
		Region:   r.URL.Query().Get("region"),
		DateFrom: r.URL.Query().Get("dateFrom"),
		DateTo:   r.URL.Query().Get("dateTo"),
	}

	reports, err := h.uc.ListReports(r.Context(), filter)
	if err != nil {
		h.respondError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "日報一覧の取得に失敗しました")
		return
	}

	// nil を空配列として返す
	if reports == nil {
		reports = []model.DailyReport{}
	}

	h.respondJSON(w, http.StatusOK, reports)
}

// CreateReport は日報を作成する。
// Apex: @HttpPost → createReport()
func (h *DailyReportHandler) CreateReport(w http.ResponseWriter, r *http.Request) {
	var req model.CreateReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "INVALID_JSON", "リクエストボディの JSON が不正です")
		return
	}

	report, err := h.uc.CreateReport(r.Context(), req)
	if err != nil {
		if errors.Is(err, usecase.ErrValidation) {
			h.respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
			return
		}
		h.respondError(w, http.StatusInternalServerError, "CREATE_FAILED", "日報の作成に失敗しました")
		return
	}

	h.respondJSON(w, http.StatusCreated, report)
}

// UpdateReportStatus はステータスを更新する。
// Apex: @HttpPatch → updateReportStatus()
func (h *DailyReportHandler) UpdateReportStatus(w http.ResponseWriter, r *http.Request) {
	reportID := extractPathParam(r, "id")
	if reportID == "" {
		h.respondError(w, http.StatusBadRequest, "MISSING_ID", "日報IDが指定されていません")
		return
	}

	var req model.UpdateStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.respondError(w, http.StatusBadRequest, "INVALID_JSON", "リクエストボディの JSON が不正です")
		return
	}

	report, err := h.uc.UpdateStatus(r.Context(), reportID, req)
	if err != nil {
		switch {
		case errors.Is(err, usecase.ErrNotFound):
			h.respondError(w, http.StatusNotFound, "NOT_FOUND", "指定された日報が見つかりません")
		case errors.Is(err, usecase.ErrInvalidStatus):
			h.respondError(w, http.StatusBadRequest, "INVALID_STATUS", err.Error())
		case errors.Is(err, usecase.ErrValidation):
			h.respondError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		default:
			h.respondError(w, http.StatusInternalServerError, "UPDATE_FAILED", "ステータス更新に失敗しました")
		}
		return
	}

	h.respondJSON(w, http.StatusOK, report)
}

// DeleteReport は日報を削除する。
// Apex: @HttpDelete → deleteReport()
func (h *DailyReportHandler) DeleteReport(w http.ResponseWriter, r *http.Request) {
	reportID := extractPathParam(r, "id")
	if reportID == "" {
		h.respondError(w, http.StatusBadRequest, "MISSING_ID", "日報IDが指定されていません")
		return
	}

	err := h.uc.DeleteReport(r.Context(), reportID)
	if err != nil {
		switch {
		case errors.Is(err, usecase.ErrNotFound):
			h.respondError(w, http.StatusNotFound, "NOT_FOUND", "指定された日報が見つかりません")
		case errors.Is(err, usecase.ErrDeleteNotAllowed):
			h.respondError(w, http.StatusBadRequest, "DELETE_NOT_ALLOWED", "下書きステータスの日報のみ削除できます")
		default:
			h.respondError(w, http.StatusInternalServerError, "DELETE_FAILED", "日報の削除に失敗しました")
		}
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ============================================================
// ヘルパーメソッド
// ============================================================

// respondJSON は JSON レスポンスを返す。
func (h *DailyReportHandler) respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(data); err != nil {
		h.logger.Error("failed to encode response", slog.String("error", err.Error()))
	}
}

// respondError は構造化エラーレスポンスを返す。
// フォーマット: {"error": "message", "code": "ERROR_CODE"}
func (h *DailyReportHandler) respondError(w http.ResponseWriter, status int, code, message string) {
	h.logger.Warn("error response",
		slog.Int("status", status),
		slog.String("code", code),
		slog.String("message", message),
	)
	h.respondJSON(w, status, model.ErrorResponse{
		Error: message,
		Code:  code,
	})
}

// extractPathParam はパスパラメータを取得する。
// Go 1.22+ の http.Request.PathValue を使用。
// フォールバックとして URL からの手動抽出も行う。
func extractPathParam(r *http.Request, name string) string {
	// Go 1.22+ のパスパラメータ
	if val := r.PathValue(name); val != "" {
		return val
	}
	// フォールバック: URL から手動抽出
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) > 0 {
		return parts[len(parts)-1]
	}
	return ""
}
