Step 5: ADR（技術選定の意思決定記録）の自動生成

## 入力（自動参照）
- 全 Step の成果物:
  - `workshop-real/01-reverse-engineering/output/`（設計書、影響分析）
  - `workshop-real/02-schema-migration/output/`（DDL、データ移行）
  - `workshop-real/03-code-modernization/output/`（Python プロジェクト、テスト）
  - `workshop-real/04-quality-and-delivery/output/`（品質評価）

## 指示
本日のワークショップで決定した（または検討すべき）アーキテクチャ方針について、ADR を生成してください。

## ADR フォーマット（各 ADR ごと）
```
## ADR-XXX: [タイトル]
- **ステータス**: 承認済 / 検討中
- **日付**: YYYY-MM-DD
- **コンテキスト**: なぜこの決定が必要だったか
- **決定**: 何を決定したか
- **代替案**: 検討した他の選択肢
- **理由**: なぜその選択肢を採用したか
- **結果**: この決定による影響・トレードオフ
```

## 生成すべき ADR
1. ADR-001: Backend 言語選定（Python / FastAPI） — 代替: Go, TypeScript
2. ADR-002: DB エンジン選定（Cloud SQL PostgreSQL） — 代替: AlloyDB, Spanner
3. ADR-003: コンテナ基盤選定（Cloud Run） — 代替: GKE Autopilot
4. ADR-004: AI 駆動開発の品質保証方針 — TDD + 多層品質ゲート
5. ADR-005: データ移行方式 — sf CLI / Data Loader / Bulk API

## 追加で生成
- アーキテクチャ全体図（Mermaid `graph TD`）— SFDC 構成 vs Google Cloud 構成を対比
- SFDC → Google Cloud サービスマッピング図（Mermaid `graph LR`）

## 出力先
`workshop-real/05-roadmap/output/adr.md`
