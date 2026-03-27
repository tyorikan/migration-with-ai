// Package event はイベント駆動アーキテクチャの発行側を提供する。
// 日報ステータス変更時にイベント（JSON）を発行する。
// 将来 Pub/Sub に繋ぐことを念頭に、Publisher インターフェースで抽象化している。
package event

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"
)

// ============================================================
// イベント型定義
// ============================================================

// ReportSubmittedEvent は日報が「提出済」に変更されたときに発行されるイベント。
// Apex Trigger の Trigger.new → Trigger.oldMap 比較に相当。
type ReportSubmittedEvent struct {
	// イベントメタデータ
	EventID   string    `json:"eventId"`   // 冪等性キー（UUID）
	EventType string    `json:"eventType"` // "report.submitted"
	Timestamp time.Time `json:"timestamp"`

	// ペイロード
	ReportID     string `json:"reportId"`
	ReportDate   string `json:"reportDate"`   // YYYY-MM-DD
	AccountID    string `json:"accountId"`
	SupervisorID string `json:"supervisorId"`
}

// FollowUpTask はフォローアップタスク作成用の構造体。
// Apex Trigger の Task オブジェクトに対応。
type FollowUpTask struct {
	ID              string  `json:"id"`
	Subject         string  `json:"subject"`
	Description     *string `json:"description,omitempty"`
	OwnerID         string  `json:"ownerId"`         // Supervisor
	ContactID       string  `json:"contactId"`       // WhoId
	DailyReportID   string  `json:"dailyReportId"`   // WhatId
	DueDate         string  `json:"dueDate"`          // ActivityDate (YYYY-MM-DD)
	Priority        string  `json:"priority"`         // "High"
	Status          string  `json:"status"`           // "Not Started"
	CounselingRecID string  `json:"counselingRecId"` // 冪等性チェック用
}

// ============================================================
// Publisher インターフェース（将来 Pub/Sub に差し替え可能）
// ============================================================

// Publisher はイベントを発行するインターフェース。
// 実装例:
//   - InMemoryPublisher: テスト・ローカル開発用
//   - PubSubPublisher:   本番 Google Cloud Pub/Sub 用（将来実装）
type Publisher interface {
	Publish(ctx context.Context, topic string, event interface{}) error
}

// ============================================================
// InMemoryPublisher（ローカル開発・テスト用）
// ============================================================

// HandlerFunc はイベント受信時のコールバック関数型。
type HandlerFunc func(ctx context.Context, data []byte) error

// InMemoryPublisher はインメモリでイベントを処理する Publisher 実装。
// Publish 即座に登録済みハンドラーを呼び出す（同期処理）。
type InMemoryPublisher struct {
	handlers map[string][]HandlerFunc
	logger   *slog.Logger
}

// NewInMemoryPublisher は InMemoryPublisher の新しいインスタンスを生成する。
func NewInMemoryPublisher(logger *slog.Logger) *InMemoryPublisher {
	return &InMemoryPublisher{
		handlers: make(map[string][]HandlerFunc),
		logger:   logger,
	}
}

// Subscribe はトピックにハンドラーを登録する。
func (p *InMemoryPublisher) Subscribe(topic string, handler HandlerFunc) {
	p.handlers[topic] = append(p.handlers[topic], handler)
}

// Publish はイベントを JSON にシリアライズし、登録済みハンドラーに配信する。
func (p *InMemoryPublisher) Publish(ctx context.Context, topic string, event interface{}) error {
	data, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("InMemoryPublisher: marshal failed: %w", err)
	}

	p.logger.Info("event published",
		slog.String("topic", topic),
		slog.Int("dataSize", len(data)),
	)

	handlers, ok := p.handlers[topic]
	if !ok {
		p.logger.Warn("no handlers registered", slog.String("topic", topic))
		return nil
	}

	for _, h := range handlers {
		if err := h(ctx, data); err != nil {
			p.logger.Error("handler failed",
				slog.String("topic", topic),
				slog.String("error", err.Error()),
			)
			// ハンドラーのエラーは記録するが、他のハンドラーの実行は継続
		}
	}

	return nil
}

// ============================================================
// イベント発行ヘルパー
// ============================================================

// TopicReportSubmitted はイベントトピック名。
const TopicReportSubmitted = "daily-report.submitted"

// PublishReportSubmitted は日報提出イベントを発行する。
// handler/usecase のステータス更新処理から呼び出される。
func PublishReportSubmitted(ctx context.Context, pub Publisher, evt ReportSubmittedEvent) error {
	evt.EventType = "report.submitted"
	evt.Timestamp = time.Now()
	return pub.Publish(ctx, TopicReportSubmitted, evt)
}
