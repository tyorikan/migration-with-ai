package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
)

// クリーンアーキテクチャを意識し、型（Entity）を定義
type Account struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Industry string `json:"industry"`
	Status   string `json:"status"`
}

// データベースアクセス層（Repository Interface / Stub）
type AccountRepository interface {
	FetchActiveAccounts() ([]Account, error)
}

// Spanner または Cloud SQL 用の実装スタブ（Frameworks & Drivers）
type mockAccountRepo struct{}

func (m *mockAccountRepo) FetchActiveAccounts() ([]Account, error) {
	// ここに実データのフェッチ処理（Spanner API等）を記述するが、今回はスタブ
	return []Account{
		{ID: "001", Name: "Google Japan", Industry: "Technology", Status: "Active"},
		{ID: "002", Name: " Test Corp ", Industry: "Finance", Status: "Active"},
	}, nil
}

// ビジネスロジック関数（Use Cases）
func getActiveAccounts(repo AccountRepository) ([]Account, error) {
	accounts, err := repo.FetchActiveAccounts()
	if err != nil {
		return nil, err
	}

	var activeAccounts []Account
	for _, acc := range accounts {
		// 空チェックとトリムのApexロジックを再現
		if strings.TrimSpace(acc.Name) != "" {
			acc.Name = strings.TrimSpace(acc.Name)
			activeAccounts = append(activeAccounts, acc)
		}
	}
	return activeAccounts, nil
}

// APIハンドラー群（Interface Adapters）
func accountHandler(w http.ResponseWriter, r *http.Request) {
	repo := &mockAccountRepo{}
	
	accounts, err := getActiveAccounts(repo)
	if err != nil {
		http.Error(w, "取引先の取得中にエラーが発生しました。", http.StatusInternalServerError)
		log.Printf("Error fetching accounts: %v", err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(accounts); err != nil {
		http.Error(w, "JSONのエンコードに失敗しました", http.StatusInternalServerError)
	}
}

func main() {
	http.HandleFunc("/accounts", accountHandler)

	// Cloud Run 等の実行環境では $PORT 環境変数でポートが指定される
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
