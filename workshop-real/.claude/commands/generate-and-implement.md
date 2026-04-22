Step 3 Phase 2 + 3: テストコード生成（🔴 RED）→ 実装（🟢 GREEN）

## 入力（自動参照）
- テストシナリオ: `workshop-real/03-code-modernization/output/TEST_SCENARIOS.md`
- DDL: `workshop-real/02-schema-migration/output/generated_ddl.sql`
- API 仕様: `workshop-real/01-reverse-engineering/output/system_overview.md`

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
│   ├── main.py            # FastAPI app 初期化
│   ├── config.py           # pydantic-settings
│   ├── model/
│   │   ├── __init__.py
│   │   └── schemas.py     # Pydantic モデル
│   ├── router/
│   │   ├── __init__.py
│   │   └── resource.py    # スタブ（raise NotImplementedError）
│   ├── usecase/
│   │   ├── __init__.py
│   │   └── resource.py    # スタブ
│   └── repository/
│       ├── __init__.py
│       └── resource.py    # ABC のみ
├── tests/
│   ├── __init__.py
│   ├── conftest.py
│   ├── test_model.py
│   ├── test_usecase.py
│   └── test_router.py
├── Dockerfile              # マルチステージ + nonroot
├── pyproject.toml
└── requirements.txt
```

## Phase 3: 🟢 GREEN — 実装

テストが**すべて PASS** するように、スタブを実装で置き換えてください。

### アーキテクチャ要件（CLAUDE.md 参照）
1. レイヤー分離: router/ → usecase/ → repository/
2. DI: `Depends()` で usecase に repository を注入
3. DB: SQLAlchemy + asyncpg
4. 設定: pydantic-settings
5. ログ: structlog
6. Dockerfile: マルチステージビルド + nonroot + ポート 8080
7. エラー: `{"error": "message", "code": "ERROR_CODE"}`

## 実行後の検証
テストコードと実装を生成したら、以下を実行して結果を報告してください:

```bash
cd workshop-real/03-code-modernization/output
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pytest -v --tb=short
```

## 出力先
`workshop-real/03-code-modernization/output/` 配下
