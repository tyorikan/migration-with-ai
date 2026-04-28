---
name: a2ui-frontend
description: A2UI プロトコル (v0.9 推奨、v0.8 互換) のコンポーネント変換パターン、ADK + FastAPI 統合パターン、Lit Renderer セットアップ手順を定義するドメインナレッジスキル。
---

A2UI を使ったフロントエンド自動生成のドメインナレッジ。

## When to Activate
- Step 3 の FastAPI Backend に A2UI フロントエンドを追加するとき
- ADK Agent で A2UI JSON を生成するとき
- Lit Renderer をセットアップするとき

## 1. A2UI プロトコル概要

A2UI (Agent-to-UI) は Google が公開する OSS プロトコル。
AI Agent が宣言的 JSON で UI を記述し、Renderer がネイティブコンポーネントで描画する。

**コアアーキテクチャ:**
```
Agent (Python/ADK) → A2UI JSON → Transport (REST/A2A) → Renderer (Lit/Angular)
```

**セキュリティモデル:**
- 実行可能コードではなく、宣言的データ形式
- クライアント側の **Catalog** がホワイトリストとして機能
- Agent はカタログに登録されたコンポーネントのみ使用可能

## 2. Basic Catalog コンポーネント一覧

### Layout
| コンポーネント | 用途 | 主要プロパティ |
|-------------|------|-------------|
| `Row` | 水平配置 | `gap`, `align` |
| `Column` | 垂直配置 | `gap`, `align` |
| `List` | リスト表示 | `items` (データバインディング) |

### Display
| コンポーネント | 用途 | 主要プロパティ |
|-------------|------|-------------|
| `Text` | テキスト表示 | `content`, `style` (heading/body/caption) |
| `Image` | 画像表示 | `src`, `alt` |
| `Icon` | アイコン | `name` |
| `Divider` | 区切り線 | — |

### Interactive
| コンポーネント | 用途 | 主要プロパティ |
|-------------|------|-------------|
| `Button` | アクション | `label`, `action`, `variant` (primary/secondary) |
| `TextField` | テキスト入力 | `label`, `placeholder`, `value` |
| `CheckBox` | チェック | `label`, `checked` |
| `Slider` | 数値入力 | `min`, `max`, `value` |
| `DateTimeInput` | 日時入力 | `label`, `value` |
| `ChoicePicker` | 選択肢 | `options`, `selected` |

### Container
| コンポーネント | 用途 | 主要プロパティ |
|-------------|------|-------------|
| `Card` | カード表示 | `children` |
| `Modal` | ダイアログ | `title`, `open`, `children` |
| `Tabs` | タブ切替 | `tabs`, `selected` |

## 3. FastAPI Router → A2UI 変換パターン

### 一覧表示（GET /list）

```json
{
  "type": "createSurface",
  "surfaceId": "entity-list",
  "components": [
    {"id": "root", "type": "Column", "children": ["header", "list"]},
    {"id": "header", "type": "Text", "properties": {"content": "エンティティ一覧", "style": "heading"}},
    {"id": "list", "type": "List", "children": ["card-template"], "dataBinding": "items"}
  ],
  "dataModel": {
    "items": []
  }
}
```

### 作成フォーム（POST /create）

```json
{
  "type": "createSurface",
  "surfaceId": "create-form",
  "components": [
    {"id": "root", "type": "Card", "children": ["form"]},
    {"id": "form", "type": "Column", "children": ["name-field", "date-field", "submit"]},
    {"id": "name-field", "type": "TextField", "properties": {"label": "名前", "placeholder": "入力してください"}},
    {"id": "date-field", "type": "DateTimeInput", "properties": {"label": "日付"}},
    {"id": "submit", "type": "Button", "properties": {"label": "作成", "variant": "primary"}, "action": "submit-create"}
  ]
}
```

### ステータス遷移（PATCH /update）

```json
{
  "type": "createSurface",
  "surfaceId": "status-update",
  "components": [
    {"id": "root", "type": "Card", "children": ["picker", "confirm"]},
    {"id": "picker", "type": "ChoicePicker", "properties": {"options": ["Draft", "Submitted", "Approved"], "selected": "Draft"}},
    {"id": "confirm", "type": "Button", "properties": {"label": "ステータス更新", "variant": "primary"}, "action": "submit-update"}
  ]
}
```

### 削除確認（DELETE /delete）

```json
{
  "type": "createSurface",
  "surfaceId": "delete-confirm",
  "components": [
    {"id": "root", "type": "Modal", "properties": {"title": "削除確認", "open": true}, "children": ["message", "actions"]},
    {"id": "message", "type": "Text", "properties": {"content": "このレコードを削除しますか？"}},
    {"id": "actions", "type": "Row", "children": ["cancel", "delete"]},
    {"id": "cancel", "type": "Button", "properties": {"label": "キャンセル", "variant": "secondary"}, "action": "close-modal"},
    {"id": "delete", "type": "Button", "properties": {"label": "削除", "variant": "primary"}, "action": "submit-delete"}
  ]
}
```

## 4. ADK + FastAPI 統合パターン（`get_fast_api_app()`）

> **ADK API の詳細仕様（`get_fast_api_app` の引数、Session Service の種類、Tool の戻り型契約 など）は、外部スキル `google-agents-cli-adk-code` および `google-agents-cli-deploy` を必ず参照すること。**
> 本セクションは「**当ワークショップ固有の統合パターン**」のみを記載する。

### Session Service の選択（重要）

| 環境 | Service | URI 例 | 備考 |
|------|---------|--------|------|
| ローカル開発（揮発OK） | `InMemorySessionService` | `session_service_uri=None`（引数省略） | プロセス再起動でセッション消失 |
| **当ワークショップ推奨** | `DatabaseSessionService`（SQLAlchemy） | `postgresql+asyncpg://app_user:password@db:5432/migration_db` | docker-compose の `db` を共有。Cloud SQL 本番移行が容易。**ADK は `create_async_engine` を使うため async driver (asyncpg) 必須**。psycopg2 は使えない |
| 本番（GCP） | `cloud_sql` バックエンド | `agents-cli scaffold create --session-type cloud_sql` | `google-agents-cli-deploy` 参照 |
| 本番（GCP, Vertex AI 統合） | `VertexAiSessionService` | `agentengine://{resource_name}` | Agent Runtime デプロイ時 |

> **アンチパターン**: `sqlite+aiosqlite:///./sessions.db` は使用しない。
> 理由: (1) 公式 `--session-type` 選択肢に存在しない、(2) コンテナ揮発・複数レプリカで共有不可、(3) docker-compose に PostgreSQL が既に存在し再利用可能。

### 推奨: Wrapped パターン（当ワークショップ用）

```python
import os
from google.adk.cli.fast_api import get_fast_api_app
from app.config import settings

AGENT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "agent")

# Step 2 で構築した PostgreSQL を ADK セッションストアにも共有
# 本番では Cloud SQL に切り替えるだけ（URI を環境変数で差し替え）
# ADK の DatabaseSessionService は create_async_engine を呼ぶため async driver (asyncpg) 必須。
# psycopg2 を指定すると "asyncio extension requires an async driver" で起動時に落ちる。
SESSION_DB_URL = os.environ.get(
    "ADK_SESSION_DB_URL",
    f"postgresql+asyncpg://{settings.db_user}:{settings.db_password}"
    f"@{settings.db_host}:{settings.db_port}/{settings.db_name}",
)

# ADK が FastAPI app を生成（Agent エンドポイント含む）
app = get_fast_api_app(
    agents_dir=AGENT_DIR,
    session_service_uri=SESSION_DB_URL,
    allow_origins=["*"],
    web=True,  # ADK Web UI も有効化
)

# 既存の FastAPI Router をマウント（Swagger UI / curl での手動確認用）
# → Agent の Tool がこの REST API を呼ぶわけではない。Tool は UseCase を直接呼ぶ。
from app.router.store_visit_router import router as store_visit_router
app.include_router(store_visit_router, prefix="/api/v1")
```

**結果のエンドポイント:**
- `/api/v1/store-visits` — 既存 REST API（Step 3 由来、Swagger / curl 手動確認用）
- `/run` — ADK Agent 実行（Renderer から A2A 経由で呼ばれる）
- `/list-agents` — 登録 Agent 一覧
- `/sessions` — Agent セッション管理（PostgreSQL の `sessions` 等のテーブルに永続化）

### docker-compose で確認する手順

> [!IMPORTANT]
> Step 3 (`app`) と Step 4 (`app-a2ui`) は同じ 8080 を使うため `profiles` で排他制御している。
> Step 4 を起動するときは `--profile a2ui` を必ず付けること。

```bash
# 0. Vertex AI 用 env をホストから渡す
export GOOGLE_CLOUD_PROJECT=my-gcp-project
export GOOGLE_CLOUD_LOCATION=us-central1
gcloud auth application-default login   # 初回のみ

# 1. db + app-a2ui + a2ui-renderer を起動
docker compose --profile a2ui up -d --build

# 2. ADK がセッションテーブルを自動作成しているか確認
docker compose exec db psql -U app_user -d migration_db -c "\dt"
# → sessions, app_states, user_states, events 等が見えれば OK

# 3. Agent エンドポイント疎通確認
curl -s http://localhost:8080/list-apps    # → ["<your_agent_dirname>"]
```

### Step 3 の requirements.txt をそのまま流用すると `google-adk` と依存衝突する

> [!WARNING]
> Step 3 の `requirements.txt` には `fastapi==0.115.5` `uvicorn==0.32.1` `anyio==4.7.0` などの厳格 pin が入っているが、
> `google-adk` 1.x は `starlette>=0.46.2` `uvicorn>=0.34.0` `anyio>=4.9.0` を要求するため、そのままでは
> `pip install` が `ResolutionImpossible` で失敗する。

**Step 4 の `requirements.txt` では Step 3 の pin を `==` から `>=` に緩めること**。最低限以下に揃える:

```
fastapi>=0.116.0
uvicorn[standard]>=0.34.0
anyio>=4.9.0
# 残りの pydantic, sqlalchemy, asyncpg, structlog, httpx は Step 3 の値以上で OK
google-adk>=1.0.0
a2ui-agent-sdk>=0.2.1   # ← 0.8.0 ではない（プロトコルバージョンとの混同に注意）
```

## 5. A2UI Agent の Tool 定義パターン

> **重要**: Tool は REST API を HTTP で呼ぶのではなく、**UseCase / Repository 層を Python 関数として直接 import して呼び出す**。
> `get_fast_api_app()` で Agent と FastAPI Backend が同一プロセスにいるため、HTTP オーバーヘッドなしで in-process 呼び出しが可能。

```python
# agent/tools.py
import json
from google.adk.tools.tool_context import ToolContext
from app.usecase.store_visit_usecase import StoreVisitUseCase
from app.repository.store_visit_repository import StoreVisitRepository
from app.dependencies import get_session

def list_visits(tool_context: ToolContext) -> str:
    """訪問記録の一覧を取得する。"""
    session = get_session()
    usecase = StoreVisitUseCase(StoreVisitRepository(session))
    visits = usecase.list_all()
    return json.dumps([v.dict() for v in visits])

def create_visit(
    store_id: str,
    visit_date: str,
    purpose: str,
    rating: int,
    tool_context: ToolContext,
) -> str:
    """新しい訪問記録を作成する。"""
    session = get_session()
    usecase = StoreVisitUseCase(StoreVisitRepository(session))
    visit = usecase.create(
        store_id=store_id, visit_date=visit_date,
        purpose=purpose, rating=rating,
    )
    return json.dumps(visit.dict())

def update_visit_status(
    visit_id: str,
    new_status: str,
    tool_context: ToolContext,
) -> str:
    """訪問記録のステータスを更新する。"""
    session = get_session()
    usecase = StoreVisitUseCase(StoreVisitRepository(session))
    visit = usecase.update_status(visit_id=visit_id, status=new_status)
    return json.dumps(visit.dict())
```

## 6. `A2uiSchemaManager` プロンプト生成

```python
from a2ui.schema.constants import VERSION_0_9
from a2ui.schema.manager import A2uiSchemaManager
from a2ui.basic_catalog.provider import BasicCatalog

schema_manager = A2uiSchemaManager(
    version=VERSION_0_9,
    catalogs=[BasicCatalog.get_config(version=VERSION_0_9)],
)

instruction = schema_manager.generate_system_prompt(
    role_description="You are a SFDC migration management UI assistant.",
    ui_description="...",  # CRUD パターン別の UI 選択ルール
    include_schema=True,
    include_examples=True,
    validate_examples=True,
)
```

## 7. Lit Renderer セットアップ

> [!IMPORTANT] **パッケージ名・バージョン・API の混同注意**
> - 公式 npm パッケージは **`@a2ui/lit`** と **`@a2ui/web_core`**（Google が公開、Apache-2.0）。
>   `@anthropic-ai/a2ui-lit-renderer` や `@a2ui/lit-renderer` は **存在しない**（過去のドキュメント誤記）。
> - npm パッケージのバージョン (0.9.x 系) と **A2UI プロトコルのバージョン (v0.8 / v0.9)** を混同しない。
>   `^0.8.0` を `dependencies` に書くと npm registry が解決できず `E404` で落ちる。
> - 公式が新規プロジェクトに推奨するのは **protocol v0.9**。`@a2ui/lit/v0_9` から import する。
> - カスタム要素は **`<a2ui-surface>`**（`<a2ui-renderer>` ではない）。
>   Surface オブジェクトは `MessageProcessor` から `onSurfaceCreated` 経由で取得して `.surface` プロパティに渡す。
> - 同様に Python SDK (`a2ui-agent-sdk`) も最新は **0.2.x**。`>=0.8.0` と書くと PyPI で解決できない。
>   v0.8 / v0.9 両プロトコルを 0.2.x SDK が提供する。

### package.json

```json
{
  "name": "a2ui-migration-renderer",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build"
  },
  "dependencies": {
    "@a2ui/lit": "^0.9.3",
    "@a2ui/web_core": "^0.9.2",
    "lit": "^3.2.1"
  },
  "devDependencies": {
    "typescript": "^5.6.3",
    "vite": "^5.4.10"
  }
}
```

### src/app.ts (公式 v0.9 パターン: MessageProcessor + ADK /run_sse 購読)

```typescript
import { LitElement, html, css } from "lit";
import { customElement, state } from "lit/decorators.js";
import { MessageProcessor } from "@a2ui/web_core/v0_9";
import { A2uiSurface, basicCatalog } from "@a2ui/lit/v0_9";

void A2uiSurface; // side-effect import: registers <a2ui-surface>

const APP_NAME = "migration_ui_agent";
const USER_ID = "workshop-user";
const SURFACE_ID = "main-surface";
const AGENT_BASE_URL = "http://localhost:8080";
// Python SDK の A2UI_OPEN_TAG / A2UI_CLOSE_TAG と一致させる
const A2UI_BLOCK_RE = /<a2ui-json>([\s\S]*?)<\/a2ui-json>/g;

@customElement("migration-app")
export class MigrationApp extends LitElement {
  private processor = new MessageProcessor([basicCatalog]);
  @state() private surface?: unknown;
  private sessionId = crypto.randomUUID();

  override connectedCallback() {
    super.connectedCallback();
    this.processor.onSurfaceCreated((s: { id: string }) => {
      if (s.id === SURFACE_ID) this.surface = s;
    });
    // ADK セッション作成
    fetch(`${AGENT_BASE_URL}/apps/${APP_NAME}/users/${USER_ID}/sessions/${this.sessionId}`,
      { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
  }

  private async sendPrompt(prompt: string) {
    const res = await fetch(`${AGENT_BASE_URL}/run_sse`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        app_name: APP_NAME, user_id: USER_ID, session_id: this.sessionId,
        new_message: { role: "user", parts: [{ text: prompt }] },
        streaming: true,
      }),
    });
    // SSE をパースし、各 event の text から <a2ui-json>...</a2ui-json> を抽出して
    // processor.processMessages([...]) に流す（実装は本ワークショップの app.ts を参照）
  }

  render() {
    return html`
      <button @click=${() => this.sendPrompt("一覧を見せて")}>一覧</button>
      ${this.surface
        ? html`<a2ui-surface .surface=${this.surface}></a2ui-surface>`
        : html`<div>Agent からの UI 応答待ち…</div>`}
    `;
  }
}
```

> [!NOTE]
> `<a2ui-surface>` は `MessageProcessor` の `onSurfaceCreated` コールバックから受け取った Surface オブジェクトを `.surface` プロパティに渡すと、catalog に登録された各コンポーネントを Lit でレンダリングする。
> Agent は LLM 応答内に `<a2ui-json>...</a2ui-json>` でラップされた v0.9 メッセージ JSON 配列を出力するので、SSE をストリーミング購読してこのタグを抽出 → JSON parse → `processor.processMessages([...])` に流す。

## 8. Vertex AI 認証設定

```bash
# ADC 認証（ワークショップ前提条件）
gcloud auth application-default login

# 環境変数
export GOOGLE_CLOUD_PROJECT="your-gcp-project-id"
export GOOGLE_CLOUD_LOCATION="us-central1"
```

> **IMPORTANT**: `GOOGLE_API_KEY` は使用不可。必ず Vertex AI 認証（ADC + サービスアカウント）を使用すること。

## 9. SFDC → A2UI 移行対応表

| SFDC UI 技術 | A2UI 対応 | 備考 |
|-------------|----------|------|
| Visualforce Page | A2UI Surface (createSurface) | ページ全体の定義 |
| Lightning Web Component | Lit Custom Element | Web Components ベースで概念的に同一 |
| Lightning Record Form | Card + TextField × N + Button | CRUD フォーム |
| Lightning Datatable | List + Card (テンプレート) | データ一覧 |
| Lightning Flow Screen | Column + TextField/ChoicePicker + Button | ウィザード的 UI |
| Toast Notification | Text (style: caption) | フィードバック表示 |
| Modal (LWC) | Modal コンポーネント | 確認ダイアログ |
