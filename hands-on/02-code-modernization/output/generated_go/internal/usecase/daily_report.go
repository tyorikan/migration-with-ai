// Package usecase はビジネスロジック層を提供する。
// 純粋な Go コードで構成され、外部パッケージ（DB、HTTP）に直接依存しない。
// repository のインターフェースに依存し、DI で具象実装を注入する。
package usecase

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"daily-report-api/internal/model"
	"daily-report-api/internal/repository"

	"github.com/google/uuid"
)

// DailyReportUseCase はビジネスロジック層のインターフェース。
// handler 層から参照される。
type DailyReportUseCase interface {
	ListReports(ctx context.Context, filter model.ListReportsFilter) ([]model.DailyReport, error)
	CreateReport(ctx context.Context, req model.CreateReportRequest) (*model.DailyReport, error)
	UpdateStatus(ctx context.Context, reportID string, req model.UpdateStatusRequest) (*model.DailyReport, error)
	DeleteReport(ctx context.Context, reportID string) error
}

// dailyReportUC は DailyReportUseCase の実装。
type dailyReportUC struct {
	repo   repository.DailyReportRepository
	logger *slog.Logger
}

// NewDailyReportUseCase は DailyReportUseCase の新しいインスタンスを生成する。
func NewDailyReportUseCase(repo repository.DailyReportRepository, logger *slog.Logger) DailyReportUseCase {
	return &dailyReportUC{repo: repo, logger: logger}
}

// ErrNotFound は日報が見つからない場合のエラー。
var ErrNotFound = fmt.Errorf("report not found")

// ErrInvalidStatus はステータス遷移が不正な場合のエラー。
var ErrInvalidStatus = fmt.Errorf("invalid status transition")

// ErrDeleteNotAllowed は削除が許可されていない場合のエラー。
var ErrDeleteNotAllowed = fmt.Errorf("only draft reports can be deleted")

// ErrValidation は入力バリデーションエラー。
var ErrValidation = fmt.Errorf("validation error")

// ListReports は日報一覧を取得する。
func (uc *dailyReportUC) ListReports(ctx context.Context, filter model.ListReportsFilter) ([]model.DailyReport, error) {
	uc.logger.Info("listing reports",
		slog.String("status", filter.Status),
		slog.String("region", filter.Region),
	)

	reports, err := uc.repo.ListReports(ctx, filter)
	if err != nil {
		uc.logger.Error("failed to list reports", slog.String("error", err.Error()))
		return nil, err
	}

	return reports, nil
}

// CreateReport は日報を作成する。
// Apex の createReport メソッドに対応。バリデーション → 日報作成 → カウンセリング記録作成。
func (uc *dailyReportUC) CreateReport(ctx context.Context, req model.CreateReportRequest) (*model.DailyReport, error) {
	// 入力バリデーション
	if err := uc.validateCreateRequest(req); err != nil {
		return nil, err
	}

	// 日報の組み立て
	reportID := uuid.New().String()[:18] // SFDC 互換の 18 文字
	visitStart, _ := time.Parse(time.RFC3339, req.VisitStartTime)
	visitEnd, _ := time.Parse(time.RFC3339, req.VisitEndTime)

	report := &model.DailyReport{
		ID:               reportID,
		Name:             fmt.Sprintf("DR-%04d", time.Now().UnixMilli()%10000),
		ReportDate:       req.ReportDate,
		SupervisorID:     req.SupervisorID,
		AccountID:        req.AccountID,
		VisitStartTime:   visitStart,
		VisitEndTime:     visitEnd,
		VisitPurpose:     req.VisitPurpose,
		OverallCondition: req.OverallCondition,
		Summary:          req.Summary,
		NextAction:       req.NextAction,
		Status:           "下書き", // Apex と同じ初期ステータス
	}

	// カウンセリング記録の組み立て
	var counselings []model.CounselingRecord
	for i, cr := range req.CounselingRecords {
		counselingID := uuid.New().String()[:18]
		counselings = append(counselings, model.CounselingRecord{
			ID:               counselingID,
			Name:             fmt.Sprintf("CR-%04d", i+1),
			ContactID:        cr.ContactID,
			Category:         cr.Category,
			Detail:           cr.Detail,
			DurationMinutes:  cr.DurationMinutes,
			FollowUpRequired: cr.FollowUpRequired,
			FollowUpDate:     cr.FollowUpDate,
			FollowUpNote:     cr.FollowUpNote,
		})
	}

	// トランザクション内で一括作成（repository 層に委譲）
	if err := uc.repo.CreateReportWithCounselings(ctx, report, counselings); err != nil {
		uc.logger.Error("failed to create report", slog.String("error", err.Error()))
		return nil, err
	}

	report.CounselingRecords = counselings

	uc.logger.Info("report created",
		slog.String("id", report.ID),
		slog.String("accountId", report.AccountID),
		slog.Int("counselingCount", len(counselings)),
	)

	return report, nil
}

// UpdateStatus はステータスを更新する。
// Apex の updateReportStatus メソッドに対応。ステータス遷移ルールを検証する。
func (uc *dailyReportUC) UpdateStatus(ctx context.Context, reportID string, req model.UpdateStatusRequest) (*model.DailyReport, error) {
	// バリデーション: ステータス値の妥当性
	if !model.Contains(model.ValidStatuses, req.Status) {
		return nil, fmt.Errorf("%w: invalid status: %s", ErrValidation, req.Status)
	}

	// 既存レコードの取得
	report, err := uc.repo.GetReportByID(ctx, reportID)
	if err != nil {
		uc.logger.Error("failed to get report", slog.String("error", err.Error()))
		return nil, err
	}
	if report == nil {
		return nil, ErrNotFound
	}

	// ステータス遷移のバリデーション（Apex のビジネスルールを移植）
	if err := uc.validateStatusTransition(report.Status, req.Status); err != nil {
		return nil, err
	}

	// 承認時は承認者情報を設定
	if req.Status == "承認済" {
		now := time.Now()
		report.ApprovedBy = &req.ApprovedBy
		report.ApprovedDate = &now
	}

	report.Status = req.Status

	if err := uc.repo.UpdateReportStatus(ctx, report); err != nil {
		uc.logger.Error("failed to update status", slog.String("error", err.Error()))
		return nil, err
	}

	uc.logger.Info("status updated",
		slog.String("id", reportID),
		slog.String("newStatus", req.Status),
	)

	return report, nil
}

// DeleteReport は日報を削除する。
// Apex の deleteReport メソッドに対応。下書きのみ削除可能。
func (uc *dailyReportUC) DeleteReport(ctx context.Context, reportID string) error {
	report, err := uc.repo.GetReportByID(ctx, reportID)
	if err != nil {
		uc.logger.Error("failed to get report for deletion", slog.String("error", err.Error()))
		return err
	}
	if report == nil {
		return ErrNotFound
	}

	// Apex と同じルール: 下書きのみ削除可能
	if report.Status != "下書き" {
		return ErrDeleteNotAllowed
	}

	if err := uc.repo.DeleteReport(ctx, reportID); err != nil {
		uc.logger.Error("failed to delete report", slog.String("error", err.Error()))
		return err
	}

	uc.logger.Info("report deleted", slog.String("id", reportID))

	return nil
}

// ============================================================
// プライベートメソッド
// ============================================================

// validateCreateRequest は作成リクエストのバリデーションを行う。
func (uc *dailyReportUC) validateCreateRequest(req model.CreateReportRequest) error {
	if req.ReportDate == "" {
		return fmt.Errorf("%w: reportDate is required", ErrValidation)
	}
	if req.SupervisorID == "" {
		return fmt.Errorf("%w: supervisorId is required", ErrValidation)
	}
	if req.AccountID == "" {
		return fmt.Errorf("%w: accountId is required", ErrValidation)
	}
	if req.VisitStartTime == "" {
		return fmt.Errorf("%w: visitStartTime is required", ErrValidation)
	}
	if req.VisitEndTime == "" {
		return fmt.Errorf("%w: visitEndTime is required", ErrValidation)
	}
	if !model.Contains(model.ValidVisitPurposes, req.VisitPurpose) {
		return fmt.Errorf("%w: invalid visitPurpose: %s", ErrValidation, req.VisitPurpose)
	}
	if !model.Contains(model.ValidConditions, req.OverallCondition) {
		return fmt.Errorf("%w: invalid overallCondition: %s", ErrValidation, req.OverallCondition)
	}

	// カウンセリング記録のバリデーション
	for i, cr := range req.CounselingRecords {
		if cr.ContactID == "" {
			return fmt.Errorf("%w: counselingRecords[%d].contactId is required", ErrValidation, i)
		}
		if !model.Contains(model.ValidCategories, cr.Category) {
			return fmt.Errorf("%w: counselingRecords[%d].category is invalid: %s", ErrValidation, i, cr.Category)
		}
		if cr.Detail == "" {
			return fmt.Errorf("%w: counselingRecords[%d].detail is required", ErrValidation, i)
		}
		if cr.DurationMinutes <= 0 {
			return fmt.Errorf("%w: counselingRecords[%d].durationMinutes must be positive", ErrValidation, i)
		}
	}

	return nil
}

// validateStatusTransition はステータス遷移の妥当性を検証する。
// Apex の if/else チェーンを Go のマップベースで明確に定義。
func (uc *dailyReportUC) validateStatusTransition(currentStatus, newStatus string) error {
	// 許可されるステータス遷移マップ
	allowedTransitions := map[string][]string{
		"下書き": {"提出済"},
		"提出済": {"承認済", "差戻し"},
		"差戻し": {"提出済"},
		"承認済": {}, // 承認済からの遷移は不可
	}

	allowed, exists := allowedTransitions[currentStatus]
	if !exists {
		return fmt.Errorf("%w: unknown current status: %s", ErrInvalidStatus, currentStatus)
	}

	if !model.Contains(allowed, newStatus) {
		return fmt.Errorf("%w: cannot transition from '%s' to '%s'", ErrInvalidStatus, currentStatus, newStatus)
	}

	return nil
}
