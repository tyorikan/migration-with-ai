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
| テスト (Backend) | pytest + pytest-asyncio + httpx |
| 静的解析 (Backend) | ruff, mypy, bandit |
| ログ | structlog（構造化ログ） |
| 設定 | pydantic-settings（環境変数） |
| Frontend | Next.js 15 (App Router) + TypeScript 5 + shadcn/ui + Tailwind CSS + TanStack Query + React Hook Form + Zod |
| テスト (Frontend) | Vitest + React Testing Library + msw（unit）/ Playwright（E2E） |
| 静的解析 (Frontend) | Biome（lint+format）+ tsc --noEmit |
| コンテナ | docker-compose（db + app + nextjs） |

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
├── docker-compose.yml                 ← 統合環境（db + app + nextjs）
├── 00-preparation/                    ← 事前準備
├── 01-reverse-engineering/output/     ← システム概要書、ER図、API仕様
├── 02-schema-migration/output/        ← DDL、データ変換スクリプト、SQL
├── 03-code-modernization/output/      ← Python (FastAPI) Backend プロジェクト + テスト
├── 04-frontend-nextjs/                ← Next.js フロントエンド（設計 + 実装）
│   └── output/
│       ├── design/                    ← /design-frontend 成果物（中粒度 markdown）
│       ├── app/                       ← Next.js App Router 実装
│       ├── components/                ← shadcn/ui + ドメインコンポーネント
│       ├── lib/                       ← BFF クライアント、Zod、auth
│       └── tests/                     ← Vitest + Playwright
├── 05-quality-and-delivery/output/    ← 品質評価結果
├── 06-roadmap/output/                 ← ADR、ロードマップ
├── examples/                          ← サンプル SFDX プロジェクト（検証用）
└── data/                              ← SFDC エクスポート CSV
```

## Step 間のインプット/アウトプット連携

| From → To | 連携ファイル |
|-----------|------------|
| Step 1 → Step 2 | `01-reverse-engineering/output/system_overview.md`（ER図・フィールド定義） |
| Step 2 → Step 3 | `02-schema-migration/output/generated_ddl.sql`（テーブル定義） |
| Step 1 → Step 3 | `01-reverse-engineering/output/system_overview.md`（API仕様） |
| Step 1 → Step 5 | `01-reverse-engineering/output/migration_assessment.md`（影響分析） |
| Step 1 → Step 4-A | `01-reverse-engineering/output/system_overview.md` + `wiki/`（業務要件 → 画面要件） |
| Step 3 → Step 4-A | `03-code-modernization/output/app/router/` + `model/schemas.py`（API 仕様 → BFF Route Handler 設計 + Zod スキーマ） |
| Step 4-A → Step 4-B | `04-frontend-nextjs/output/design/`（中粒度設計書 = 実装の唯一の真実） |
| Step 3 → Step 4-B | Backend は **HTTP 経由で呼ぶ**（Step 4 から改変禁止）。`docker compose --profile nextjs up -d` で `app:8080` がコンテナ内部 NW から参照される |
| Step 4 → Step 5 | `04-frontend-nextjs/output/`（Next.js プロジェクト = フロント単体でデプロイ可能） + Backend 疎通確認 |

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

# Step 3: db + Backend（app, port 8080）
docker compose --profile step3 up -d --build

# Step 4: db + Backend（app）+ Next.js フロント（nextjs, port 3000）
#   nextjs は BFF Route Handler 経由で app:8080 を呼ぶ（CORS 不要）
docker compose --profile nextjs up -d --build

# クリーンアップ
docker compose --profile nextjs --profile step3 down -v
```

環境変数:
- `DB_HOST=db` `DB_PORT=5432` `DB_USER=app_user` `DB_PASSWORD=password` `DB_NAME=migration_db`（Backend）
- `BACKEND_URL=http://app:8080/api/v1`（Next.js BFF が叩く Backend のベース URL — Step 3 FastAPI は `/api/v1/store-visits` を公開）

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
| `nextjs-frontend` | Next.js (App Router) + shadcn/ui + Tailwind + TanStack Query + Zod の実装パターン集。BFF Route Handler、ロール制御、Vitest/Playwright のひな形 | Step 4-A 設計 + Step 4-B 実装 |
| `quality-rubric` | 成果物のスコアリング評価基準（1-5 の数値評価、合格基準）。Step 4 は 4-A（設計）/ 4-B（実装）の 2 セクション | `/review-gate` 実行時 |

## Agents（特化型エージェント）

各 Step で使用する特化型エージェントが `.claude/agents/` に定義されている。

| エージェント | 役割 | 使用 Step |
|------------|------|----------|
| `sfdc-analyzer` | SFDX プロジェクト分析 → 設計書自動生成 | Step 1 |
| `schema-converter` | DDL 生成 + データ移行スクリプト生成 | Step 2 |
| `python-modernizer` | TDD で Apex → Python/FastAPI 変換 | Step 3 |
| `nextjs-frontend-designer` | Step 3 Backend と業務要件から Next.js 中粒度設計書を生成（実装はしない） | Step 4-A |
| `nextjs-frontend-implementer` | 設計書を唯一の真実として Next.js を TDD で実装（Vitest + Playwright） | Step 4-B |
| `migration-reviewer` | 品質レビュー + スコアリング + Step 間整合性検証 | `/review-gate` + 各 Step 完了時 |

---

## 品質保証: 独立コンテキストレビュー

> **Anthropic ハーネス設計パターン準拠**: builder と evaluator を独立したコンテキストで実行し、self-leniency（自己評価の甘さ）を排除する。

各 Step 完了後に **`/clear` → `/review-gate N`** を実行することで、builder の思考履歴を一切持たない状態で品質レビューを実施できる。

```
# ① builder として Step を実行
/reverse-engineer ./examples

# ② コンテキストをリセット
/clear

# ③ 独立コンテキストで品質チェック
/review-gate 1

# ④ PASS したら次の Step へ
/clear
/schema-convert ./examples
```

Step 4 は **二段構成** (`4-A` 設計 → `4-B` 実装) のため `/review-gate` も二回:

```
# Step 4-A: 設計フェーズ
/clear
/design-frontend                # nextjs-frontend-designer agent
/clear
/review-gate 4-A                # 設計レビュー → DESIGN_REPORT.md

# Step 4-B: 実装フェーズ（4-A PASS 後）
/clear
/implement-frontend             # nextjs-frontend-implementer agent
/clear
/review-gate 4-B                # 実装レビュー → review_report.md
```

## 状態管理: workshop-state.json

`workshop-state.json` はワークショップの進捗・メトリクス・レビュースコアをマシンリーダブルに管理する。
新しいセッション開始時にこのファイルを読み込み、前回の作業状態を正確に復元できる。

構造は `workshop-state.schema.json`（JSON Schema Draft-07）で定義されている。スコアは必ず `.steps.stepN.review.score` 配下に格納する（直下ではない）点に注意。

```bash
# 状態更新（各 Step 完了時に実行）
./scripts/update-state.sh .steps.step1.status completed
./scripts/update-state.sh .steps.step1.metrics.objects_found 8
./scripts/update-state.sh .steps.step1.review.score 4.2
./scripts/update-state.sh .steps.step1.review.gate_passed true

# スキーマ検証（型崩れ・必須キー欠落・enum 違反の早期検知）
./scripts/validate-state.sh

# 整合性チェック（Step 間のデータ一致を機械的に検証）
./scripts/verify-consistency.sh

# 進捗チェック（成果物の存在確認 + DB 状態確認 + スキーマ検証）
./scripts/check-progress.sh
```

## ハーネス進化ポリシー

### 現在のターゲットモデル
- **Primary**: Claude Opus 4.7 (via Vertex AI)
- **最終検証日**: 2026-04-28

### モデル更新時のチェックリスト
新しいモデルがリリースされたら、以下を順に検証し、不要になった足場は取り除くこと:

1. [ ] Step 1 の3段パイプライン → Code Wiki なしの1段実行でも品質が維持されるか？
2. [ ] Plan-First ルール → モデルが自発的に計画を立てるようになったか？
3. [ ] 独立コンテキストレビュー → セルフレビューでも self-leniency が発生しないか？
4. [ ] コンテキスト分割 → 全 Step を1セッションで実行しても品質が維持されるか？

品質が維持される場合、そのハーネスコンポーネントを除去してシンプル化する。

