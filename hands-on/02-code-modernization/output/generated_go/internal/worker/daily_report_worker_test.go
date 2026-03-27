// Package worker_test は go-sqlmock を使った worker 層のテストを提供する。
// イベント受信からトランザクション内の UPDATE / SELECT / INSERT を検証する。
package worker_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"testing"

	"daily-report-api/internal/event"
	"daily-report-api/internal/worker"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

// ============================================================
// ヘルパー
// ============================================================

func newMockDB(t *testing.T) (*sql.DB, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("failed to create sqlmock: %v", err)
	}
	t.Cleanup(func() { db.Close() })
	return db, mock
}

func newTestLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
}

func validEvent() event.ReportSubmittedEvent {
	return event.ReportSubmittedEvent{
		EventID:      "evt-001",
		ReportID:     "r1",
		AccountID:    "acc-1",
		SupervisorID: "sup-1",
		ReportDate:   "2025-01-15",
	}
}

func marshalEvent(t *testing.T, evt event.ReportSubmittedEvent) []byte {
	t.Helper()
	data, err := json.Marshal(evt)
	if err != nil {
		t.Fatalf("failed to marshal event: %v", err)
	}
	return data
}

// ============================================================
// HandleReportSubmitted テスト
// ============================================================

func TestHandleReportSubmitted_Success_NoFollowUps(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	w := worker.NewDailyReportWorker(db, newTestLogger())

	mock.ExpectBegin()
	// updateLastVisitDate
	mock.ExpectExec("UPDATE accounts").
		WillReturnResult(sqlmock.NewResult(0, 1))
	// createFollowUpTasks — 該当レコードなし
	mock.ExpectQuery("SELECT").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "contact_id", "category",
			"follow_up_date", "follow_up_note", "contact_last_name",
		}))
	mock.ExpectCommit()

	err := w.HandleReportSubmitted(context.Background(), marshalEvent(t, validEvent()))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

func TestHandleReportSubmitted_Success_WithFollowUps(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	w := worker.NewDailyReportWorker(db, newTestLogger())

	mock.ExpectBegin()
	// updateLastVisitDate
	mock.ExpectExec("UPDATE accounts").
		WillReturnResult(sqlmock.NewResult(0, 1))
	// createFollowUpTasks — 2 件のフォローアップ
	followUpRows := sqlmock.NewRows([]string{
		"id", "contact_id", "category",
		"follow_up_date", "follow_up_note", "contact_last_name",
	}).
		AddRow("cr1", "c1", "業務改善", "2025-01-22", "メモ1", "田中").
		AddRow("cr2", "c2", "人材育成", nil, nil, "佐藤")

	mock.ExpectQuery("SELECT").WillReturnRows(followUpRows)
	// 2 件の INSERT
	mock.ExpectExec("INSERT INTO follow_up_tasks").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO follow_up_tasks").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	err := w.HandleReportSubmitted(context.Background(), marshalEvent(t, validEvent()))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

func TestHandleReportSubmitted_InvalidJSON(t *testing.T) {
	t.Parallel()
	db, _ := newMockDB(t)
	w := worker.NewDailyReportWorker(db, newTestLogger())

	err := w.HandleReportSubmitted(context.Background(), []byte("{invalid"))
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}
}

func TestHandleReportSubmitted_BeginTxError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	w := worker.NewDailyReportWorker(db, newTestLogger())

	mock.ExpectBegin().WillReturnError(errors.New("tx error"))

	err := w.HandleReportSubmitted(context.Background(), marshalEvent(t, validEvent()))
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestHandleReportSubmitted_UpdateVisitDateError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	w := worker.NewDailyReportWorker(db, newTestLogger())

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE accounts").
		WillReturnError(errors.New("update failed"))
	mock.ExpectRollback()

	err := w.HandleReportSubmitted(context.Background(), marshalEvent(t, validEvent()))
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestHandleReportSubmitted_SelectFollowUpError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	w := worker.NewDailyReportWorker(db, newTestLogger())

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE accounts").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT").
		WillReturnError(errors.New("select failed"))
	mock.ExpectRollback()

	err := w.HandleReportSubmitted(context.Background(), marshalEvent(t, validEvent()))
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestHandleReportSubmitted_InsertTaskError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	w := worker.NewDailyReportWorker(db, newTestLogger())

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE accounts").
		WillReturnResult(sqlmock.NewResult(0, 1))
	followUpRows := sqlmock.NewRows([]string{
		"id", "contact_id", "category",
		"follow_up_date", "follow_up_note", "contact_last_name",
	}).AddRow("cr1", "c1", "業務改善", "2025-01-22", "メモ", "田中")
	mock.ExpectQuery("SELECT").WillReturnRows(followUpRows)
	mock.ExpectExec("INSERT INTO follow_up_tasks").
		WillReturnError(errors.New("constraint violation"))
	mock.ExpectRollback()

	err := w.HandleReportSubmitted(context.Background(), marshalEvent(t, validEvent()))
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestHandleReportSubmitted_CommitError(t *testing.T) {
	t.Parallel()
	db, mock := newMockDB(t)
	w := worker.NewDailyReportWorker(db, newTestLogger())

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE accounts").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "contact_id", "category",
			"follow_up_date", "follow_up_note", "contact_last_name",
		}))
	mock.ExpectCommit().WillReturnError(errors.New("commit failed"))

	err := w.HandleReportSubmitted(context.Background(), marshalEvent(t, validEvent()))
	if err == nil {
		t.Fatal("expected error for commit failure")
	}
}
