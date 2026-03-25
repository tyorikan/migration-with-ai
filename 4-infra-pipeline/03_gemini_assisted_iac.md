# Gemini を活用した Infrastructure as Code 開発支援

アプリケーションコードと同様に、Terraform (HCL) や Kubernetes マニフェスト (YAML)、CI/CD パイプライン定義の作成・修正においても、Gemini や Gemini Code Assist は強力な支援ツールとなります。

## 1. 新規インフラ・リソース構成の初期案作成（ゼロからの生成）

Google Cloud の公式モジュール構成やベストプラクティスを最初から調べる手間を大きく削減できます。

### プロンプト例: Cloud Run 構成の骨組み作成

> **ユーザ:**
> 以下の要件で Cloud Run サービスをデプロイする Terraform のコードを書いてください。
> - エンドポイントは内部のみ (ingress = internal) に制限する
> - Cloud SQL (PostgreSQL) に接続するため、VPC コネクタを利用する
> - プロビジョニングには `google-beta` プロバイダではなく、最新の仕様を使用する

> **Gemini 活用ポイント:**
> 出力された HCL に加えて、Gemini は IAM 設定 (Cloud Run サービスアカウントに必要な Cloud SQL クライアントロールなど) も併せて提案してくれることが多いです。不足している場合は「このサービスを動かすために必要な IAM ロールとその割り当てコードも追加して」と要求します。

## 2. 既存リソースから Terraform モデルの逆算・移行

環境構築時に検証用に Console から手動で作成したリソースを、後から Terraform 化したい場合に役立ちます。

### プロンプト例: 手動構築リソースの IaC 化支援

> **ユーザ:**
> GCP コンソールから "migration-import-bucket" という名前の Cloud Storage バケットを作成しました。設定内容は以下の通りです。
> - リージョン: asia-northeast1
> - ストレージクラス: Standard
> - Oject Lifecycle: 30日後にアーカイヴクラスに移行
> これを管理するための Terraform リソース定義を出力してください。

## 3. エラー・トラブルシューティング

Terraform の実行時エラー (`terraform plan` や `apply`) は、依存関係や GCP の仕様（特定の API の有効化漏れ、IAM不備など）に起因することが多々あります。

### プロンプト例: エラーログの解析

> **ユーザ:**
> `terraform apply` を実行したところ、以下のエラーが表示されました。原因と修正方法を教えてください。
> ```
> Error: Error creating Service: googleapi: Error 403: Permission 'iam.serviceAccounts.actAs' denied on service account...
> ```

> **Gemini 活用ポイント:**
> Gemini はこのエラーが「デプロイを実行するユーザ（またはサービスアカウント）に対して、対象のサービスアカウントを借用（アサイン）する権限が不足している」ことを理解し、どのリソースに対し誰に `roles/iam.serviceAccountUser` を付与すべきかを具体的に解説してくれます。

## 4. CI/CD パイプライン構築の支援

Cloud Build の `cloudbuild.yaml` などをゼロから作成する際も強力です。パイプライン特有の構文、引数の渡し方、ステップ間の成果物の引き継ぎを任せることができます。

### プロンプト例: Cloud Build 手順の作成

> **ユーザ:**
> Google Cloud Build 用の `cloudbuild.yaml` を作成してください。ステップは以下の通りです。
> 1. Go アプリケーションの単体テスト (`go test`) を実行する
> 2. `asia-northeast1-docker.pkg.dev/$PROJECT_ID/repo/app` に対して Docker イメージをビルド・プッシュする
> 3. プッシュしたイメージを使って `my-cloud-run-service` という Cloud Run サービスを asia-northeast1 リージョンにデプロイする

## 実践での注意点（ハルシネーション対策）

- **モジュール起点のコードか、リソース起点のコードか:** Gemini がサードパーティコミュニティの Terraform Module を出力している場合、それに依存したくない時は「コミュニティのモジュール機能は使わず、単一の `google_xxxx` リソースとネイティブなブロックで記述してください」と指定します。
- **最新 API バージョンの確認:** 稀に古い API 仕様のブロックや引数 (`template` 内の細かい属性変更など) を提案することがあります。`terraform validate` コマンドで構成ファイル検証を行うサイクルを必ずセットで回すようにします。
