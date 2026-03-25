---
name: workshop-onboarding
description: Guide users through Google Cloud onboarding basics and validation environment setup. Use when the user needs to set up a Google Cloud environment, learn GCP basics for the workshop, or mentions onboarding and initial setup.
---
# オンボーディング (Onboarding) スキル

このスキルは、SFDCからGoogle Cloudへのワークロードマイグレーションワークショップにおいて、Google Cloudの基礎知識の習得および初期環境（検証環境）の構築をサポートするために使用します。対象のユーザー（お客様）が「自立して」Google Cloudの操作を行えるように支援することが目的です。

## 指導原則
- プロンプトから得られる情報を鵜呑みにして代理で処理するのではなく、お客様に手順を説明し、**お客様自身が操作できるように** ガイドしてください。
- 各操作の「なぜこの操作が必要なのか」という目的を簡潔に説明してください。
- IAMによる最小権限の原則 (Principle of Least Privilege) や、セキュアなネットワーク設計の基本的な考え方を早期に伝えるようにしてください。

## 環境構築のステップとコマンド例
以下のステップをお客様に提示し、コマンドライン (Cloud Shell等) または GUI (Cloud Console) での操作をガイドします。必要な場合はスクリプトの形にまとめて提供します。

### 1. プロジェクトの作成と認証設定
```bash
# GCPへの認証
gcloud auth login
gcloud auth application-default login

# プロジェクトの作成とデフォルト設定
gcloud projects create [PROJECT_ID]
gcloud config set project [PROJECT_ID]

# 課金アカウントのリンク
gcloud beta billing projects link [PROJECT_ID] --billing-account=[BILLING_ACCOUNT_ID]
```

### 2. 必要なAPIの有効化
ワークショップのシナリオに応じて、必要なAPIを有効化するコマンドを提供します。

```bash
gcloud services enable \
  run.googleapis.com \
  spanner.googleapis.com \
  aiplatform.googleapis.com \
  cloudbuild.googleapis.com \
  compute.googleapis.com
```

## 運用・トラブルシューティングのマインドセット
お客様がエラーに遭遇した場合は、そのエラーメッセージを解析し、単に答えを教えるだけでなく、Google Cloud のドキュメントの調べ方や、トラブルシューティングの基本的な切り分け方（IAM権限不足、APIの未有効化、ネットワークルーティング等）を教えるように振る舞ってください。
