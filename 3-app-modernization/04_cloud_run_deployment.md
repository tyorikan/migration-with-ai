# 04. Cloud Run へのデプロイ

## 目的
前のステップで Artifact Registry にプッシュしたコンテナイメージを、フルマネージドなサーバーレス環境である **Cloud Run** にデプロイします。
単なるデプロイにとどまらず、実運用（プライベートIPを用いたデータベース接続や、安全なシークレット管理）を想定したエンタープライズ向けのベストプラクティス構成を学びます.

## Cloud Run の選定基準の復習
- インフラ管理を極力ゼロにしたい (NoOps).
- ゼロスケール機能によるコスト最適化を行いたい.
- HTTP Request または Event Arc トリガーによるステートレスな処理である.
- 顧客とのやり取りや非同期のバッチジョブ（Cloud Run Jobs）を含んでいる。

---

## 1. Cloud Run の基本デプロイ

まずは最小限の設定で、パブリックにアクセス可能な状態としてデプロイしてみます。

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="asia-northeast1"
export REPO_NAME="migration-workshop-repo"

# 03 で push したイメージを指定
export IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/app-modern-go:v1.0.0"

# Cloud Run サービス名
export SERVICE_NAME="app-modern-go"

gcloud run deploy ${SERVICE_NAME} \
    --image=${IMAGE_URI} \
    --region=${REGION} \
    --allow-unauthenticated \
    --port=8080 \
    --set-env-vars=DB_CONNECTION_STRING="dummy-for-test" \
    --max-instances=5
```

> **Note:** `--allow-unauthenticated` を設定すると IAM 認証なしで（インターネットから）アクセス可能になります。本番の社内用APIなどの場合は、デフォルトの **未認証アクセスを不許可** にして、IAM を経由させるのがベストプラクティスです。

デプロイ完了後、ターミナルに表示される `Service URL` (例: `https://app-modern-go-xxxxxxxxx-an.a.run.app`) にアクセスして動作を確認してください。

## 2. エンタープライズ向け (本番想定) の設定

実際の SFDC からの移行案件では、セキュアなデータベース(Cloud SQL / AlloyDB など)との接続や、秘匿情報を扱う層が必須になります。

### 2.1. Secret Manager の統合

DB のパスワード、APIキー、各種トークンなどを、平文の環境変数 ( `--set-env-vars` ) に持たせることはセキュリティ上推奨されません。Google Cloud では **Secret Manager** とのシームレスな統合を利用します。

**(1) シークレットの作成**
```bash
# DB接続文字列をシークレットとして保存
echo "postgres://dbuser:supersecret!@10.0.0.5:5432/migration_db" | gcloud secrets create app-db-conn-string \
    --data-file=- \
    --replication-policy="automatic"
```

**(2) Cloud Run サービスアカウントへの権限付与**
```bash
# デフォルトコンピュートサービスアカウントを取得 (またはカスタムSAを指定)
export RUN_SA=$(gcloud iam service-accounts list --filter="name:compute@developer.gserviceaccount.com" --format="value(email)")

# シークレットへのアクセス権限を付与
gcloud secrets add-iam-policy-binding app-db-conn-string \
    --member="serviceAccount:${RUN_SA}" \
    --role="roles/secretmanager.secretAccessor"
```

**(3) Cloud Run にシークレットを環境変数としてマウントして再デプロイ**
```bash
gcloud run deploy ${SERVICE_NAME} \
    --image=${IMAGE_URI} \
    --region=${REGION} \
    --update-secrets=DB_CONNECTION_STRING=app-db-conn-string:latest
```
これにより、アプリケーション内からは通常の環境変数 `DB_CONNECTION_STRING` として振る舞いますが、中身は Secret Manager からの安全な参照になります。

### 2.2. VPC へのプライベート接続 (Serverless VPC Access / Direct VPC Egress)

プライベート IP しか持たない Cloud SQL や AlloyDB に Cloud Run からアクセスするためには、VPC へのルーティング設定が必要です。現在は **Direct VPC Egress** が推奨されています。

**(1) (準備) DB 接続用の VPC ネットワークとサブネットがあることを確認**
```bash
# --network="default" などを指定
export NETWORK="default"
```

**(2) VPC アウトバウンド トラフィックを構成**
```bash
gcloud run deploy ${SERVICE_NAME} \
    --image=${IMAGE_URI} \
    --region=${REGION} \
    --network=${NETWORK} \
    --vpc-egress=private-ranges-only
```
- `--vpc-egress=private-ranges-only`: RFC1918 プライベート IP 宛の通信のみを VPC に流します。インターネット宛の通信（外部 API など）は VPC を経由せず、そのまま Cloud Run の IP プールから外部へ出ます。

## 3. 継続的デリバリー (CI/CD) への布石

手動の `gcloud run deploy` コマンドで動作が確認できたら、以降はこのステップを **Cloud Build** や **GitHub Actions** に組み込みます。（これは [4-infra-pipeline](../4-infra-pipeline) のセクションと連携します。）

### 自動化の概略
1. 開発者がリポジトリに `git push` する。
2. Cloud Build / GitHub Actions が発火。
3. `docker build` と `docker push` を実行し、Artifact Registry にイメージを保管。
4. `gcloud run deploy` が、保管した最新のイメージタグを参照して実行される (ゼロダウンタイムデプロイ)。

## 4. トラブルシューティングと可観測性

### 4.1. ログの確認 (Cloud Logging)
デプロイが失敗する、またはリクエストが 500 エラーを返す場合は以下のコマンドですぐにログを確認します。
```bash
gcloud beta run services logs tail ${SERVICE_NAME} --project ${PROJECT_ID}
```

### 4.2. メトリクスの利用 (Cloud Monitoring)
Google Cloud コンソール上の Cloud Run メトリックのタブから以下を確認できます。
- **リクエスト数 (Request count)**
- **レイテンシ (Latency)**
- **コンテナ インスタンス数**

これにより、急激なスパイクやゼロスケールからのコールドスタート時間などを視覚的に分析できます。

---

👉 仮想マシンや、ステートフルな要件、または既存の Kubernetes パイプラインをそのまま持ち込みたい場合は、これの代替案として [05. GKE Autopilot へのデプロイ](./05_gke_autopilot_deployment.md) の経路についてもご確認ください。
