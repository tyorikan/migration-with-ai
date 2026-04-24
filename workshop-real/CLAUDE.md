# SFDC モダナイゼーション ワークショップ — プロジェクトルール

## プロジェクトコンテキスト

このプロジェクトは、Salesforce (SFDC) 上のアプリケーションを Google Cloud (Python/FastAPI/PostgreSQL) に
AI 駆動でモダナイズするための **1日集中型オンサイトワークショップ** の教材・ツールセットです。

「設計書がないから移行できない」のではなく、「ソースコードこそが唯一の真実」。
AI にソースコードから設計を逆起こしさせ、TDD でデグレを防ぎながら移行します。

## ⚠️ 必須: Plan-First ルール

**いかなるコマンド・タスクでも、コードや成果物の生成に入る前に、必ず実行計画（何をどの順序で行うか）を提示し、ユーザーの承認を得てから実装に進むこと。**

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

---

## Skills（ドメインナレッジ）

コード生成・変換時は `.claude/skills/` 配下のスキルを参照すること。
スキルには SFDC 固有の変換ルール、パターン、チェックリストが定義されている。

| スキル | 用途 | 参照タイミング |
|-------|------|-------------|
| `sfdc-to-python` | Apex → Python 変換パターン（ガバナ制限、Trigger、共有モデル、Batch、Formula） | Step 3: コードモダナイズ時 |
| `sfdc-schema-migration` | SFDC → PostgreSQL DDL 変換ルール（命名規則、型マッピング、データ移行） | Step 2: スキーマ変換時 |
| `reverse-engineering` | SFDC ソースコードからの設計書逆起こしルール | Step 1: 逆起こし時 |
| `tdd-modernize` | Apex テスト → pytest 変換 + TDD ワークフロー | Step 3: テスト駆動開発時 |

## Agents（特化型エージェント）

各 Step で使用する特化型エージェントが `.claude/agents/` に定義されている。

| エージェント | 役割 | 使用 Step |
|------------|------|----------|
| `sfdc-analyzer` | SFDX プロジェクト分析 → 設計書自動生成 | Step 1 |
| `schema-converter` | DDL 生成 + データ移行スクリプト生成 | Step 2 |
| `python-modernizer` | TDD で Apex → Python/FastAPI 変換 | Step 3 |
| `migration-reviewer` | 品質レビュー + Step 間整合性検証 | Step 4-5 + 各 Step 完了時 |

