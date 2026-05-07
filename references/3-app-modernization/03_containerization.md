# 03. コンテナ化 (Docker) と Artifact Registry への登録

## 目的
AI (Gemini) によって変換されたモダンなアプリケーションコード (Go, Python など) を、Google Cloud 環境 (Cloud Run, GKE Autopilot) で動作させるためにコンテナ（Docker イメージ）化するプロセスを学びます。また、作成したイメージを Google Cloud の Artifact Registry (AR) に登録するまでの手順を実践します。

## 対象となるコード
前のステップで変換されたコード（ここでは Go のサンプルを想定）を含んだ `sample/modern_go_sample/` ディレクトリを使用します。

## ベストプラクティスに基づいたコンテナ化

SFDC などのサーバレス環境からクラウドネイティブなコンテナプラットフォーム (Cloud Run / GKE Autopilot) へ移行する際、以下の原則に従ってコンテナイメージを作成します。

1. **小さく安全なベースイメージの選択:** Debian/Ubuntu のフルOSではなく、ビルド済みのバイナリのみを実行させる Distroless (Go等の場合) や、Alpine、スリム化されたベースイメージ (Python等の場合) を選択し、攻撃表面を減らします。
2. **マルチステージビルドの活用:** ビルド環境（コンパイラやツール）と実行環境を分離し、最終的なイメージサイズを最小化します。
3. **root ユーザー以外での実行 (Principle of Least Privilege):** コンテナ内プロセスは可能な限り root 以外のユーザー（UID/GID）で実行されるように Dockerfile を記述します。これは特に GKE で重要なセキュリティ・プラクティスです。
4. **ステートレスと環境変数の利用:** 設定値、DBのシークレット、API Key 等はイメージ内に含めず、すべて環境変数から実行時に注入される仕組みにします（Cloud Run / GKE の Secret/ConfigMap との親和性）。

---

## 1. Dockerfile の作成 (Go言語の例)

`sample/modern_go_sample/Dockerfile` として以下の実装例を用意しています。これはマルチステージビルド・Distroless・Non-root のベストプラクティスを盛り込んでいます。

```dockerfile
# ---- Build Stage ----
FROM golang:1.26-alpine AS builder

# 必要なパッケージ（git等）をインストール（今回はモジュールダウンロード用）
RUN apk update && apk add --no-cache git ca-certificates tzdata

WORKDIR /app

# 依存モジュールキャッシュ用のコピー (go.mod, go.sum がある場合)
# COPY go.mod go.sum ./
# RUN go mod download

# ソースコード全体をコピー
COPY . .

# セキュリティ対策: 非rootユーザーを作成しておく (UID/GID 10001)
RUN adduser -D -g '' -u 10001 appuser

# Static Binary としてビルド (CGO無効化)
# Cloud Run や GKE は Linux x86_64 環境が基本
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -installsuffix cgo -o main .

# ---- Final Stage (Runtime) ----
# distroless (static) をベースにする。シェルすら含まれない極小イメージ
FROM gcr.io/distroless/static-debian12:nonroot

# Build Stage から CA証明書とタイムゾーンをコピー
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Build Stage からユーザー情報をコピー
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Build Stage からコンパイル済みバイナリをコピー
COPY --from=builder /app/main /main

# 実行ユーザーを非root (appuser) に指定
USER appuser:appuser

# 8080ポートを Listen する (ドキュメント用)
EXPOSE 8080

# コンテナ起動時に実行されるコマンド
ENTRYPOINT ["/main"]
```

> **Note (Python などの場合)**: Python (Flask/FastAPI等) の場合は通常 `python:3.11-slim` などをベースにし、第1ステージで `pip install -r requirements.txt --target=/dependency` を行い、第2ステージ（ランタイム）でそれらをコピーし、gunicorn や uvicorn を非 root で起動する構成にします。


## 2. ローカルでのビルドと検証手順

Gemini との対話で生成したアプリケーションが、コンテナとして正しく動作するかローカルの Docker 環境で検証します。

```bash
# アプリケーションディレクトリへ移動
cd sample/modern_go_sample/

# Docker イメージのビルド
docker build -t app-modern-go:local .

# ダミーの環境変数を与えてコンテナを起動 (ローカルDBはないのでロジックの起動確認のみ)
docker run -p 8080:8080 \
  -e PORT=8080 \
  -e DB_CONNECTION_STRING="dummy" \
  app-modern-go:local
```

別のターミナルから `curl` を使って動作を確認します（Goサンプルの仕様に合わせてリクエストを送る）。

```bash
curl http://localhost:8080/api/convert
# (例えば 400 Bad Request 等、Goアプリケーション自身のハンドリング結果が返ってくればコンテナは正常稼働)
```

## 3. Artifact Registry への登録

ローカルで動作確認がとれた Docker イメージを、Google Cloud にデプロイするため **Artifact Registry** にプッシュします。

### 3.1. Artifact Registry リポジトリの作成

(1-onboarding の環境構築スクリプトで作成済みの方もいるかもしれませんが、念のため)

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="asia-northeast1"
export REPO_NAME="migration-workshop-repo"

# Docker イメージ用のリポジトリ作成
gcloud artifacts repositories create ${REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Docker repository for App Modernization workshop"

# リポジトリが作成されたことを確認
gcloud artifacts repositories list --location=${REGION}
```

### 3.2. Docker の認証設定

gcloud CLI を使用して、Artifact Registry に Docker がプッシュできるように認証ヘルパーを設定します。

```bash
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```

### 3.3. イメージのタグ付けとプッシュ

```bash
# イメージの FQDN (Fully Qualified Domain Name) パスを構築
export IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/app-modern-go:v1.0.0"

# ローカルのイメージにタグ付け
docker tag app-modern-go:local ${IMAGE_URI}

# Artifact Registry へプッシュ！
docker push ${IMAGE_URI}

# プッシュされたことを確認
gcloud artifacts docker images list ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/app-modern-go
```

**トラブルシューティング:**
もし `denied: Permission "artifactregistry.repositories.uploadArtifacts" denied` のようなエラーが出た場合、現在 `gcloud auth login` しているアカウントが対象プロジェクトの `roles/artifactregistry.writer` (または owner) の権限を持っているか、1-onboarding の前提条件ファイル等を参照して確認してください。

---

## 次のアクション

作成したコンテナイメージ (`IMAGE_URI` が指すイメージ) を使って、実際に Google Cloud 上へデプロイを行います。
要件に応じて、コンテナベースのフルマネージドサーバーレスである **Cloud Run** か、より複雑なオーケストレーションが可能な **GKE Autopilot** かを選択して進みます。

👉 次のステップ: [04. Cloud Run へのデプロイ](./04_cloud_run_deployment.md) または [05. GKE Autopilot へのデプロイ](./05_gke_autopilot_deployment.md) （順次進めてください）
