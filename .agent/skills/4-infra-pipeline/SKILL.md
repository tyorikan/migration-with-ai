---
name: workshop-infra-pipeline
description: Orchestrate infrastructure as code (IaC) using Terraform and set up automated CI/CD deployment pipelines. Use when the user needs to create Google Cloud infrastructure with Terraform, establish CI/CD, or automate deployments.
---
# インフラ＆パイプライン (Infra & Pipeline) スキル

このスキルは、Terraform を用いた Infrastructure as Code (IaC) による Google Cloud リソースの宣言的な管理と、Cloud Build や GitHub Actions を用いた継続的インテグレーション/継続的デプロイメント (CI/CD) パイプラインの構築をサポートします。

## ベストプラクティス
1. **ステート管理 (State Management)**
   - Terraformのステートファイルはローカルに置かず、必ず Cloud Storage (GCS) バケットに保存する設定 (Remote Backend) を原則とします。
2. **モジュール分割**
   - ネットワーク、データベース、コンピュート (Cloud Run等) といったリソース群ごとに `.tf` ファイルを論理的に分割し、再利用性と可読性を高めることを推進します。
3. **継続的インテグレーション (CI/CD)**
   - コードのマージ後、自動的にインフラがデプロイされ、アプリケーションのコンテナイメージが Artifact Registry にプッシュされ、Cloud Run に反映されるフローを構築します。

## 実装例: Terraform のベース設定

### 1. `backend.tf`
ステートをGCSで管理するための基本設定です。
```hcl
terraform {
  backend "gcs" {
    bucket  = "my-project-tfstate-bucket"
    prefix  = "terraform/state/workshop"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
```

### 2. リソース定義例 (`main.tf` - Cloud Run)
```hcl
provider "google" {
  project = var.project_id
  region  = "asia-northeast1"
}

resource "google_cloud_run_v2_service" "default" {
  name     = "modernized-app"
  location = "asia-northeast1"

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello" # 最初はHelloイメージで構築
      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }
    }
  }
}

# パブリックアクセス許可
resource "google_cloud_run_service_iam_member" "public" {
  location = google_cloud_run_v2_service.default.location
  project  = google_cloud_run_v2_service.default.project
  service  = google_cloud_run_v2_service.default.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

## 実装例: CI/CD パイプライン構成 (Cloud Build)
アプリケーションのテスト・ビルド・デプロイを自動化する `cloudbuild.yaml` のひな形です。

```yaml
steps:
  # 1. ユニットテストの実行 (例: Go)
  - name: 'golang:1.26'
    entrypoint: 'go'
    args: ['test', './...']

  # 2. コンテナイメージのビルド
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/my-repo/modern-app:$COMMIT_SHA', '.']

  # 3. Artifact Registry へのプッシュ
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/my-repo/modern-app:$COMMIT_SHA']

  # 4. Cloud Run へのデプロイ
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'gcloud'
    args:
      - 'run'
      - 'deploy'
      - 'modern-app'
      - '--image'
      - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/my-repo/modern-app:$COMMIT_SHA'
      - '--region'
      - 'asia-northeast1'

images:
  - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/my-repo/modern-app:$COMMIT_SHA'
```

作業を通して、お客様に「インフラがコードで管理される安心感」と「自動化のメリット」をハンズオンで伝えてください。
