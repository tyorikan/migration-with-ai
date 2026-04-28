Step 3 Phase 2 + 3: テストコード生成（🔴 RED）→ 実装（🟢 GREEN）

## 入力（自動参照）

### Step 3 の成果物
- テストシナリオ: `03-code-modernization/output/TEST_SCENARIOS.md`

### Step 1-2 の成果物（参照）
- 統合設計書: `01-reverse-engineering/output/system_overview.md`（API 仕様・ステータス遷移・副作用マップ）
- Code Wiki: `01-reverse-engineering/output/wiki/classes/`（Apex クラスの詳細ロジック）
- DDL: `02-schema-migration/output/generated_ddl.sql`（SQLAlchemy モデル生成のベース）

## Phase 2: 🔴 RED — テストコード + スタブ生成

以下のテストシナリオに基づき、**テストコード + スタブ構造** を生成してください。
実装コードはスタブ（`raise NotImplementedError`）にしてください。

### 技術要件
- pytest + `@pytest.mark.parametrize`（テーブル駆動テスト）
- `unittest.mock.AsyncMock` で Repository 層をモック
- FastAPI `TestClient`（httpx ベース）
- テスト命名: `test_<機能>_<シナリオ>`

### プロジェクト構造
CLAUDE.md の「アーキテクチャ（3層レイヤー分離）」に従い、以下を生成:

```
03-code-modernization/output/
├── app/
│   ├── __init__.py
│   ├── main.py            # FastAPI app 初期化 + DI wiring 完成（NotImplementedError は残さない）
│   ├── config.py           # pydantic-settings
│   ├── db.py               # SQLAlchemy async engine + get_session
│   ├── dependencies.py    # get_usecase / get_*_repo を Depends で wire（具象に注入）
│   ├── model/
│   │   ├── __init__.py
│   │   └── schemas.py     # Pydantic モデル
│   ├── router/
│   │   ├── __init__.py
│   │   └── resource.py    # スタブ（raise NotImplementedError）
│   ├── usecase/
│   │   ├── __init__.py
│   │   └── resource.py    # スタブ
│   ├── repository/
│   │   ├── __init__.py
│   │   ├── resource.py    # ABC + dataclass（インターフェース）
│   │   └── resource_sqlalchemy.py  # ★ 必須: SQLAlchemy 具象実装
│   └── jobs/               # ★ 必須（Apex Batch クラスがある場合）
│       ├── __init__.py
│       └── <job_name>.py  # Cloud Run Jobs 互換の async main エントリ
├── tests/
│   ├── __init__.py
│   ├── conftest.py
│   ├── test_model.py
│   ├── test_usecase.py
│   ├── test_router.py
│   └── test_jobs.py        # ★ 必須（Batch がある場合）
├── Dockerfile              # マルチステージ + nonroot
├── pyproject.toml
├── requirements.txt        # ランタイム依存
└── requirements-dev.txt    # ★ 必須: mypy, pytest-cov, bandit を含む
```

> **重要**: 上記構造のうち ★ 印が付いた成果物は **省略不可** です。
> - `repository/<resource>_sqlalchemy.py` と `dependencies.py` は production 起動性を担保するため必須
> - `jobs/`・`test_jobs.py` は対象 SFDC プロジェクトに `Batchable` を implements する Apex クラスが **1 つでも** 存在すれば必須
> - `requirements-dev.txt` は静的解析の機械的検証を可能にするため必須

## Phase 3: 🟢 GREEN — 実装

テストが**すべて PASS** するように、スタブを実装で置き換えてください。

### アーキテクチャ要件（CLAUDE.md 参照）
1. レイヤー分離: router/ → usecase/ → repository/
2. DI: `Depends()` で usecase に repository を注入。**`get_usecase` は `NotImplementedError` のまま残さず、`Depends(get_session) → SqlAlchemyXxxRepository(session) → Usecase(...)` のチェーンで wire する**（→ 詳細は `sfdc-to-python` SKILL の「9. Repository wiring パターン」参照）
3. DB: SQLAlchemy + asyncpg。**Repository ABC ごとに具象 SQLAlchemy 実装（`repository/<resource>_sqlalchemy.py`）を必ず生成する**。ABC のみでの提出は不合格
4. 設定: pydantic-settings
5. ログ: structlog
6. Dockerfile: マルチステージビルド + nonroot + ポート 8080。**builder と runtime の Python マイナーバージョンを完全に一致させる**こと（例: builder が `python:3.12-slim` なら runtime も `python:3.12-slim`）。`gcr.io/distroless/python3-debian12` は **Python 3.11** ベースなので、3.12 でビルドした wheel は読み込めず `No module named <pkg>` で落ちる。distroless を使うなら同じマイナーバージョンの distroless image を選ぶか、素直に `python:3.<X>-slim` ランタイムに非 root user (`useradd --system app`) を作って `USER app` で起動すること
7. エラー: `{"error": "message", "code": "ERROR_CODE"}`
8. **Apex Batch 移行**: 対象 SFDC プロジェクトに `Database.Batchable` を implements する Apex クラスがあれば、`app/jobs/<job_name>.py` を **必ず** 生成する（→ 詳細は `sfdc-to-python` SKILL の「4. Batch Apex → Cloud Run Jobs」参照）。`python -m app.jobs.<job_name>` で起動可能な async main を実装し、冪等性のため `INSERT ... ON CONFLICT DO UPDATE`（または同等の upsert）を入れる。対応する `tests/test_jobs.py` も必須
9. **dev 依存ツール**: `requirements-dev.txt` に最低限 `mypy`, `pytest-cov`, `bandit` を含める。`pyproject.toml` の `[tool.mypy] strict = true` 宣言と整合させる

## 実行後の検証
テストコードと実装を生成したら、以下を実行して結果を報告してください:

```bash
cd 03-code-modernization/output
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt

# 1. テスト + カバレッジ
pytest -v --tb=short --cov=app --cov-report=term-missing --cov-fail-under=80

# 2. 型チェック（pyproject.toml の [tool.mypy] strict 設定に従う）
mypy app/

# 3. セキュリティスキャン
bandit -r app/

# 4. lint
ruff check app/ tests/

# 5. Docker ビルド（uvicorn 等が runtime ランタイムの site-packages から import できることを保証）
#    builder と runtime の Python マイナーバージョン不一致は build では検知できないので
#    以下の起動チェックまで実行すること。
#    Step 3 の app サービスは profiles: [step3] 配下にあるので --profile step3 が必須。
docker compose --profile step3 build app
docker compose --profile step3 up -d db app
sleep 3 && docker compose logs app | tail -20
# logs に "Uvicorn running on http://0.0.0.0:8080" が出ていれば OK。
# "No module named uvicorn" 等が出ていれば Dockerfile の Python バージョン不整合を疑う。
docker compose --profile step3 down
```

**5 つすべてが PASS（または bandit はノイズのみで CRITICAL なし）するまでは GREEN とみなさない。** 失敗があれば、以下のいずれかで対応すること:
- 実装を修正して再実行
- ノイズ（false positive）の場合は明示的に `# noqa` / `# type: ignore[<rule>]` / `# nosec B<id>` を付け、理由をコメントで残す

## 出力先
`03-code-modernization/output/` 配下
