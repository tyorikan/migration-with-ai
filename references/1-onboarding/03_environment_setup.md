# 検証用環境の構築手順 (Environment Setup)

ワークショップで利用する Google Cloud のベース環境（プロジェクトの設定、API の有効化、ネットワーク基盤など）を構築する手順です。
※本手順はコンソールおよび `gcloud` CLIを利用したマニュアル構築を想定しています。本格的な運用では Terraform (IaC) での構築を推奨します（[インフラ＆パイプライン](../4-infra-pipeline)フェーズにて後述）。

## 1. プロジェクトの設定と確認

### プロジェクトIDのエクスポート
以降のコマンド操作を簡略化するため、環境変数へプロジェクトIDをセットします。

```bash
# ご自身のプロジェクトIDに置き換えてください
export PROJECT_ID="your-workshop-project-id"

# gcloud のデフォルトプロジェクトを設定
gcloud config set project $PROJECT_ID
```

## 2. 必要な API の有効化

ワークショップの過程で各種マネージドサービスを利用できるように、Google Cloud の API を有効化します。

```bash
gcloud services enable \
  compute.googleapis.com \
  run.googleapis.com \
  sqladmin.googleapis.com \
  aiplatform.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  cloudaicompanion.googleapis.com
```

- `compute.googleapis.com` : Compute Engine およびネットワーク基盤用
- `run.googleapis.com` : Cloud Run 用
- `sqladmin.googleapis.com` : Cloud SQL (PostgreSQL) 用
- `aiplatform.googleapis.com` : Vertex AI (Gemini 生成API) 用
- `cloudbuild.googleapis.com` / `artifactregistry.googleapis.com` : コンテナビルドと保存用
- `cloudaicompanion.googleapis.com` : Gemini for Google Cloud (コンソール上の Gemini) 用

## 3. ネットワーク基盤の確認・作成

データベース (Cloud SQL/AlloyDB) とアプリケーション (Cloud Run) をセキュアに接続するため、VPC (Virtual Private Cloud) ネットワークの準備が必要です。

新規プロジェクトの場合、`default` ネットワークが自動作成されていますが、セキュリティ観点から本番環境ではカスタムVPCを作成します。ワークショップの手始めとして、VPC およびサブネットを作成してみましょう。

```bash
# 例: ワークショップ用 カスタム VPC の作成
gcloud compute networks create workshop-vpc \
  --subnet-mode=custom \
  --bgp-routing-mode=regional

# 例: 東京リージョン (asia-northeast1) にサブネットを作成
gcloud compute networks subnets create workshop-subnet \
  --network=workshop-vpc \
  --region=asia-northeast1 \
  --range=10.0.0.0/24
```

*(DB接続のためのプライベートサービスアクセス(VPC Peering)の構築手順などは、データベース移行フェーズ、または Terraform で一括構築する手順にてフォローします)*

## 4. 実行ロールの確認
ワークショップ進行中、各種サービス作成時に権限エラーが発生した場合は、ご自身のアカウントに適切な「IAM ロール」が付与されているか、Google Cloud コンソールの **[IAM と管理] > [IAM]** 画面から確認してください。
