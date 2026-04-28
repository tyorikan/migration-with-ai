Step 4: A2UI フロントエンド生成 — ADK Agent + Lit Renderer

## 入力（自動参照）

### Step 1 の成果物（設計情報）
- 統合設計書: `01-reverse-engineering/output/system_overview.md`（API 仕様・エンティティ一覧・ステータス遷移）

### Step 3 の成果物（Backend 実装）
- FastAPI Router: `03-code-modernization/output/app/router/`
- Pydantic Schema: `03-code-modernization/output/app/model/schemas.py`
- UseCase: `03-code-modernization/output/app/usecase/`
- 依存定義: `03-code-modernization/output/requirements.txt`

## 実行内容

以下を **自律的に** 実行してください。

### Phase 0: Step 3 成果物のコピー

1. `03-code-modernization/output/` の内容を `04-frontend-a2ui/output/` に **丸ごとコピー** する
2. コピー対象: `app/`, `tests/`, `Dockerfile`, `requirements.txt`, `requirements-dev.txt`, `pyproject.toml` 等すべて

```bash
# Step 3 の成果物を 04 にコピー（既存の .gitkeep 等は上書き）
cp -r 03-code-modernization/output/* 04-frontend-a2ui/output/
```

> **重要**: Step 3 の成果物は `03-code-modernization/output/` にそのまま残す（原本として保持）。
> Step 4 の出力 = Step 3 の全コード + A2UI 拡張 = **最終的なデプロイ可能成果物**。

### Phase 1: ADK Agent + FastAPI マージ

1. Step 1 の設計書から、管理画面に必要な UI パターン（一覧・フォーム・ステータス遷移・削除確認）を特定する
2. ADK Agent を構築（`a2ui-agent-sdk` + `A2uiSchemaManager` + `BasicCatalog` 使用）
3. Agent の Tool として、Step 3 の FastAPI REST API を呼び出す関数を定義
4. `04-frontend-a2ui/output/main.py` を **書き換え**: `get_fast_api_app()` で ADK アプリを生成し、既存 Router を `include_router()` でマージ
5. `requirements.txt` に `google-adk`, `a2ui-agent-sdk` を **追記**
6. `prompt_builder.py` に A2UI テンプレート定義を記述（CRUD 各パターン）

### Phase 2: Lit Renderer セットアップ

1. A2UI 公式 Lit Renderer をセットアップ（`renderer/package.json` + `renderer/src/app.ts`）
2. Agent の接続先を設定

### Phase 3: Dockerfile 拡張

1. Step 3 の Dockerfile をベースに ADK + A2UI 依存を追加
2. Agent ディレクトリを COPY に追加

### 検証

生成後、以下を確認してください:

```bash
# 1. Python 依存インストール
cd 04-frontend-a2ui/output
pip install -r requirements.txt

# 2. FastAPI + ADK 起動確認
python main.py &

# 3. 既存 REST API が動作確認（Step 3 の API がそのまま動く）
curl -s http://localhost:8080/api/v1/store-visits | head -20

# 4. Agent エンドポイント確認
curl -s http://localhost:8080/list-agents

# 5. Lit Renderer 起動
cd renderer && npm install && npm run dev
```

## A2UI コンポーネント変換ルール

スキル `a2ui-frontend` の変換パターンに従ってください:
- `GET /list` → Card + List + Text
- `POST /create` → TextField + DateTimeInput + Button
- `PATCH /update` → ChoicePicker + Button
- `DELETE /delete` → Button + Modal

## 技術要件

- **認証**: Vertex AI（ADC）のみ。`GOOGLE_API_KEY` は使用不可
- **ADK**: `google-adk` + `a2ui-agent-sdk` を依存に追加
- **Renderer**: A2UI 公式 Lit Renderer
- **ポート**: Backend + Agent = 8080、Renderer = 5173

## 出力先
`04-frontend-a2ui/output/` 配下

### 生成されるプロジェクト構造

```
04-frontend-a2ui/output/
├── app/                        ← Step 3 からコピー（FastAPI アプリ）
│   ├── main.py                 ← Step 3 の元ファイル（参考用に残す）
│   ├── router/
│   ├── usecase/
│   ├── repository/
│   └── model/
├── tests/                      ← Step 3 からコピー（pytest テスト）
├── agent/                      ← 🆕 ADK Agent + A2UI
│   ├── __init__.py
│   ├── agent.py                ← ADK Agent + A2UI 統合
│   ├── prompt_builder.py       ← A2UI テンプレート・UI 切り替えルール
│   └── tools.py                ← Backend REST API 呼び出し Tool
├── main.py                     ← 🆕 get_fast_api_app() + 既存 Router マージ（エントリポイント）
├── requirements.txt            ← Step 3 + google-adk, a2ui-agent-sdk
├── renderer/                   ← 🆕 Lit Renderer
│   ├── package.json
│   ├── tsconfig.json
│   ├── Dockerfile              ← Renderer 用 Dockerfile
│   └── src/
│       └── app.ts              ← Lit Renderer エントリポイント
└── Dockerfile                  ← Step 3 を拡張（ADK 依存追加）
```

> **ポイント**: `04-frontend-a2ui/output/` だけで完全に自己完結する。
> Step 3 の `03-code-modernization/output/` は「Backend のみ」の原本として残る。
