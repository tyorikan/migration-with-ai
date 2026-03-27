// Package event の InMemoryPublisher テスト。
package event

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"testing"
)

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
}

// ============================================================
// InMemoryPublisher テスト
// ============================================================

func TestInMemoryPublisher_Publish_Success(t *testing.T) {
	t.Parallel()
	pub := NewInMemoryPublisher(testLogger())

	var received []byte
	pub.Subscribe("test-topic", func(_ context.Context, data []byte) error {
		received = data
		return nil
	})

	evt := map[string]string{"key": "value"}
	if err := pub.Publish(context.Background(), "test-topic", evt); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if received == nil {
		t.Fatal("handler was not called")
	}

	var result map[string]string
	if err := json.Unmarshal(received, &result); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	if result["key"] != "value" {
		t.Errorf("key = %q, want %q", result["key"], "value")
	}
}

func TestInMemoryPublisher_NoHandlers(t *testing.T) {
	t.Parallel()
	pub := NewInMemoryPublisher(testLogger())

	// ハンドラー未登録でもエラーにならない（warn ログのみ）
	if err := pub.Publish(context.Background(), "no-handler-topic", "data"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestInMemoryPublisher_MultipleHandlers(t *testing.T) {
	t.Parallel()
	pub := NewInMemoryPublisher(testLogger())

	callCount := 0
	handler := func(_ context.Context, _ []byte) error {
		callCount++
		return nil
	}

	pub.Subscribe("multi", handler)
	pub.Subscribe("multi", handler)
	pub.Subscribe("multi", handler)

	if err := pub.Publish(context.Background(), "multi", "test"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if callCount != 3 {
		t.Errorf("callCount = %d, want 3", callCount)
	}
}

func TestInMemoryPublisher_HandlerError_ContinuesOthers(t *testing.T) {
	t.Parallel()
	pub := NewInMemoryPublisher(testLogger())

	secondCalled := false
	pub.Subscribe("err-topic", func(_ context.Context, _ []byte) error {
		return errors.New("handler1 failed")
	})
	pub.Subscribe("err-topic", func(_ context.Context, _ []byte) error {
		secondCalled = true
		return nil
	})

	// 最初のハンドラーがエラーでも全体はエラーにならず、2番目も実行される
	if err := pub.Publish(context.Background(), "err-topic", "data"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !secondCalled {
		t.Error("second handler should have been called despite first handler error")
	}
}

func TestInMemoryPublisher_TopicIsolation(t *testing.T) {
	t.Parallel()
	pub := NewInMemoryPublisher(testLogger())

	topicACalled := false
	pub.Subscribe("topic-a", func(_ context.Context, _ []byte) error {
		topicACalled = true
		return nil
	})

	// topic-b にパブリッシュしても topic-a のハンドラーは呼ばれない
	if err := pub.Publish(context.Background(), "topic-b", "data"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if topicACalled {
		t.Error("topic-a handler should NOT have been called for topic-b")
	}
}

// ============================================================
// PublishReportSubmitted テスト
// ============================================================

func TestPublishReportSubmitted_SetsMetadata(t *testing.T) {
	t.Parallel()
	pub := NewInMemoryPublisher(testLogger())

	var received []byte
	pub.Subscribe(TopicReportSubmitted, func(_ context.Context, data []byte) error {
		received = data
		return nil
	})

	evt := ReportSubmittedEvent{
		ReportID:     "r1",
		ReportDate:   "2025-01-15",
		AccountID:    "acc-001",
		SupervisorID: "sup-001",
	}
	if err := PublishReportSubmitted(context.Background(), pub, evt); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var result ReportSubmittedEvent
	if err := json.Unmarshal(received, &result); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	if result.EventType != "report.submitted" {
		t.Errorf("EventType = %q, want %q", result.EventType, "report.submitted")
	}
	if result.Timestamp.IsZero() {
		t.Error("Timestamp should be set")
	}
	if result.ReportID != "r1" {
		t.Errorf("ReportID = %q, want %q", result.ReportID, "r1")
	}
}
