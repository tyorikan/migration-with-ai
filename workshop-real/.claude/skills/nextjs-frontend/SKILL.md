---
name: nextjs-frontend
description: Next.js (App Router) + shadcn/ui + Tailwind CSS + TanStack Query + React Hook Form + Zod による業務管理画面の実装パターン集。Step 3 FastAPI Backend を BFF (Route Handler) 経由で呼ぶ構成。Step 4-A 設計と Step 4-B 実装の両方で参照する。
---

# Next.js Frontend パターン集

> Step 4-A 設計フェーズ・Step 4-B 実装フェーズで参照する **当ワークショップ固有** のドメインナレッジ。
> Next.js 自体の一般知識（公式ドキュメントで足りる内容）は重複を避け、**選定理由・統合パターン・落とし穴** に絞る。

## 1. 技術スタック（採用根拠）

| 層 | ツール | 採用根拠 |
|----|--------|---------|
| Framework | Next.js 15 (App Router) | RSC で初期表示の TTFB が良い、BFF (Route Handler) を同一プロジェクトに置けて CORS 不要、Server Action で簡潔な Mutation |
| 言語 | TypeScript 5 (strict) | Backend Pydantic と Zod を介して型を共有、ロード時間で破壊的変更を検知 |
| パッケージ管理 | pnpm | symlink で `node_modules` 軽量、monorepo 化しやすい |
| UI | shadcn/ui (Radix ベース) + Tailwind CSS | コピペ式で依存薄、デザインを完全コントロール、Workshop の learning curve が低い |
| データフェッチ | TanStack Query v5 | キャッシュ・リフェッチ・楽観更新が宣言的、Mutation がエラーハンドリング含めて簡潔 |
| Form | React Hook Form + Zod | uncontrolled で再レンダ最小、Zod で client/server 共有スキーマ |
| Lint/Format | Biome | Step 3 の ruff と思想が近く高速、ESLint 設定地獄を避ける |
| テスト (unit) | Vitest + React Testing Library + msw | Vite ベースで高速、Step 3 の pytest と TDD 体験を揃える |
| テスト (e2e) | Playwright | dev server を `webServer` で起動、CI/ローカル両対応 |

## 2. ディレクトリ構造（厳守）

```
04-frontend-nextjs/output/
├── app/
│   ├── layout.tsx                     # フォント・theme・QueryClientProvider・Toaster
│   ├── page.tsx                       # ダッシュボード
│   ├── visits/
│   │   ├── page.tsx                   # 一覧
│   │   ├── new/page.tsx               # 新規作成
│   │   └── [id]/
│   │       ├── page.tsx               # 詳細
│   │       └── edit/page.tsx          # 編集
│   └── api/                           # BFF Route Handler
│       └── visits/
│           ├── route.ts               # GET / POST
│           └── [id]/
│               ├── route.ts           # GET / PATCH / DELETE
│               └── transition/route.ts
├── components/
│   ├── ui/                            # shadcn generated（手動 add）
│   ├── visits/                        # ドメイン
│   └── layout/                        # AppShell, RoleSwitcher
├── lib/
│   ├── backend.ts                     # server-only HTTP client
│   ├── auth.ts                        # Cookie からロール抽出
│   ├── schemas.ts                     # Zod スキーマ
│   └── query-client.ts                # TanStack Query 設定
└── tests/
    ├── unit/                          # Vitest
    └── e2e/                           # Playwright
```

## 3. shadcn/ui のセットアップ手順（実装フェーズ）

```bash
cd 04-frontend-nextjs/output

# 1. Tailwind 等セットアップ後
npx shadcn@latest init -y -d --base-color slate

# 2. Workshop で使う最小セット（過不足なし）
npx shadcn@latest add -y \
  button input table dialog badge select textarea label \
  card sonner dropdown-menu form

# 注: --yes / --force 系 flag を使い CI でも安定して再生成できるようにする
```

## 4. BFF Route Handler のひな形

```ts
// app/api/visits/route.ts
import { NextRequest, NextResponse } from "next/server";
import { backend } from "@/lib/backend";
import { listVisitsQuerySchema, visitCreateSchema } from "@/lib/schemas";

export const dynamic = "force-dynamic"; // セッション/Cookie に依存させる

export async function GET(req: NextRequest) {
  const params = Object.fromEntries(req.nextUrl.searchParams);
  const parsed = listVisitsQuerySchema.safeParse(params);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "リクエスト形式が不正です", code: "VALIDATION_ERROR", details: parsed.error.issues },
      { status: 400 }
    );
  }
  const res = await backend.get("/store-visits", { searchParams: parsed.data });
  return NextResponse.json(await res.json(), { status: res.status });
}

export async function POST(req: NextRequest) {
  const body = await req.json();
  const parsed = visitCreateSchema.safeParse(body);
  if (!parsed.success) { /* ...同上 */ }
  const res = await backend.post("/store-visits", { json: parsed.data });
  return NextResponse.json(await res.json(), { status: res.status });
}
```

## 4-X. 設計時の Backend OpenAPI 照合（**Step 4-A の必須手順**）

> **過去の事故**: Step 4-A 設計書 / `BACKEND_URL` を `/api/v1` 前提で書いたが、Step 3 Backend は prefix なしで実装されており、Step 4-B 実装段階で初めて発覚。BFF を `/api/v1` 抜きに調整する応急処置で先に進んでしまい、Step 3 の瑕疵を覆い隠した。

設計フェーズ (`/design-frontend` agent / Step 4-A) では、**Backend が起動可能なら必ず OpenAPI を取得して path 整合を確認** すること:

```bash
# 1. Backend を起動
docker compose --profile step3 up -d app && sleep 5

# 2. OpenAPI から実 path を取得
curl -fsS http://localhost:8080/openapi.json | jq -r '.paths | keys[]' | sort
# 期待出力例: ["/api/v1/store-visits", "/api/v1/store-visits/{visit_id}", "/healthz"]

# 3. 設計に書く BACKEND_URL を、この実態に合わせて決定する
#    例: /api/v1/store-visits が公開されている → BACKEND_URL=http://app:8080/api/v1
#    例: /store-visits が公開されている → BACKEND_URL=http://app:8080
```

**Backend が動かない / 起動できない場合**は、`03-code-modernization/output/app/main.py` の `include_router(prefix=…)` と `app/router/*.py` の `APIRouter(prefix=…)` を直読みして `/openapi.json` 相当を **静的解析** で求める。

設計書 (`design/api-client.md` `design/overview.md`) に `BACKEND_URL` を書く際は、この実 path 起点で逆算した値を採用 (希望や仕様書だけで決めない)。設計と Backend が乖離している場合は **設計を Backend に寄せる前に Step 3 を直すべき** か、`/clear` してユーザーに判断を仰ぐ。

## 5. server-only Backend クライアント

```ts
// lib/backend.ts
import "server-only";  // ← client から import すると build 時エラー

const BACKEND_URL = process.env.BACKEND_URL ?? "http://app:8080/api/v1";

type Init = RequestInit & { searchParams?: Record<string, string | undefined>; json?: unknown };

async function request(path: string, init: Init = {}) {
  const url = new URL(BACKEND_URL + path);
  for (const [k, v] of Object.entries(init.searchParams ?? {})) {
    if (v !== undefined && v !== "") url.searchParams.set(k, String(v));
  }
  const headers = new Headers(init.headers);
  if (init.json !== undefined) headers.set("content-type", "application/json");
  return fetch(url, {
    ...init,
    headers,
    body: init.json !== undefined ? JSON.stringify(init.json) : init.body,
    cache: "no-store",
  });
}

export const backend = {
  get:    (p: string, i?: Init) => request(p, { ...i, method: "GET" }),
  post:   (p: string, i?: Init) => request(p, { ...i, method: "POST" }),
  patch:  (p: string, i?: Init) => request(p, { ...i, method: "PATCH" }),
  delete: (p: string, i?: Init) => request(p, { ...i, method: "DELETE" }),
};
```

## 6. ロール制御（Workshop 用簡易認証）

```ts
// lib/auth.ts
import { cookies } from "next/headers";

export type Role = "sales" | "manager";

export async function currentRole(): Promise<Role> {
  const c = await cookies();          // ← Next.js 15 で async
  const v = c.get("role")?.value;
  return v === "manager" ? "manager" : "sales";
}

export async function requireManager() {
  if ((await currentRole()) !== "manager") {
    throw new Response(
      JSON.stringify({ error: "マネージャー権限が必要です", code: "FORBIDDEN" }),
      { status: 403, headers: { "content-type": "application/json" } }
    );
  }
}
```

UI 側の RoleSwitcher は `document.cookie = "role=manager; path=/"` で切り替えれば良い。Workshop 範囲では JWT 等は不要。

## 7. Zod ↔ Pydantic 同期戦略

Backend Pydantic は **camelCase alias** を受けるので Frontend は **camelCase で統一**。

```ts
// lib/schemas.ts
import { z } from "zod";

export const visitStatus = z.enum(["Draft", "Submitted", "Approved", "Rejected"]);
export type VisitStatus = z.infer<typeof visitStatus>;

export const visitDetail = z.object({
  category: z.string().min(1),
  description: z.string().nullable().optional(),
  priority: z.number().int().min(1).max(5).default(3),
  dueDate: z.string().date().nullable().optional(),  // ← camelCase
});

export const visitCreateSchema = z.object({
  storeId: z.string().min(1),
  visitDate: z.string().date(),
  purpose: z.string().min(1),
  summary: z.string().nullable().optional(),
  nextAction: z.string().nullable().optional(),
  rating: z.number().int().min(1).max(5).nullable().optional(),
  details: z.array(visitDetail).default([]),
});

export const visitResponseSchema = z.object({
  id: z.string(),
  name: z.string(),
  storeId: z.string(),
  visitorId: z.string(),
  visitDate: z.string(),
  status: visitStatus,
  purpose: z.string(),
  summary: z.string().nullable(),
  nextAction: z.string().nullable(),
  rating: z.number().nullable(),
  visitDetails: z.array(visitDetail).default([]),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VisitResponse = z.infer<typeof visitResponseSchema>;

export const listVisitsQuerySchema = z.object({
  status: visitStatus.optional(),
  storeId: z.string().optional(),
  fromDate: z.string().date().optional(),
  toDate: z.string().date().optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});
```

> **重要**: Backend のレスポンスは **snake_case** で返ってくる場合があるので、BFF 層で `keysToCamel()` を一度通すか、Backend レスポンスを `z.preprocess` で変換する。Pydantic が `populate_by_name=True` + `by_alias=True` でレスポンスを返しているなら camelCase で来るはず — 実装フェーズで実際のレスポンスを 1 度確認すること。

## 8. TanStack Query パターン

```tsx
// components/visits/visit-list-table.tsx
"use client";
import { useQuery } from "@tanstack/react-query";

export function VisitListTable({ status }: { status?: string }) {
  const q = useQuery({
    queryKey: ["visits", { status }],
    queryFn: async () => {
      const r = await fetch(`/api/visits?status=${status ?? ""}`);
      if (!r.ok) throw new Error(await r.text());
      return r.json();
    },
  });
  if (q.isLoading) return <div>読み込み中…</div>;
  if (q.isError)   return <div>エラー: {(q.error as Error).message}</div>;
  if (!q.data?.data?.length) return <div>該当する訪問記録はありません</div>;
  return <table>{/* ... */}</table>;
}
```

## 9. Vitest + msw のひな形

```ts
// tests/unit/api-visits.test.ts
import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";
import { GET } from "@/app/api/visits/route";
import { NextRequest } from "next/server";

const server = setupServer(
  http.get("http://app:8080/api/v1/store-visits", () =>
    HttpResponse.json({ data: [{ id: "v1" }], count: 1, limit: 50, offset: 0 })
  )
);

beforeAll(() => server.listen());
afterAll(() => server.close());

test("GET /api/visits proxies backend", async () => {
  const req = new NextRequest(new URL("http://localhost/api/visits"));
  const res = await GET(req);
  expect(res.status).toBe(200);
  expect((await res.json()).data[0].id).toBe("v1");
});
```

## 10. Playwright 設定

```ts
// playwright.config.ts
import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests/e2e",
  use: { baseURL: "http://localhost:3000" },
  webServer: {
    command: "pnpm build && pnpm start",   // CI 安定
    port: 3000,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
```

## 11. Dockerfile（multi-stage の要点）

- `node:20-alpine` ベース
- deps stage: `pnpm install --frozen-lockfile` だけ
- build stage: `pnpm build` で `.next/standalone` 出力
- runner stage: standalone を COPY、`USER 1001` non-root、`CMD ["node", "server.js"]`、`EXPOSE 3000`
- `next.config.ts` に `output: "standalone"` を必ず設定

## 12. 落とし穴（よくあるハマり）

| 症状 | 原因と対処 |
|------|-----------|
| BFF から `fetch failed` | コンテナ内で `BACKEND_URL=http://localhost:8080/...` のままで Docker network から見えない。`http://app:8080/api/v1` にする |
| BFF から **404 `{"detail":"Not Found"}`** | `BACKEND_URL` の prefix と Backend 実 path が不一致。**`curl /openapi.json` で実 path を確認** し、BFF の URL を実態に合わせる。Step 4-A の §4-X 参照 |
| Hydration mismatch | RSC で `Date.now()` `Math.random()` を直書き。フォーマット系はクライアント側に寄せる |
| Cookie が読めない | Next.js 15 で `cookies()` は async。`const c = await cookies()` |
| shadcn の color が反映されない | `tailwind.config.ts` の `content` に `"./components/**"` `"./app/**"` を含めていない |
| Playwright が起動しない | `playwright install --with-deps` を Dockerfile / CI で実行していない |
| Server Action で 500 | Server Action 内で `lib/backend.ts` を呼ぶ際、Next 15 では `await cookies()` を最初に呼ばないと headers が取れない |
| `pnpm build` で「Module not found '@/...'` | `tsconfig.json` の `paths` に `"@/*": ["./*"]` がない |

## 13. 業務ルールの UI 制御チートシート

| ルール | UI 表現 |
|------|--------|
| Approved は編集不可 | `{visit.status !== "Approved" && <EditButton />}` |
| Draft のみ削除可 | `{visit.status === "Draft" && <DeleteButton />}` |
| Submitted → Approved/Rejected はマネージャーのみ | `{visit.status === "Submitted" && role === "manager" && <ApproveButtons />}` |
| Rejected → Draft（再編集）| 編集ボタンクリック時に PATCH `{status: "Draft"}` を含める |
| 重複防止 | フォーム送信時に Backend `400 BUSINESS_ERROR` を catch して toast で「同一日・店舗の記録が既に存在」 |
| メール通知の事前告知 | 承認ダイアログに「承認すると訪問者にメール通知されます」を表示 |
