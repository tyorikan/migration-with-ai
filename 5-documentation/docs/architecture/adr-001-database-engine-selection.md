# ADR 001: データベースエンジンの選定 (Cloud SQL for PostgreSQL)

*   **Status:** Accepted
*   **Deciders:** アプリケーションモダナイゼーション・チーム
*   **Date:** 2025-03-01
*   **Tags:** `Cloud SQL`, `PostgreSQL`, `AlloyDB`, `Spanner`, `Database`

## コンテキストと問題の背景

Salesforce (SFDC) 上で稼働しているアプリケーションを Google Cloud に移行するにあたり、データの永続化層として使用するデータベースエンジンを選定する必要がある。

SFDC のデータモデルはリレーショナルな構造（オブジェクト間の参照関係・主従関係）を持つため、移行先も RDB が適切と判断している。Google Cloud が提供するマネージド RDB サービスとして、以下の3つの選択肢を検討した。

**前提条件:**
- 移行データ量: 数十 GB 〜 数百 GB 規模
- 同時接続数: 最大でも数百コネクション程度
- 可用性要件: 99.95% 以上
- 運用チーム: RDB の運用経験あり（PostgreSQL / MySQL）
- 予算: スタートアップフェーズのため、コスト効率を重視

## 決定事項 (Decision)

**Cloud SQL for PostgreSQL** を SFDC 移行先のデータベースエンジンとして採用する。

## 考慮した選択肢 (Considered Options)

1.  **Cloud SQL for PostgreSQL:** Google マネージドの PostgreSQL サービス。HA 構成、自動バックアップ、PITR に対応。
2.  **AlloyDB for PostgreSQL:** PostgreSQL 互換の Google 独自エンジン。高いトランザクション性能と分析クエリの同時実行が可能。
3.  **Cloud Spanner:** Google 独自のグローバル分散 RDB。無制限のスケーラビリティと 99.999% の可用性。

## 決定の理由 (Rationale)

| 評価軸 | Cloud SQL | AlloyDB | Spanner |
| :--- | :---: | :---: | :---: |
| **PostgreSQL 互換性** | ✅ ネイティブ | ✅ 互換 | ⚠️ GoogleSQL / PG互換(制限あり) |
| **エコシステム（ORM, ツール）** | ✅ フル互換 | ✅ フル互換 | ⚠️ 一部非対応 |
| **コスト（この規模）** | ✅ 最安 | ⚠️ 中程度 | ❌ 最も高い |
| **学習コスト** | ✅ 低い | ✅ 低い | ⚠️ 独自概念あり |
| **HA / 可用性** | ✅ 99.95% | ✅ 99.99% | ✅ 99.999% |
| **スケーラビリティ** | ⚠️ 垂直スケール中心 | ✅ 読み取りスケール | ✅ 水平スケール |
| **運用経験の活用** | ✅ | ✅ | ⚠️ |

*   **コスト効率:** 現時点のデータ量・トラフィックでは Cloud SQL で十分であり、AlloyDB / Spanner のプレミアムコストは正当化できない。
*   **PostgreSQL ネイティブ:** ORM（GORM 等）、マイグレーションツール（golang-migrate 等）、監視ツールとのフル互換により、移行リスクを最小化できる。
*   **運用経験:** チームの既存の PostgreSQL 運用ノウハウをそのまま活用できる。
*   **段階的移行:** まず Cloud SQL で移行を完了し、将来的にトラフィックが増大した場合に AlloyDB へのアップグレードパスが用意されている（PostgreSQL 互換のため移行コストが低い）。

## 想定される結果 (Consequences)

### ポジティブな結果 (Positive)
*   移行初期費用を抑えつつ、マネージドサービスの恩恵（自動バックアップ、HA、セキュリティパッチ）を享受できる。
*   既存の PostgreSQL ツールチェーン・ノウハウをそのまま活用でき、チームの生産性を維持できる。
*   Terraform でのプロビジョニングが成熟しており、IaC 化が容易。

### ネガティブな結果 (Negative)
*   水平スケーリングが必要になった場合、AlloyDB や Spanner への再移行が必要。ただし PostgreSQL 互換の AlloyDB への移行は比較的容易。
*   Spanner が提供するグローバル分散やマルチリージョン書き込みは利用できない。現時点ではその要件はない。

## 関連資料 (References)

*   [Cloud SQL for PostgreSQL ドキュメント](https://cloud.google.com/sql/docs/postgres)
*   [AlloyDB vs Cloud SQL 比較](https://cloud.google.com/alloydb/docs/overview)
*   [02_schema_design.md - スキーマ設計ガイド](../../2-database-migration/02_schema_design.md)
*   [01_terraform_foundation.md - Terraform 基盤構築](../../4-infra-pipeline/01_terraform_foundation.md)
