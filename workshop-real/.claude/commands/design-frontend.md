Step 4-A: Next.js フロントエンド設計フェーズ — 中粒度 markdown 設計書の生成

> **重要**: このコマンドは Next.js プロジェクトの **設計** だけを行います。実装（`*.tsx`, `package.json`, etc.）は **生成しません**。実装は次の `/implement-frontend` で行います。

## あなたの役割

`nextjs-frontend-designer` agent として、Step 1 の業務要件と Step 3 の Backend API を分析し、`04-frontend-nextjs/output/design/` 配下に **中粒度の Next.js フロントエンド設計書** を生成してください。

## 入力（自動参照）

### Step 1 の成果物（業務要件）
- 統合設計書: `01-reverse-engineering/output/system_overview.md`（エンティティ、業務ルール、ステータス遷移、ロール）
- Code Wiki: `01-reverse-engineering/output/wiki/`（クラス・トリガーの詳細、メール通知）

### Step 3 の成果物（Backend API）
- FastAPI Router: `03-code-modernization/output/app/router/`
- Pydantic Schema: `03-code-modernization/output/app/model/schemas.py`
- UseCase（ビジネスルール）: `03-code-modernization/output/app/usecase/`
- Exceptions: `03-code-modernization/output/app/exceptions.py`

## 必須参照スキル（Plan 提示前に必ず Skill ツールで開くこと）

- `nextjs-frontend` — Next.js App Router、shadcn/ui、TanStack Query、BFF Route Handler、Zod 同期、Vitest/Playwright のひな形
- `quality-rubric` — Step 4-A 設計レビューの評価軸

## 生成する成果物

```
04-frontend-nextjs/output/design/
├── overview.md              # 全体方針・技術スタック・画面遷移図 (Mermaid stateDiagram)
├── design-system.md         # 色・タイポ・余白トークン、shadcn/ui 一覧、ステータスバッジの色対応
├── api-client.md            # BFF Route Handler ↔ Backend エンドポイント対応表、エラーマッピング
├── data-model.md            # Zod スキーマ案、camelCase ↔ snake_case 境界、型生成方針
└── screens/                 # P0 画面 7 枚（必須）
    ├── dashboard.md
    ├── visit-list.md
    ├── visit-detail.md
    ├── visit-create.md
    ├── visit-edit.md
    ├── visit-status-transition.md
    └── visit-delete-confirm.md
```

各 `screens/*.md` は以下のセクションを **この順序で固定** 記述:
`## 目的・ロール` → `## ワイヤー (ASCII or Mermaid)` → `## 状態` → `## バリデーション` → `## API 呼び出し` → `## コンポーネントツリー (疑似 JSX)` → `## アクセシビリティ` → `## エラー時 UX`

## 厳守ルール

- **コード生成は禁止**。`*.tsx` `*.ts` `package.json` 等は作らない（実装は次のコマンドで行う）
- **業務ルールを UI で明文化**: Approved 編集不可、Draft 削除のみ、Submitted → Approved/Rejected はマネージャーロールのみ、重複防止 をいずれかの screens/*.md で UI 制御として書き出す
- **API 整合**: api-client.md で BFF Route Handler ↔ Backend エンドポイントを 1:1 対応の表で示す
- **Zod スキーマと Backend Pydantic の同期**: data-model.md で フィールド名・型・必須・enum を Backend と一致させる（camelCase ベース）
- **Mermaid 構文の検証**: 図がレンダリングできることを確認

## 完了条件

- design/ 配下に 11 ファイル（overview / design-system / api-client / data-model + screens 7 枚）が揃う
- 全 .md がレンダリング可能（Mermaid 構文 OK、表崩れなし）
- 状態更新:
  ```bash
  ./scripts/update-state.sh .steps.step4.phases.design.status completed
  ./scripts/update-state.sh .steps.step4.metrics.design_screens 7
  ./scripts/update-state.sh .steps.step4.metrics.bff_route_handlers <カウント>
  ./scripts/update-state.sh .steps.step4.metrics.pages_count 7
  ./scripts/update-state.sh .steps.step4.status in_progress
  ```

## 次のステップ

設計書を出したら:
1. `/clear` でコンテキストをリセット
2. `/review-gate 4-A` で独立レビュー
3. レビュー PASS（`steps.step4.phases.design.review.gate_passed === true`）後に `/implement-frontend` で実装フェーズへ
