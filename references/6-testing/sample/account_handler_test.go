package handler_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	// プロジェクト固有のパッケージ (実際のモジュールパスに置き換えてください)
	// "example.com/sfdc-migration/internal/handler"
	// "example.com/sfdc-migration/internal/model"
	// "example.com/sfdc-migration/internal/repository"
)

// =============================================================================
// Account CRUD API のユニットテスト (Table-Driven Tests)
// =============================================================================
// このファイルは、Gemini 等の AI によるテスト生成の「参考例」として使用します。
// AI に渡す際、プロジェクトのコーディング規約やテストスタイルのサンプルとして活用してください。
//
// テスト方針:
//   - DB への依存はインターフェース + モックで分離
//   - Table-driven tests で正常系・異常系を網羅
//   - testify/assert でアサーション
// =============================================================================

// --- モデル定義 (実際は internal/model パッケージに配置) ---

// Account は SFDC の Account オブジェクトに対応する構造体です。
type Account struct {
	ID                string  `json:"id"`
	Name              string  `json:"name"`
	AccountType       *string `json:"account_type,omitempty"`
	Industry          *string `json:"industry,omitempty"`
	AnnualRevenue     *float64 `json:"annual_revenue,omitempty"`
	NumberOfEmployees *int    `json:"number_of_employees,omitempty"`
	Phone             *string `json:"phone,omitempty"`
	Website           *string `json:"website,omitempty"`
}

// --- リポジトリインターフェース (internal/repository) ---
// DB 操作をインターフェースで抽象化し、テスト時にモックに差し替え可能にする。

type AccountRepository interface {
	GetByID(ctx context.Context, id string) (*Account, error)
	Create(ctx context.Context, account *Account) error
	Update(ctx context.Context, account *Account) error
	Delete(ctx context.Context, id string) error
	List(ctx context.Context, limit, offset int) ([]*Account, error)
}

// --- モックリポジトリ ---

type mockAccountRepo struct {
	getByIDFunc func(ctx context.Context, id string) (*Account, error)
	createFunc  func(ctx context.Context, account *Account) error
	updateFunc  func(ctx context.Context, account *Account) error
	deleteFunc  func(ctx context.Context, id string) error
	listFunc    func(ctx context.Context, limit, offset int) ([]*Account, error)
}

func (m *mockAccountRepo) GetByID(ctx context.Context, id string) (*Account, error) {
	return m.getByIDFunc(ctx, id)
}

func (m *mockAccountRepo) Create(ctx context.Context, account *Account) error {
	return m.createFunc(ctx, account)
}

func (m *mockAccountRepo) Update(ctx context.Context, account *Account) error {
	return m.updateFunc(ctx, account)
}

func (m *mockAccountRepo) Delete(ctx context.Context, id string) error {
	return m.deleteFunc(ctx, id)
}

func (m *mockAccountRepo) List(ctx context.Context, limit, offset int) ([]*Account, error) {
	return m.listFunc(ctx, limit, offset)
}

// --- ハンドラ定義 (簡易版) ---

type AccountHandler struct {
	repo AccountRepository
}

func NewAccountHandler(repo AccountRepository) *AccountHandler {
	return &AccountHandler{repo: repo}
}

func (h *AccountHandler) GetAccount(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if id == "" {
		http.Error(w, `{"error":"id is required"}`, http.StatusBadRequest)
		return
	}

	account, err := h.repo.GetByID(r.Context(), id)
	if err != nil {
		http.Error(w, `{"error":"internal server error"}`, http.StatusInternalServerError)
		return
	}
	if account == nil {
		http.Error(w, `{"error":"account not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(account)
}

func (h *AccountHandler) CreateAccount(w http.ResponseWriter, r *http.Request) {
	var account Account
	if err := json.NewDecoder(r.Body).Decode(&account); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if account.Name == "" {
		http.Error(w, `{"error":"name is required"}`, http.StatusBadRequest)
		return
	}

	if err := h.repo.Create(r.Context(), &account); err != nil {
		http.Error(w, `{"error":"failed to create account"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(account)
}

// =============================================================================
// テスト: GetAccount (取得 API)
// =============================================================================

func TestGetAccount(t *testing.T) {
	industry := "Technology"
	revenue := 1000000.50

	tests := []struct {
		name           string
		queryID        string
		mockSetup      func() *mockAccountRepo
		wantStatusCode int
		wantBodyContains string
	}{
		{
			name:    "正常系: 有効な ID で Account を取得",
			queryID: "001xx000003DGpcAAG",
			mockSetup: func() *mockAccountRepo {
				return &mockAccountRepo{
					getByIDFunc: func(ctx context.Context, id string) (*Account, error) {
						return &Account{
							ID:            "001xx000003DGpcAAG",
							Name:          "株式会社テスト",
							Industry:      &industry,
							AnnualRevenue: &revenue,
						}, nil
					},
				}
			},
			wantStatusCode:   http.StatusOK,
			wantBodyContains: "株式会社テスト",
		},
		{
			name:    "異常系: ID が空の場合 400 エラー",
			queryID: "",
			mockSetup: func() *mockAccountRepo {
				return &mockAccountRepo{
					getByIDFunc: func(ctx context.Context, id string) (*Account, error) {
						t.Fatal("GetByID should not be called when ID is empty")
						return nil, nil
					},
				}
			},
			wantStatusCode:   http.StatusBadRequest,
			wantBodyContains: "id is required",
		},
		{
			name:    "異常系: 存在しない ID で 404 エラー",
			queryID: "001xx000003NOTEXIST",
			mockSetup: func() *mockAccountRepo {
				return &mockAccountRepo{
					getByIDFunc: func(ctx context.Context, id string) (*Account, error) {
						return nil, nil // Not found
					},
				}
			},
			wantStatusCode:   http.StatusNotFound,
			wantBodyContains: "account not found",
		},
		{
			name:    "異常系: DB エラーで 500 エラー",
			queryID: "001xx000003DGpcAAG",
			mockSetup: func() *mockAccountRepo {
				return &mockAccountRepo{
					getByIDFunc: func(ctx context.Context, id string) (*Account, error) {
						return nil, errors.New("connection refused")
					},
				}
			},
			wantStatusCode:   http.StatusInternalServerError,
			wantBodyContains: "internal server error",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Arrange
			handler := NewAccountHandler(tt.mockSetup())
			req := httptest.NewRequest(http.MethodGet, "/accounts?id="+tt.queryID, nil)
			rec := httptest.NewRecorder()

			// Act
			handler.GetAccount(rec, req)

			// Assert
			if rec.Code != tt.wantStatusCode {
				t.Errorf("status code = %d, want %d", rec.Code, tt.wantStatusCode)
			}
			body := rec.Body.String()
			if !strings.Contains(body, tt.wantBodyContains) {
				t.Errorf("body = %q, want to contain %q", body, tt.wantBodyContains)
			}
		})
	}
}

// =============================================================================
// テスト: CreateAccount (作成 API)
// =============================================================================

func TestCreateAccount(t *testing.T) {
	tests := []struct {
		name           string
		requestBody    string
		mockSetup      func() *mockAccountRepo
		wantStatusCode int
		wantBodyContains string
	}{
		{
			name:        "正常系: 最小限の項目で Account を作成",
			requestBody: `{"id":"001xx000003NEW01","name":"新規取引先"}`,
			mockSetup: func() *mockAccountRepo {
				return &mockAccountRepo{
					createFunc: func(ctx context.Context, account *Account) error {
						return nil
					},
				}
			},
			wantStatusCode:   http.StatusCreated,
			wantBodyContains: "新規取引先",
		},
		{
			name:        "正常系: 日本語の全角文字を含む Account を作成",
			requestBody: `{"id":"001xx000003NEW02","name":"㈱テスト・コーポレーション　東京支社（代表）"}`,
			mockSetup: func() *mockAccountRepo {
				return &mockAccountRepo{
					createFunc: func(ctx context.Context, account *Account) error {
						return nil
					},
				}
			},
			wantStatusCode:   http.StatusCreated,
			wantBodyContains: "㈱テスト・コーポレーション",
		},
		{
			name:        "異常系: name が空の場合 400 エラー",
			requestBody: `{"id":"001xx000003NEW03","name":""}`,
			mockSetup: func() *mockAccountRepo {
				return &mockAccountRepo{
					createFunc: func(ctx context.Context, account *Account) error {
						t.Fatal("Create should not be called when name is empty")
						return nil
					},
				}
			},
			wantStatusCode:   http.StatusBadRequest,
			wantBodyContains: "name is required",
		},
		{
			name:        "異常系: 不正な JSON",
			requestBody: `{invalid json}`,
			mockSetup: func() *mockAccountRepo {
				return &mockAccountRepo{
					createFunc: func(ctx context.Context, account *Account) error {
						t.Fatal("Create should not be called on invalid JSON")
						return nil
					},
				}
			},
			wantStatusCode:   http.StatusBadRequest,
			wantBodyContains: "invalid request body",
		},
		{
			name:        "異常系: DB 書き込みエラー",
			requestBody: `{"id":"001xx000003NEW04","name":"DBエラーテスト"}`,
			mockSetup: func() *mockAccountRepo {
				return &mockAccountRepo{
					createFunc: func(ctx context.Context, account *Account) error {
						return errors.New("duplicate key violation")
					},
				}
			},
			wantStatusCode:   http.StatusInternalServerError,
			wantBodyContains: "failed to create account",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := NewAccountHandler(tt.mockSetup())
			req := httptest.NewRequest(http.MethodPost, "/accounts", strings.NewReader(tt.requestBody))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()

			handler.CreateAccount(rec, req)

			if rec.Code != tt.wantStatusCode {
				t.Errorf("status code = %d, want %d", rec.Code, tt.wantStatusCode)
			}
			body := rec.Body.String()
			if !strings.Contains(body, tt.wantBodyContains) {
				t.Errorf("body = %q, want to contain %q", body, tt.wantBodyContains)
			}
		})
	}
}
