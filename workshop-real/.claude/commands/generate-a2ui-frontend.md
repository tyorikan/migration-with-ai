Step 4: A2UI フロントエンド生成 — ADK Agent + Lit Renderer

## 入力（自動参照）

### Step 1 の成果物（設計情報）
- 統合設計書: `01-reverse-engineering/output/system_overview.md`（API 仕様・エンティティ一覧・ステータス遷移）

### Step 3 の成果物（Backend 実装）
- FastAPI Router: `03-code-modernization/output/app/router/`
- Pydantic Schema: `03-code-modernization/output/app/model/schemas.py`
- UseCase: `03-code-modernization/output/app/usecase/`
- 依存定義: `03-code-modernization/output/requirements.txt`

## 必須参照スキル（Plan 提示前に必ず Skill ツールで開くこと）

ADK 関連の判断は当ファイルの抜粋ではなく、Google 公式スキルを根拠とする:

- **`google-agents-cli-workflow`** — ADK 開発ライフサイクル全体（Always active）
- **`google-agents-cli-adk-code`** — Agent / Tool / callbacks / **state/sessions** の API 詳細
- **`google-agents-cli-deploy`** — `session_service_uri` の選択肢と本番デプロイ
- **`a2ui-frontend`** — A2UI v0.8 + 当 Workshop 固有の統合パターン（PostgreSQL 共有 / Lit Renderer）

> Plan 段階で「どのスキルを根拠に何を決めたか」を明記すること。

### スキル取得（コマンド実行の最初に必ずチェック）

`google-agents-cli-*` スキルは **動的取得 / git 管理外** の方針。コマンド実行開始時に以下を必ず実行:

```bash
# 既に存在すればスキップ、無ければ取得（副作用ディレクトリも自動掃除）
./scripts/install-adk-skills.sh
```

**スキルが新規取得された場合**: 現在の Claude Code セッションでは認識されない。ユーザーに「`/clear` で再起動 → 再度 `/generate-a2ui-frontend` を実行してください」と案内し、当コマンドは一旦終了する。
**既存だった場合**: そのまま下記 Phase 0 へ進む。

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
3. Agent の Tool として、Step 3 の **UseCase / Repository 層を Python 関数で直接呼び出す**関数を定義（REST API を HTTP で呼ぶのではなく in-process 呼び出し）
4. `04-frontend-a2ui/output/main.py` を **書き換え**: `get_fast_api_app()` で ADK アプリを生成し、既存 Router を `include_router()` でマージ
   - **`session_service_uri` は PostgreSQL を指す**（`postgresql+psycopg2://app_user:password@db:5432/migration_db` または `app/config.py` から組み立てる）
   - **SQLite (`sqlite+aiosqlite:///`) は禁止** — 公式 `--session-type` 選択肢に存在せず、コンテナ揮発・複数レプリカ非対応
5. `requirements.txt` に `google-adk`, `a2ui-agent-sdk`, `psycopg2-binary` を **追記**（PostgreSQL ドライバ）
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
# 0. セッション URI が PostgreSQL を指しているか静的検証（SQLite 禁止）
grep -nE "session_service_uri" 04-frontend-a2ui/output/main.py
grep -E "sqlite" 04-frontend-a2ui/output/main.py && echo "❌ SQLite 検出 — PostgreSQL に修正" && exit 1

# 1. docker-compose で DB + App 起動
docker compose up -d --build db app

# 2. ADK が PostgreSQL にセッションテーブルを自動作成しているか確認
docker compose exec db psql -U app_user -d migration_db -c "\dt" | grep -iE "(session|state|event)"
# → sessions / app_states / user_states / events 等が見えれば OK

# 3. 既存 REST API が動作確認（Step 3 の API がそのまま動く）
curl -s http://localhost:8080/api/v1/store-visits | head -20

# 4. Agent エンドポイント確認
curl -s http://localhost:8080/list-agents

# 5. Lit Renderer 起動
cd 04-frontend-a2ui/output/renderer && npm install && npm run dev
```

### 完了チェックリスト

Plan の最後に以下を全項目チェックすること（チェックが付かない項目があれば修正してから完了報告）:

- [ ] Skill ツールで `google-agents-cli-workflow`, `google-agents-cli-adk-code`, `google-agents-cli-deploy`, `a2ui-frontend` を起動した
- [ ] `main.py` の `session_service_uri` が `postgresql+psycopg2://...`（または環境変数経由）を指す
- [ ] `main.py` 内に `sqlite` 文字列が一切ない（`grep -E "sqlite" main.py` が空）
- [ ] `requirements.txt` に PostgreSQL ドライバ（`psycopg2-binary` 等）が含まれる
- [ ] `docker compose up -d` で DB + App + （オプション）Renderer が起動する
- [ ] `psql -c "\dt"` で ADK のセッションテーブルが PostgreSQL 上に作成されている
- [ ] `GOOGLE_API_KEY` を一切使用していない（Vertex AI ADC のみ）
- [ ] Step 3 の `app/` `tests/` がバイト同一（`diff -rq` で差分なし）

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
│   └── tools.py                ← UseCase/Repository 直接呼び出し Tool
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
