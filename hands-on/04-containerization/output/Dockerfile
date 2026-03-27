# ============================================================
# SV 業務日報 API — セキュア Dockerfile
# マルチステージビルド + distroless nonroot
# ============================================================

# ----------------------------------------------------------
# Stage 1: Build
# ----------------------------------------------------------
FROM golang:1.24-bookworm AS builder

WORKDIR /src

# 依存キャッシュ: go.mod / go.sum を先にコピーして go mod download
COPY go.mod go.sum ./
RUN go mod download

# ソースコードをコピーしてビルド
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" \
    -o /out/server ./cmd/server/main.go

# ----------------------------------------------------------
# Stage 2: Runtime (distroless nonroot)
# ----------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot

# メタデータ
LABEL maintainer="[EMAIL_ADDRESS]"
LABEL description="SV Daily Report API — Go + Cloud Run"

# ビルドステージからバイナリのみコピー
COPY --from=builder /out/server /server

# nonroot ユーザーで実行（UID 65532）
USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/server"]
