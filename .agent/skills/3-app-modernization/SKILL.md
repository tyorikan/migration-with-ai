---
name: workshop-app-modernization
description: Modernize applications by converting legacy logic to a modern backend running on Cloud Run or GKE using AI-driven development. Use when the user wants to refactor legacy code, translate Apex to modern languages, or containerize apps.
---
# アプリのモダナイズ (App Modernization) スキル

このスキルは、SFDC上に構築されたレガシーなビジネスロジック（Apexクラスやトリガー等）を、コンテナ化されたモダンなマイクロサービスアーキテクチャにリファクタリング・移行するための支援を行います。主に **Cloud Run** や **GKE** へのデプロイを前提としています。

## モダナイゼーションの基本戦略
1. **Stateless Service へのアーキテクチャ変更**
   - Cloud Run で水平スケールさせるため、処理はステートレスにし、セッションやトランザクション状態は Spanner や Cloud SQL 等の外部に持たせる設計をガイドします。
2. **AI駆動によるコード翻訳**
   - 古いApexコードをそのままインフラに載せ替えるのではなく、Geminiを活用して クリーンアーキテクチャ に基づく Go, Python, TypeScript ガイドラインに沿ったコードに翻訳します。

## Apex からのモダン言語変換プロセス
AIを用いて、レガシーコードからビジネス要件を抽出し、新しい言語に書き直させます。

### コード変換のプロンプト・テンプレート
```markdown
以下のSalesforce Apexクラスのコードを分析し、Go言語を用いたREST APIバックエンドのコードとして再実装してください。
要件:
- `net/http` あるいは `gorilla/mux` を用いてエンドポイントを作成すること。
- ビジネスロジック関数とデータベースアクス関数は分離すること（クリーンアーキテクチャ）。
- データベースはCloud Spannerを想定し、ORMではなく `cloud.google.com/go/spanner` パッケージを用いたアクセス処理のスタブを作成すること。
- エラーハンドリングを適切に行うこと。

【対象のApexコード】
(ここにコードを挿入)
```

## コンテナ化 (Docker) とローカル検証
翻訳されたアプリケーションが Cloud Run にデプロイできるように、`Dockerfile` の作成をお客様と実施します。

### サンプル: 汎用的な Go アプリケーションの Dockerfile
```dockerfile
# Build ステージ
FROM golang:1.26-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# セキュリティ・軽量化のため CGO 無効で静的バイナリを作成
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

# Run ステージ (Distrolessイメージの推奨パターン)
FROM gcr.io/distroless/static-debian12
WORKDIR /app
COPY --from=builder /app/main .

# Cloud Run は環境変数 $PORT で待ち受けポートが注入される
ENV PORT=8080
EXPOSE 8080

CMD ["/app/main"]
```

## Cloud Run の検証デプロイ
お客様の手元（あるいはCloud Shell）ですぐに動作確認ができるよう、以下のgcloudコマンドを用いたデプロイ手順を提供します。

```bash
gcloud run deploy my-modern-app \
  --source . \
  --region asia-northeast1 \
  --allow-unauthenticated
```
この時、背後で Cloud Build が自動でコンテナビルドを行ってくれる体験（Source-based Deployment）をお客様に体感してもらうことを重視してください。

## GKE Autopilot の検証デプロイ
エンタープライズ要件により、Kubernetes の採用が必要な場合は **GKE Autopilot** を推奨します。ノード管理が不要で Cloud Run に近い運用体験を提供しつつ、K8s の強力なエコシステムをフル活用できます。

マニフェストファイル (Deployment, Service 等) は AI に自動生成させ、お客様にデプロイの流れを体験していただきます。
```bash
kubectl apply -f k8s/
```
