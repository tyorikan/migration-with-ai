# migration-with-ai

## 目次と各セクションの概要

本ワークショップは以下の6つのセクションで構成されており、各ディレクトリに必要な手順とサンプルアセットが含まれています。

### 📌 ワークショップ（実践）

- **[workshop-real](./workshop-real/README.md)** 🆕
   * お客様の実 SFDC コードを使い、Claude Code（via Vertex AI）で設計逆起こし → TDD コード変換 → docker-compose 検証まで1日で行う実践ワークショップ。

### 📌 ハンズオン（サンプルアプリ）

- **[hands-on](./hands-on/README.md)**
   * サンプルアプリ（業務日報システム）を使い、AI ネイティブ移行の全 Step を体験するハンズオン。

### 📚 リファレンスドキュメント

1. **[1-onboarding](./1-onboarding/README.md)**
   * Google Cloud プロジェクトのセットアップ、課金設定、必要な API の有効化など、環境構築の基礎を学びます。
2. **[2-database-migration](./2-database-migration/README.md)**
   * SFDC のデータ構造 (Account/Contact など) を Google Cloud SQL/AlloyDB (PostgreSQL) へ移行するための、Schema 変換とデータエクスポート戦略を検証します。
3. **[3-app-modernization](./3-app-modernization/README.md)**
   * 既存のコード (Apex等) を生成 AI を使用して Go や Node.js 等のモダンな言語に変換し、Cloud Run 等のサーバレス環境へデプロイする方法を学びます。
4. **[4-infra-pipeline](./4-infra-pipeline/README.md)**
   * Terraform を使用した IaC でインフラを構築し、Cloud Build で CI/CD パイプラインを自動化する手順を実践します。
5. **[5-documentation](./5-documentation/README.md)**
   * Gemini を活用してソースコードやインフラ構成から Architecture Decision Record (ADR) や OpenAPI 仕様書などのドキュメントを自動生成し、メンテナンスする手法を学びます。
6. **[6-testing](./6-testing/README.md)**
   * AI を使用したテストコードの自動生成と、CI 組み込みによる自動テスト実行で、マイグレーション後の品質を担保するフローを体験します。