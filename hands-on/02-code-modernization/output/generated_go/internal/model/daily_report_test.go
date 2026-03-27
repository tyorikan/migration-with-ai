// Package model のバリデーションテスト。
// 対象: Contains ヘルパー、Picklist 定数、構造体フィールド。
package model

import "testing"

// ============================================================
// Contains ヘルパー
// ============================================================

func TestContains_Found(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		slice []string
		val   string
		want  bool
	}{
		{"先頭一致", []string{"A", "B", "C"}, "A", true},
		{"中間一致", []string{"A", "B", "C"}, "B", true},
		{"末尾一致", []string{"A", "B", "C"}, "C", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := Contains(tt.slice, tt.val); got != tt.want {
				t.Errorf("Contains(%v, %q) = %v, want %v", tt.slice, tt.val, got, tt.want)
			}
		})
	}
}

func TestContains_NotFound(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		slice []string
		val   string
	}{
		{"存在しない値", []string{"A", "B", "C"}, "D"},
		{"空のスライス", []string{}, "A"},
		{"空文字列を検索", []string{"A", "B"}, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if Contains(tt.slice, tt.val) {
				t.Errorf("Contains(%v, %q) = true, want false", tt.slice, tt.val)
			}
		})
	}
}

// ============================================================
// ValidVisitPurposes バリデーション
// ============================================================

func TestValidVisitPurposes_AllValid(t *testing.T) {
	t.Parallel()
	valid := []string{"定期巡回", "緊急対応", "新規オープン支援", "研修", "監査"}
	for _, v := range valid {
		t.Run(v, func(t *testing.T) {
			t.Parallel()
			if !Contains(ValidVisitPurposes, v) {
				t.Errorf("%q は有効な訪問目的として認識されるべき", v)
			}
		})
	}
}

func TestValidVisitPurposes_Invalid(t *testing.T) {
	t.Parallel()
	invalid := []string{"お見舞い", "営業", "", "定期巡回 "}
	for _, v := range invalid {
		t.Run("invalid_"+v, func(t *testing.T) {
			t.Parallel()
			if Contains(ValidVisitPurposes, v) {
				t.Errorf("%q は無効な訪問目的のはず", v)
			}
		})
	}
}

// ============================================================
// ValidConditions バリデーション
// ============================================================

func TestValidConditions_AllValid(t *testing.T) {
	t.Parallel()
	for _, v := range ValidConditions {
		t.Run(v, func(t *testing.T) {
			t.Parallel()
			if !Contains(ValidConditions, v) {
				t.Errorf("%q は有効な評価として認識されるべき", v)
			}
		})
	}
}

func TestValidConditions_Invalid(t *testing.T) {
	t.Parallel()
	invalid := []string{"E", "a", "AB", ""}
	for _, v := range invalid {
		t.Run("invalid_"+v, func(t *testing.T) {
			t.Parallel()
			if Contains(ValidConditions, v) {
				t.Errorf("%q は無効な評価のはず", v)
			}
		})
	}
}

// ============================================================
// ValidStatuses バリデーション
// ============================================================

func TestValidStatuses_AllValid(t *testing.T) {
	t.Parallel()
	expected := []string{"下書き", "提出済", "承認済", "差戻し"}
	for _, v := range expected {
		t.Run(v, func(t *testing.T) {
			t.Parallel()
			if !Contains(ValidStatuses, v) {
				t.Errorf("%q は有効なステータスとして認識されるべき", v)
			}
		})
	}
}

func TestValidStatuses_Invalid(t *testing.T) {
	t.Parallel()
	invalid := []string{"完了", "取消", "draft", ""}
	for _, v := range invalid {
		t.Run("invalid_"+v, func(t *testing.T) {
			t.Parallel()
			if Contains(ValidStatuses, v) {
				t.Errorf("%q は無効なステータスのはず", v)
			}
		})
	}
}

// ============================================================
// ValidCategories バリデーション
// ============================================================

func TestValidCategories_AllValid(t *testing.T) {
	t.Parallel()
	expected := []string{"業務改善", "人材育成", "クレーム対応", "売上分析", "衛生管理", "その他"}
	for _, v := range expected {
		t.Run(v, func(t *testing.T) {
			t.Parallel()
			if !Contains(ValidCategories, v) {
				t.Errorf("%q は有効なカテゴリとして認識されるべき", v)
			}
		})
	}
}

func TestValidCategories_Invalid(t *testing.T) {
	t.Parallel()
	invalid := []string{"経営戦略", "general", ""}
	for _, v := range invalid {
		t.Run("invalid_"+v, func(t *testing.T) {
			t.Parallel()
			if Contains(ValidCategories, v) {
				t.Errorf("%q は無効なカテゴリのはず", v)
			}
		})
	}
}

// ============================================================
// CreateReportRequest 構造体テスト
// ============================================================

func TestCreateReportRequest_PtrFields(t *testing.T) {
	t.Parallel()
	req := CreateReportRequest{
		ReportDate:       "2025-01-15",
		SupervisorID:     "sup-001",
		AccountID:        "acc-001",
		VisitStartTime:   "2025-01-15T09:00:00Z",
		VisitEndTime:     "2025-01-15T10:00:00Z",
		VisitPurpose:     "定期巡回",
		OverallCondition: "A",
		Summary:          nil,
		NextAction:       nil,
	}
	if req.Summary != nil {
		t.Error("Summary should be nil")
	}
	if req.NextAction != nil {
		t.Error("NextAction should be nil")
	}
}

// ============================================================
// UpdateStatusRequest 構造体テスト
// ============================================================

func TestUpdateStatusRequest_Fields(t *testing.T) {
	t.Parallel()
	req := UpdateStatusRequest{
		Status:     "承認済",
		ApprovedBy: "manager-001",
	}
	if req.Status != "承認済" {
		t.Errorf("Status = %q, want %q", req.Status, "承認済")
	}
	if req.ApprovedBy != "manager-001" {
		t.Errorf("ApprovedBy = %q, want %q", req.ApprovedBy, "manager-001")
	}
}

// ============================================================
// ListReportsFilter 構造体テスト
// ============================================================

func TestListReportsFilter_EmptyFilter(t *testing.T) {
	t.Parallel()
	filter := ListReportsFilter{}
	if filter.Status != "" || filter.Region != "" || filter.DateFrom != "" || filter.DateTo != "" {
		t.Error("空の ListReportsFilter の全フィールドはゼロ値であるべき")
	}
}
