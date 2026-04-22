# プロンプトテンプレート: Apex → Python (FastAPI) TDD 変換

> **用途**: Apex REST Controller を Python (FastAPI) に TDD で変換する
> **対象 AI**: Claude Code via Vertex AI

---

## 使い方

このテンプレートは Step 3 の TDD フロー（3-1 → 3-2 → 3-3）に沿って、3段階に分けて使用します。

---

## Phase 1: テストシナリオ洗い出し（3-1）

```markdown
# 指示

以下の Apex ソースコードを分析し、**テストシナリオの一覧だけ**を出力してください。
コードの変換や実装は行わないでください。

# 抽出すべきテストシナリオ
1. 各 REST エンドポイント（@HttpGet/@HttpPost/@HttpPatch/@HttpDelete）の正常系
2. 各エンドポイントの異常系（バリデーションエラー、存在しないID、権限不足等）
3. ビジネスルール（ステータス遷移、計算ロジック、条件分岐）
4. Trigger の副作用（レコード更新、子レコード連動）
5. 境界値（数値の上限/下限、空文字列、NULL）
6. CASCADE 削除の動作

# 出力形式
| # | カテゴリ | シナリオ | 期待結果 | 元の Apex コード箇所 |

# 出力先
workshop-real/03-code-modernization/output/TEST_SCENARIOS.md

# 入力（Apex ソースコード）
（ファイルを指定 or 貼り付け）
```

---

## Phase 2: テストコード生成 — 🔴 RED（3-2）

```markdown
# 指示

以下のテストシナリオ一覧に基づき、Python のテストコード + スタブ構造を生成してください。
**実装コードは書かないでください。** テストだけ書いて全テストが FAIL する状態を作ります。

# 技術要件
1. **フレームワーク**: pytest
2. **パラメタライズ**: `@pytest.mark.parametrize`
3. **モック**: `unittest.mock.AsyncMock` で Repository 層をモック
4. **HTTP テスト**: FastAPI `TestClient`
5. **テスト命名**: `test_<機能>_<シナリオ>` 形式

# プロジェクト構造
workshop-real/03-code-modernization/output/
├── app/
│   ├── __init__.py
│   ├── main.py            # FastAPI app（最小限の初期化）
│   ├── config.py           # Pydantic Settings（DB_HOST, DB_PORT 等）
│   ├── model/
│   │   ├── __init__.py
│   │   └── schemas.py     # Pydantic モデル（入出力の型定義）
│   ├── router/
│   │   ├── __init__.py
│   │   └── resource.py    # raise NotImplementedError
│   ├── usecase/
│   │   ├── __init__.py
│   │   └── resource.py    # raise NotImplementedError
│   └── repository/
│       ├── __init__.py
│       └── resource.py    # ABC（インターフェースのみ）
├── tests/
│   ├── __init__.py
│   ├── conftest.py
│   ├── test_model.py
│   ├── test_usecase.py
│   └── test_router.py
├── Dockerfile              # マルチステージビルド + nonroot
├── pyproject.toml
└── requirements.txt

# requirements.txt の内容
fastapi>=0.115.0
uvicorn[standard]>=0.32.0
sqlalchemy[asyncio]>=2.0.0
asyncpg>=0.30.0
pydantic-settings>=2.0.0
structlog>=24.0.0
pytest>=8.0.0
pytest-asyncio>=0.24.0
httpx>=0.27.0
ruff>=0.8.0
mypy>=1.13.0

# テストシナリオ
（TEST_SCENARIOS.md の内容を貼り付け）
```

---

## Phase 3: 実装 — 🟢 GREEN（3-3）

```markdown
# 指示

以下のテストコードが**すべて PASS** するように、スタブになっている実装を完成させてください。

# アーキテクチャ要件（厳守）
1. **レイヤー分離**（3層）:
   - `router/` — FastAPI Router（HTTP リクエスト/レスポンスの処理）
   - `usecase/` — ビジネスロジック（純粋な Python、フレームワーク依存なし）
   - `repository/` — データアクセス層（SQLAlchemy + asyncpg）
2. **依存性注入 (DI)**:
   - usecase は repository の ABC に依存する（具象に依存しない）
   - router は usecase に依存する
   - FastAPI の `Depends()` で DI を実現
3. **エラーハンドリング**:
   - 構造化エラーレスポンス: `{"error": "message", "code": "ERROR_CODE"}`
   - HTTP ステータスコードを適切に使い分け
4. **環境変数**:
   - `pydantic-settings` で DB 接続情報を管理
   - DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME
5. **ロギング**: `structlog` による構造化ログ
6. **トランザクション**: 親子レコードの操作は SQLAlchemy Session でアトミックに
7. **Dockerfile**:
   - マルチステージビルド（builder + runtime）
   - runtime は `python:3.12-slim` + nonroot ユーザー
   - ポート 8080 を EXPOSE

# テストコード
（テストコードを貼り付け or ファイルを指定）

# 参考: PostgreSQL テーブル定義
（Step 2 で生成した DDL を貼り付け or ファイルを指定）

# 出力先
workshop-real/03-code-modernization/output/ の既存スタブを上書き
```
