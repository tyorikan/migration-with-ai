Step 4-B: Next.js フロントエンド実装フェーズ — 設計 markdown を唯一の真実とした TDD 実装

> **前提**: `/design-frontend` と `/review-gate 4-A` が完了していること（`steps.step4.phases.design.review.gate_passed === true`）。
> 未完了の場合は実装に入らず、ユーザーに設計フェーズの完了を依頼してください。

## あなたの役割

`nextjs-frontend-implementer` agent として、Step 4-A で生成された `04-frontend-nextjs/output/design/` 配下の markdown を **唯一の真実** とし、Next.js (App Router) フロントエンドを **TDD** で実装してください。

## 入力（自動参照）

### Step 4-A の成果物（設計書 — これを唯一の真実とする）
- `04-frontend-nextjs/output/design/overview.md`
- `04-frontend-nextjs/output/design/design-system.md`
- `04-frontend-nextjs/output/design/api-client.md`
- `04-frontend-nextjs/output/design/data-model.md`
- `04-frontend-nextjs/output/design/screens/*.md`（P0 画面 7 枚）

### Step 3 の成果物（参照のみ・改変禁止）
- FastAPI Router: `03-code-modernization/output/app/router/`
- Pydantic Schema: `03-code-modernization/output/app/model/schemas.py`

## 必須参照スキル（Plan 提示前に必ず Skill ツールで開くこと）

- `nextjs-frontend` — App Router、shadcn/ui 追加手順、TanStack Query、BFF Route Handler、Zod 同期、Vitest/Playwright のひな形
- `tdd-modernize` — テストファースト原則
- `quality-rubric` — Step 4-B 実装レビューの評価軸

## アーキテクチャ

```
Browser (port 3000)
  ↓ /api/*
Next.js Route Handler (BFF, port 3000)
  - lib/auth.ts でロール抽出
  - lib/schemas.ts (Zod) で検証
  - lib/backend.ts で Backend を叩く
  ↓ HTTP (docker compose 内部 NW)
Step 3 FastAPI Backend (port 8080) — 改変禁止
  ↓
PostgreSQL (port 5432)
```

## TDD 実装サイクル（Step 3 と同じ）

各 Phase で **テストファースト**（Vitest RED → 実装 GREEN → リファクタ）:

1. **Phase 0**: プロジェクト初期化（package.json / tsconfig / next.config / tailwind / vitest / playwright / biome / shadcn/ui add）
2. **Phase 1**: `lib/schemas.ts` — Zod ラウンドトリップ test → 実装
3. **Phase 2**: BFF Route Handler — msw で Backend モックした test → 実装
4. **Phase 3**: ドメインコンポーネント — Vitest + RTL の test → 実装
5. **Phase 4**: ページ実装（App Router） — design/screens/*.md のコンポーネントツリー通りに
6. **Phase 5**: Playwright E2E — P0 4 シナリオ（list / create / status-transition / delete）
7. **Phase 6**: Dockerfile + 本番ビルド検証
8. **Phase 7**: README 上書き

## 厳守ルール

- **設計と実装の一致**: design/screens/X.md のコンポーネントツリー名と実装ファイル (`app/visits/.../page.tsx`) が対応する
- **Backend 改変禁止**: `03-code-modernization/output/` を編集しない
- **業務ルールの UI 制御**: Approved 編集不可、Draft 削除のみ、マネージャーのみ承認 を grep で確認できるレベルで実装
- **camelCase の徹底**: Frontend は外向き camelCase
- **server-only**: `lib/backend.ts` は client から import 不可（`server-only` パッケージ使用）

## 検証（PASS まで実装を続ける）

```bash
cd 04-frontend-nextjs/output

# 1. 型チェック
pnpm typecheck     # tsc --noEmit エラー 0

# 2. lint
pnpm lint          # biome (or eslint) エラー 0

# 3. ユニットテスト + カバレッジ
pnpm test          # Vitest 全 PASS、Route Handler / schemas で 70%+

# 4. Docker ビルド + 起動
docker compose --profile nextjs up -d --build
curl -fsS http://localhost:3000/                  # 200
curl -fsS http://localhost:3000/api/visits        # JSON 配列
curl -fsS http://localhost:8080/healthz           # Backend ok

# 5. E2E
pnpm e2e           # Playwright P0 4 シナリオ PASS
```

**全 5 項目が PASS** するまで「完了」とみなさない。

## 完了条件

- 上記 5 検証すべて PASS
- 状態更新:
  ```bash
  ./scripts/update-state.sh .steps.step4.phases.implement.status completed
  ./scripts/update-state.sh .steps.step4.metrics.vitest_tests <数>
  ./scripts/update-state.sh .steps.step4.metrics.playwright_e2e_scenarios <数>
  ./scripts/update-state.sh .steps.step4.metrics.typecheck_errors 0
  ./scripts/update-state.sh .steps.step4.metrics.lint_errors 0
  ./scripts/update-state.sh .steps.step4.metrics.components_count <数>
  ./scripts/update-state.sh .steps.step4.status completed
  ```

## 次のステップ

実装が完了したら:
1. `/clear` でコンテキストをリセット
2. `/review-gate 4-B` で独立レビュー
3. レビュー PASS 後に Step 5 / Step 6 へ進む
