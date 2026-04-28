# Step 4: Next.js フロントエンド — 設計 (4-A) → 実装 (4-B)

> [!IMPORTANT]
> **「Backend の API を curl で叩く」だけで終わらせない。**
> Step 3 で構築した FastAPI の REST API を、Next.js (App Router) + shadcn/ui で「ブラウザで動く管理画面」として組み上げる。
> 設計フェーズを **明示的に切る** ことで Plan-First を強化し、実装事故を設計レビューで予防する。

## 🎯 ゴール

| フェーズ | 成果物 | コマンド |
|---------|-------|---------|
| **Step 4-A 設計** | 中粒度 markdown 設計書 11 ファイル（overview / design-system / api-client / data-model + screens × 7）| `/design-frontend` |
| **Step 4-A レビュー** | `DESIGN_REPORT.md`（独立コンテキストの設計レビュー） | `/clear` → `/review-gate 4-A` |
| **Step 4-B 実装** | Next.js プロジェクト一式（app/ + components/ + lib/ + tests/ + Dockerfile）| `/implement-frontend` |
| **Step 4-B レビュー** | `review_report.md`（独立コンテキストの実装レビュー） | `/clear` → `/review-gate 4-B` |

> [!NOTE]
> **`04-frontend-nextjs/output/` が最終成果物ディレクトリ**。Next.js (port 3000) は Step 3 Backend (port 8080) を BFF Route Handler 経由で呼ぶ。Step 3 の Python コードは **改変しない**。

---

## 全体フロー

```
┌─────────────────────────────────────────────────────────────┐
│ Browser (port 3000)                                         │
│   App Router (RSC + Client) + shadcn/ui + Tailwind          │
│   TanStack Query + React Hook Form + Zod                    │
└────────┬────────────────────────────────────────────────────┘
         │ /api/visits, /api/visits/[id], etc. (same-origin)
┌────────▼────────────────────────────────────────────────────┐
│ Next.js Route Handlers (BFF, port 3000)                     │
│   - lib/auth.ts でロール抽出 (Cookie)                        │
│   - lib/schemas.ts (Zod) で入力検証                          │
│   - lib/backend.ts で Backend を叩く (server-only)           │
└────────┬────────────────────────────────────────────────────┘
         │ HTTP (docker-compose 内部 NW)
┌────────▼────────────────────────────────────────────────────┐
│ Step 3 FastAPI Backend (app:8080) — 改変禁止                │
│   /api/v1/store-visits CRUD                                 │
└────────┬────────────────────────────────────────────────────┘
         │
┌────────▼────────────────────────────────────────────────────┐
│ PostgreSQL (db:5432)                                        │
└─────────────────────────────────────────────────────────────┘
```

## ⚙️ 技術スタック

| 層 | ツール | 役割 |
|----|--------|------|
| Framework | Next.js 15 (App Router) | RSC + BFF Route Handler |
| 言語 | TypeScript 5 (strict) | Zod で Backend と型共有 |
| パッケージ管理 | pnpm | 軽量 |
| UI | shadcn/ui (Radix) + Tailwind CSS | デザインを完全コントロール |
| データフェッチ | TanStack Query v5 | キャッシュ + Mutation |
| Form | React Hook Form + Zod | 型安全な検証 |
| Lint/Format | Biome | 高速、Step 3 の ruff と思想が近い |
| テスト (unit) | Vitest + RTL + msw | Step 3 の pytest と TDD 体験を揃える |
| テスト (e2e) | Playwright | dev server 起動込み |

詳細は `.claude/skills/nextjs-frontend/SKILL.md` を参照。

## 📋 認証・ロール制御

ワークショップ用の **簡易ロールスイッチ** のみ:
- ヘッダ右上の `RoleSwitcher` で `sales` / `manager` を切替 → Cookie `role` に保存
- BFF Route Handler の入口で `cookies().get('role')` を読み、`requireManager()` で「Submitted → Approved」操作などを制御
- Backend には現状ロールの概念がないため Backend 改変なし
- 本格的な OAuth (Auth.js + Google) は ADR `06-roadmap` に「将来課題」として記載

## 🛠️ 起動・テスト

```bash
# 1. ハーネス改修済みの状態で Backend + Next.js を起動
docker compose --profile nextjs up -d --build

# 2. 動作確認
curl -fsS http://localhost:8080/healthz                   # Backend
curl -fsS http://localhost:3000/api/visits                # BFF Route Handler
open http://localhost:3000                                # ブラウザで管理画面

# 3. ローカル開発（ホットリロード）
cd 04-frontend-nextjs/output
pnpm install
pnpm dev                                                  # http://localhost:3000

# 4. テスト
pnpm typecheck                                            # tsc --noEmit
pnpm lint                                                 # Biome
pnpm test                                                 # Vitest
pnpm e2e                                                  # Playwright

# 5. クリーンアップ
docker compose --profile nextjs down -v
```

## 🚦 P0 画面一覧（必須実装）

| # | 画面 | パス | 主なロール | 主な操作 |
|---|------|------|-----------|---------|
| 1 | ダッシュボード | `/` | 全員 | 直近の Submitted 件数、クイックアクション |
| 2 | 訪問記録一覧 | `/visits` | 全員 | 検索 / 絞り込み / ページング |
| 3 | 訪問記録詳細 | `/visits/[id]` | 全員 | フィールド閲覧、ステータス遷移ボタン |
| 4 | 新規作成 | `/visits/new` | 営業担当 | フォーム送信 → Draft で保存 |
| 5 | 編集 | `/visits/[id]/edit` | 営業担当 (Draft/Rejected のみ) | フィールド編集 |
| 6 | ステータス遷移 | 詳細画面のダイアログ | Draft/Submitted/Rejected の主体ロール | 提出 / 承認 / 差し戻し / 再編集 |
| 7 | 削除確認 | 詳細画面のダイアログ | 営業担当 (Draft のみ) | 確認後削除 |

## 📐 業務ルールの UI 制御（厳守）

- **Approved**: 編集ボタン・削除ボタン非表示、ステータス遷移ダイアログにも選択肢なし、バッジは緑
- **Draft**: 編集 / 削除可、提出ボタン表示
- **Submitted**: 編集不可（または「内容変更には差し戻しが必要」と注記）、マネージャーのみ承認 / 差し戻しボタン
- **Rejected**: 編集 → 自動的に Draft へ戻る挙動を案内
- 重複防止: フォーム送信時に Backend の `400 BUSINESS_ERROR` を catch して toast で通知
- ページネーション: `limit/offset` ベース（総件数は API が返さないため「{count}件 表示中」）

## 🔍 品質ゲート

`/review-gate 4-A` および `/review-gate 4-B` で migration-reviewer agent が独立コンテキストでレビュー。詳細は `.claude/skills/quality-rubric/SKILL.md` の Step 4-A / Step 4-B セクション。

合格基準（両ゲート共通）:
- 全評価軸で 3/5 以上
- 平均スコア 3.5/5 以上
- CRITICAL 発見事項 0 件

## 📂 出力ディレクトリ構造

```
04-frontend-nextjs/output/
├── design/                              # /design-frontend 成果物
│   ├── overview.md
│   ├── design-system.md
│   ├── api-client.md
│   ├── data-model.md
│   └── screens/                         # P0 画面 7 枚
│       ├── dashboard.md
│       ├── visit-list.md
│       ├── visit-detail.md
│       ├── visit-create.md
│       ├── visit-edit.md
│       ├── visit-status-transition.md
│       └── visit-delete-confirm.md
├── app/                                 # Next.js App Router
│   ├── layout.tsx
│   ├── page.tsx
│   ├── visits/{page,new/page,[id]/page,[id]/edit/page}.tsx
│   └── api/visits/{route,[id]/route,[id]/transition/route}.ts
├── components/{ui,visits,layout}/
├── lib/{backend,auth,schemas,query-client}.ts
├── tests/{unit,e2e}/
├── package.json, tsconfig.json, next.config.ts, tailwind.config.ts
├── vitest.config.ts, playwright.config.ts, biome.json
├── components.json                      # shadcn/ui 設定
├── Dockerfile                           # multi-stage (deps → build → runner)
├── .env.local.example                   # BACKEND_URL=http://app:8080/api/v1
├── DESIGN_REPORT.md                     # /review-gate 4-A 成果物
└── review_report.md                     # /review-gate 4-B 成果物
```

## 🗂️ 関連ファイル

- 設計コマンド: `.claude/commands/design-frontend.md`
- 実装コマンド: `.claude/commands/implement-frontend.md`
- 設計エージェント: `.claude/agents/nextjs-frontend-designer.md`
- 実装エージェント: `.claude/agents/nextjs-frontend-implementer.md`
- スキル: `.claude/skills/nextjs-frontend/SKILL.md`
- 評価軸: `.claude/skills/quality-rubric/SKILL.md`（Step 4-A / 4-B セクション）
