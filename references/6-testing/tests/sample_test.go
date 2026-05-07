package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// これはあくまでワークショップにおける説明用（Gemini生成コードのイメージ）のスタブです。
// 実際には 3-app-modernize 等で作成したハンドラを呼び出します。

func TestHealthCheckHandler(t *testing.T) {
	// 擬似的なハンドラ (実際は main.go などからインポート)
	healthHandler := func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	}

	req, err := http.NewRequest("GET", "/health", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(healthHandler)

	// ハンドラを実行
	handler.ServeHTTP(rr, req)

	// 1. ステータスコードの検証
	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
	}

	// 2. レスポンスボディの検証
	var response map[string]string
	err = json.Unmarshal(rr.Body.Bytes(), &response)
	if err != nil {
		t.Fatalf("Failed to parse response body: %v", err)
	}

	if response["status"] != "ok" {
		t.Errorf("handler returned unexpected body: got %v want %v", response["status"], "ok")
	}
}
