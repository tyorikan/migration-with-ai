#!/bin/bash
# -----------------------------------------------------------------------------
# テスト実行およびカバレッジレポート生成スクリプト
# -----------------------------------------------------------------------------

set -e # エラーが発生した場合は直ちに終了

echo "Running tests and generating coverage..."

# カバレッジファイルを出力しつつテストを実行
go test -v -coverprofile=coverage.out ./...

echo ""
echo "=== Test Coverage Summary ==="
# 関数ごとのカバレッジ率を表示
go tool cover -func=coverage.out

echo ""
# HTML形式のカバレッジレポートを生成（ローカルで確認する場合に便利）
go tool cover -html=coverage.out -o coverage.html
echo "HTML coverage report generated: coverage.html"

# 必要に応じて、カバレッジ要件（例: 80%以上でパスとするなど）のチェックをここに追加します
# coverage_percent=$(go tool cover -func=coverage.out | grep total | awk '{print substr($3, 1, length($3)-1)}' | awk '{printf "%.0f\n", $1}')
# if [ "$coverage_percent" -lt 80 ]; then
#   echo "Error: Test coverage ($coverage_percent%) is below the required threshold of 80%."
#   exit 1
# fi

echo "Tests completed successfully."
