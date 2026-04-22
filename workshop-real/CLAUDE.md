# SFDC モダナイゼーション ワークショップ — プロジェクトルール

## プロジェクトコンテキスト

このプロジェクトは、Salesforce (SFDC) 上のアプリケーションを Google Cloud (Python/FastAPI/PostgreSQL) に
AI 駆動でモダナイズするための **1日集中型オンサイトワークショップ** の教材・ツールセットです。

「設計書がないから移行できない」のではなく、「ソースコードこそが唯一の真実」。
AI にソースコードから設計を逆起こしさせ、TDD でデグレを防ぎながら移行します。

## テクノロジースタック

| カテゴリ | 技術 |
|---------|------|
| Backend | Python 3.12 + FastAPI |
| DB | PostgreSQL 16（docker-compose で管理） |
| ORM | SQLAlchemy 2.x + asyncpg |
| テスト | pytest + pytest-asyncio + httpx |
| 静的解析 | ruff, mypy, bandit |
| ログ | structlog（構造化ログ） |
| 設定 | pydantic-settings（環境変数） |
| コンテナ | docker-compose（db + app） |

## アーキテクチャ（3層レイヤー分離）

```
router/      → HTTP リクエスト/レスポンスの処理（FastAPI Router）
usecase/     → ビジネスロジック（純粋な Python、フレームワーク依存なし）
repository/  → データアクセス層（SQLAlchemy + asyncpg）
```

- **DI**: usecase は repository の ABC に依存（具象に依存しない）。FastAPI の `Depends()` で注入。
- **エラー**: 構造化エラーレスポンス `{"error": "message", "code": "ERROR_CODE"}`
- **トランザクション**: 親子レコードの操作は SQLAlchemy Session でアトミックに

## 出力ルール

- 各 Step の成果物は対応する `XX-xxx/output/` に出力する
- **日本語**で記述する
- **Mermaid 図**を積極的に使用する（flowchart, erDiagram, stateDiagram-v2, gantt）
- コード生成時は **TDD を遵守**する（テスト → 実装の順序）
- DDL 生成時は **外部キーの依存関係を考慮した順序**で出力する

## ディレクトリ構成

```
workshop-real/
├── CLAUDE.md                          ← 本ファイル
├── docker-compose.yml                 ← 統合環境
├── 00-preparation/                    ← 事前準備
├── 01-reverse-engineering/output/     ← システム概要書、ER図、API仕様
├── 02-schema-migration/output/        ← DDL、データ変換スクリプト、SQL
├── 03-code-modernization/output/      ← Python プロジェクト + テスト
├── 04-quality-and-delivery/output/    ← 品質評価結果
├── 05-roadmap/output/                 ← ADR、ロードマップ
├── examples/                          ← サンプル SFDX プロジェクト（検証用）
├── data/                              ← SFDC エクスポート CSV
└── templates/                         ← AI プロンプトテンプレート
```

## Step 間のインプット/アウトプット連携

| From → To | 連携ファイル |
|-----------|------------|
| Step 1 → Step 2 | `01-reverse-engineering/output/system_overview.md`（ER図・フィールド定義） |
| Step 2 → Step 3 | `02-schema-migration/output/generated_ddl.sql`（テーブル定義） |
| Step 1 → Step 3 | `01-reverse-engineering/output/system_overview.md`（API仕様） |
| Step 1 → Step 5 | `01-reverse-engineering/output/migration_assessment.md`（影響分析） |
| Step 3 → Step 4 | `03-code-modernization/output/tests/`（テストコード） |

## SFDC → PostgreSQL 変換ルール

### 命名規則
- テーブル名: `__c` 除去 → snake_case → 複数形（例: `StoreVisit__c` → `store_visits`）
- カラム名: `__c` 除去 → snake_case（例: `StoreCode__c` → `store_code`）

### データ型マッピング
| SFDC 型 | PostgreSQL 型 |
|---------|--------------|
| Id | `VARCHAR(18) PRIMARY KEY` |
| Text | `VARCHAR(length)` |
| LongTextArea | `TEXT` |
| Checkbox | `BOOLEAN DEFAULT false` |
| Number | `INTEGER` or `NUMERIC(p, s)` |
| Date | `DATE` |
| DateTime | `TIMESTAMPTZ` |
| Picklist | `VARCHAR(255)` + CHECK 制約 |
| Lookup | `FOREIGN KEY ... ON DELETE SET NULL` |
| MasterDetail | `FOREIGN KEY ... ON DELETE CASCADE NOT NULL` |

## Docker 環境

```bash
# DB のみ起動（Step 2）
docker compose up -d db

# アプリ + DB（Step 3-4）
docker compose up -d --build

# クリーンアップ
docker compose down -v
```

環境変数: `DB_HOST=db`, `DB_PORT=5432`, `DB_USER=app_user`, `DB_PASSWORD=password`, `DB_NAME=migration_db`
