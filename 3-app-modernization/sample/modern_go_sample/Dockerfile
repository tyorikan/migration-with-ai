# 1. Build ステージ
# Go 1.26 の軽量な alpine イメージを使用
FROM golang:1.26-alpine AS builder

WORKDIR /app

# go.mod と go.sum を利用する場合はコメントアウトを外す
# COPY go.mod go.sum ./
# RUN go mod download

# ソースコードをコピー
COPY . .

# go mod init されていない場合の手動初期化（サンプルのため）
RUN go mod init modern_app || true

# セキュリティおよび軽量化のため、CGO 無効で静的バイナリを作成
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

# 2. Run ステージ
# Google 提供のセキュアな静的イメージを利用 (コンパイル済みバイナリのみ配置)
FROM gcr.io/distroless/static-debian12

WORKDIR /app

# ビルドステージからコンパイル済みバイナリのみをコピー
COPY --from=builder /app/main .

# Cloud Run から渡される環境変数ポートを利用
ENV PORT=8080
EXPOSE 8080

# アプリケーションの実行
CMD ["/app/main"]
