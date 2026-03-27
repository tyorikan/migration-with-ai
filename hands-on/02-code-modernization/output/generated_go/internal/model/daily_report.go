// Package model は業務日報システムのドメインモデル（構造体）を定義する。
// DDL のテーブル定義に対応した Go 構造体と、
// リクエスト/レスポンス用の DTO を分離して管理する。
package model

import (
	"time"
)

// ============================================================
// ドメインモデル（DB テーブル対応）
// ============================================================

// DailyReport は業務日報（daily_reports テーブル）に対応する構造体。
type DailyReport struct {
	ID               string     `json:"id"`
	Name             string     `json:"name"`
	ReportDate       string     `json:"reportDate"`       // YYYY-MM-DD
	SupervisorID     string     `json:"supervisorId"`
	AccountID        string     `json:"accountId"`
	VisitStartTime   time.Time  `json:"visitStartTime"`
	VisitEndTime     time.Time  `json:"visitEndTime"`
	VisitPurpose     string     `json:"visitPurpose"`
	OverallCondition string     `json:"overallCondition"`
	Summary          *string    `json:"summary,omitempty"`
	NextAction       *string    `json:"nextAction,omitempty"`
	Status           string     `json:"status"`
	ApprovedBy       *string    `json:"approvedBy,omitempty"`
	ApprovedDate     *time.Time `json:"approvedDate,omitempty"`
	CreatedAt        time.Time  `json:"createdAt"`
	UpdatedAt        time.Time  `json:"updatedAt"`

	// リレーション（JOIN 結果を格納）
	AccountName      string `json:"accountName,omitempty"`
	AccountStoreCode string `json:"accountStoreCode,omitempty"`
	AccountRegion    string `json:"accountRegion,omitempty"`

	// 子レコード
	CounselingRecords []CounselingRecord `json:"counselingRecords,omitempty"`
}

// CounselingRecord はカウンセリング記録（counseling_records テーブル）に対応する構造体。
type CounselingRecord struct {
	ID              string     `json:"id"`
	Name            string     `json:"name"`
	DailyReportID   string     `json:"dailyReportId"`
	ContactID       string     `json:"contactId"`
	Category        string     `json:"category"`
	Detail          string     `json:"detail"`
	DurationMinutes int        `json:"durationMinutes"`
	FollowUpRequired bool      `json:"followUpRequired"`
	FollowUpDate    *string    `json:"followUpDate,omitempty"` // YYYY-MM-DD
	FollowUpNote    *string    `json:"followUpNote,omitempty"`
	CreatedAt       time.Time  `json:"createdAt"`
	UpdatedAt       time.Time  `json:"updatedAt"`

	// リレーション
	ContactLastName string `json:"contactLastName,omitempty"`
}

// ============================================================
// リクエスト DTO
// ============================================================

// CreateReportRequest は日報作成リクエストの構造体。
type CreateReportRequest struct {
	ReportDate       string                     `json:"reportDate"`
	SupervisorID     string                     `json:"supervisorId"`
	AccountID        string                     `json:"accountId"`
	VisitStartTime   string                     `json:"visitStartTime"`
	VisitEndTime     string                     `json:"visitEndTime"`
	VisitPurpose     string                     `json:"visitPurpose"`
	OverallCondition string                     `json:"overallCondition"`
	Summary          *string                    `json:"summary,omitempty"`
	NextAction       *string                    `json:"nextAction,omitempty"`
	CounselingRecords []CreateCounselingRequest  `json:"counselingRecords,omitempty"`
}

// CreateCounselingRequest はカウンセリング記録作成リクエストの構造体。
type CreateCounselingRequest struct {
	ContactID        string  `json:"contactId"`
	Category         string  `json:"category"`
	Detail           string  `json:"detail"`
	DurationMinutes  int     `json:"durationMinutes"`
	FollowUpRequired bool    `json:"followUpRequired"`
	FollowUpDate     *string `json:"followUpDate,omitempty"`
	FollowUpNote     *string `json:"followUpNote,omitempty"`
}

// UpdateStatusRequest はステータス更新リクエストの構造体。
type UpdateStatusRequest struct {
	Status     string `json:"status"`
	ApprovedBy string `json:"approvedBy,omitempty"`
}

// ListReportsFilter は日報一覧取得時のフィルタ条件。
type ListReportsFilter struct {
	Status   string
	Region   string
	DateFrom string
	DateTo   string
}

// ============================================================
// レスポンス DTO
// ============================================================

// ErrorResponse はエラーレスポンスの構造体。
type ErrorResponse struct {
	Error string `json:"error"`
	Code  string `json:"code"`
}

// ============================================================
// バリデーション
// ============================================================

// ValidVisitPurposes は訪問目的の有効値リスト。
var ValidVisitPurposes = []string{"定期巡回", "緊急対応", "新規オープン支援", "研修", "監査"}

// ValidConditions は店舗総合評価の有効値リスト。
var ValidConditions = []string{"A", "B", "C", "D"}

// ValidStatuses はステータスの有効値リスト。
var ValidStatuses = []string{"下書き", "提出済", "承認済", "差戻し"}

// ValidCategories はカウンセリング分類の有効値リスト。
var ValidCategories = []string{"業務改善", "人材育成", "クレーム対応", "売上分析", "衛生管理", "その他"}

// Contains はスライスに値が含まれるか判定するヘルパー。
func Contains(slice []string, val string) bool {
	for _, s := range slice {
		if s == val {
			return true
		}
	}
	return false
}
