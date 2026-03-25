# 4. インフラ環境とデプロイメントパイプライン (Infra & Pipeline)

本セクションでは、モダナイズされたアプリケーションを Google Cloud 上に展開するための、**Infrastructure as Code (IaC)** を用いた基盤構築と、**CI/CD パイプライン**の設計・構築手法について学習します。

## 目的 (Objectives)

- **Terraform による IaC の実践:** Google Cloud リソースをコードで管理するメリットとベストプラクティスを理解する。
- **CI/CD の設計:** Cloud Build などを活用した、セキュアで自動化されたデプロイメントパイプラインを設計する。
- **Gemini を活用した IaC:** Terraform コードやマニフェストファイルの生成、修正、トラブルシューティングに AI をどのように組み込むかを体験する。

## ドキュメント一覧

1. **[Terraform 基盤構築 (01_terraform_foundation.md)](./01_terraform_foundation.md)**
   - GCP における Terraform のディレクトリ構成、状態管理 (tfstate) のベストプラクティス。
   - ネットワーク (VPC)、IAM、データベース (Cloud SQL/AlloyDB)、コンピュート (Cloud Run/GKE) のコード化アプローチ。

2. **[CI/CD アーキテクチャ設計 (02_ci_cd_architecture.md)](./02_ci_cd_architecture.md)**
   - 変更要求から本番デプロイまでのエンドツーエンドのワークフロー設計。
   - セキュリティシフトレフト (脆弱性スキャン)、承認プロセスの組み込み。

3. **[Gemini を活用した IaC 開発 (03_gemini_assisted_iac.md)](./03_gemini_assisted_iac.md)**
   - HCL (HashiCorp Configuration Language) の生成、既存コードのモジュール化、エラー解決における Gemini の活用方法と効果的なプロンプト。

## サンプルコード (sample)

`sample/` ディレクトリには、本セクションで解説する概念を具体化したサンプルが含まれています。

- `sample/terraform/`: アプリケーション基盤を構築するための Terraform コード片。
- `sample/cloudbuild/`: Cloud Build を用いた CI/CD パイプライン定義の例。
