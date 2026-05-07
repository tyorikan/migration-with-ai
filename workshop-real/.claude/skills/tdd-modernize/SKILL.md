---
name: tdd-modernize
description: Apex テストクラスを pytest に変換し、TDD で Python コードを実装するスキル。RED → GREEN → REFACTOR のサイクルを厳守し、Apex の assert を仕様として扱う。
---

Apex テストクラスから pytest テストを生成し、テスト駆動でモダナイズを進めるワークフロー。

## When to Activate
- Apex テストクラスを pytest に変換するとき
- TDD で Python モジュールを実装するとき
- テストファーストで移行コードを書くとき

## TDD ワークフロー

```
0. CONTRACT: API 契約 (公開 URL prefix を含む) を確定する  ← 必須・先頭
1. RED:    Apex テストクラスから pytest テストを生成 → 実行 → 失敗を確認
2. GREEN:  最小限の実装でテストをパスさせる
3. REFACTOR: リファクタリング（テストは緑のまま）
4. REPEAT: 次のテストケースへ
```

## Step 0: API 契約の確定（**必須・最優先**）

> **過去の事故事例**: README に `/api/v1/store-visits` と仕様化されていたのに、実装は `/store-visits` (prefix なし) で生成され、テストも実装に追従して `/store-visits` で書かれてしまった。pytest は全 PASS だが、**テスト自体が仕様から外れていた**ため Step 4 (Frontend) 構築時に発覚するまで誰も気付かなかった。
>
> 同じ事故を防ぐために、テストを 1 行でも書く前に「最終公開 URL」を確定する。

### Step 0-1: 仕様ソースから URL を抽出する

以下を「仕様」として横断的に grep し、**全 path のリスト** を作る。

```bash
# 入力ソース 1: Step 1 逆起こし
grep -E "GET|POST|PATCH|DELETE|PUT" 01-reverse-engineering/output/system_overview.md \
  | grep -oE "/[a-z][a-z0-9/_{}-]*"

# 入力ソース 2: Step 3 README (バージョン prefix の決定が含まれる)
grep -oE "https?://[^[:space:]]+|/api/v1/[^[:space:]\"'\\)]+" 03-code-modernization/README.md

# 入力ソース 3: Step 1 wiki (推奨マッピング欄)
grep -E "APIRouter|prefix|url" 01-reverse-engineering/output/wiki/classes/*.md
```

### Step 0-2: 「公開 URL contract 表」を成果物として書く

`tests/conftest.py` 直上または `tests/contract.py` に以下のような **唯一の真実テーブル** を残す。

```python
# tests/contract.py — API 契約 (Single Source of Truth for URLs)
# README.md / system_overview.md と一致させること。
# テストはここを import する。直書きしない。

API_PREFIX = "/api/v1"

ROUTES = {
    "list_visits":   ("GET",    f"{API_PREFIX}/store-visits"),
    "get_visit":     ("GET",    f"{API_PREFIX}/store-visits/{{id}}"),
    "create_visit":  ("POST",   f"{API_PREFIX}/store-visits"),
    "update_visit":  ("PATCH",  f"{API_PREFIX}/store-visits/{{id}}"),
    "delete_visit":  ("DELETE", f"{API_PREFIX}/store-visits/{{id}}"),
    "healthz":       ("GET",    "/healthz"),  # infra path (no prefix)
}
```

### Step 0-3: FastAPI の prefix 戦略を決定

`include_router` の prefix と APIRouter の prefix のどちらに `/api/v1` を置くかを **明示的に決める**。

| パターン | 実装 | 適用 |
|---------|------|------|
| **(A) include 側にバージョン prefix** | `app.include_router(visits_router, prefix="/api/v1")`<br>`router = APIRouter(prefix="/store-visits")` | バージョン管理を main で集中させたい場合（**推奨**） |
| (B) router 側に全部入り | `app.include_router(visits_router)`<br>`router = APIRouter(prefix="/api/v1/store-visits")` | router 単独で完結させたい場合 |
| (C) `root_path` でプロキシに任せる | `app = FastAPI(root_path="/api/v1")`<br>`app.include_router(visits_router)` | リバースプロキシ (ALB など) で prefix 剥離する場合 |

**インフラエンドポイント** (`/healthz`, `/metrics`, `/readyz`) は K8s/Cloud Run の慣例で **ルート直下** に置く (バージョン prefix を付けない)。

### Step 0-4: テストは契約から URL を取る

```python
# tests/test_router.py
from tests.contract import ROUTES

async def test_list_visits(client):
    method, path = ROUTES["list_visits"]
    res = await client.request(method, path)
    assert res.status_code == 200
```

これにより、**プロダクト URL を変更したら全テストが自動追従** + **README/設計書と URL がズレた瞬間に grep で発見可能**になる。

### Step 0-5: GREEN 後の **契約適合チェック** を必ず実行

```bash
# ① 実装の OpenAPI を取得
.venv/bin/uvicorn app.main:app --port 18080 &
UV_PID=$!
sleep 2
curl -fsS http://127.0.0.1:18080/openapi.json | jq -r '.paths | keys[]' | sort > /tmp/openapi-paths.txt
kill $UV_PID

# ② contract.py の path と diff
python3 -c "from tests.contract import ROUTES; [print(p) for _,p in ROUTES.values()]" \
  | sed 's/{[^}]*}/{[^/]*}/g' | sort > /tmp/contract-paths.txt

diff /tmp/contract-paths.txt /tmp/openapi-paths.txt && echo "✅ 契約適合" || \
  { echo "🔴 契約と実装の URL が不一致"; exit 1; }
```

このチェックを **GREEN フェーズ完了の必須条件** とし、`/review-gate 3` でも同等のチェックを再実行する。

## Step 1: Apex テスト → pytest 変換ルール

### テストデータ

```apex
// Apex: @TestSetup
@TestSetup
static void setupTestData() {
    Account acc = new Account(Name = 'テスト企業');
    insert acc;
    Contact con = new Contact(
        FirstName = '太郎',
        LastName = 'テスト',
        AccountId = acc.Id
    );
    insert con;
}
```

```python
# Python: @pytest.fixture
import pytest
from uuid import uuid4

@pytest.fixture
async def test_account(session):
    account = Account(
        id=uuid4(),
        name="テスト企業",
    )
    session.add(account)
    await session.commit()
    return account

@pytest.fixture
async def test_contact(session, test_account):
    contact = Contact(
        id=uuid4(),
        first_name="太郎",
        last_name="テスト",
        account_id=test_account.id,
    )
    session.add(contact)
    await session.commit()
    return contact
```

### アサーション

```apex
// Apex
System.assertEquals('Expected', actual.Name);
System.assertEquals(3, results.size());
System.assert(result.IsActive__c, 'Should be active');
```

```python
# Python
assert actual.name == "Expected"
assert len(results) == 3
assert result.is_active, "Should be active"
```

### 例外テスト

```apex
// Apex
try {
    SomeClass.dangerousMethod();
    System.assert(false, 'Should have thrown');
} catch (AuraHandledException e) {
    System.assertEquals('エラーメッセージ', e.getMessage());
}
```

```python
# Python
from fastapi import HTTPException

async def test_dangerous_method_raises():
    with pytest.raises(HTTPException) as exc_info:
        await some_usecase.dangerous_method()
    assert exc_info.value.status_code == 400
    assert "エラーメッセージ" in str(exc_info.value.detail)
```

### DML 操作

```apex
// Apex
Test.startTest();
insert newRecord;
Test.stopTest();
// verify
System.assertNotEquals(null, newRecord.Id);
```

```python
# Python
async def test_create_record(session, usecase):
    result = await usecase.create(CreateRequest(
        name="テスト",
    ))
    assert result.id is not None

    # DB にも反映されているか確認
    db_record = await session.get(Model, result.id)
    assert db_record is not None
    assert db_record.name == "テスト"
```

## Step 2: テストファイル構成

```
tests/
├── conftest.py              ← 共通フィクスチャ（DB セッション等）
├── unit/
│   ├── test_models.py       ← Pydantic モデルのバリデーション
│   └── test_usecases.py     ← usecase 層の単体テスト
├── integration/
│   ├── test_repositories.py ← DB 操作の統合テスト
│   └── test_api.py          ← API エンドポイントの統合テスト
└── fixtures/
    └── test_data.py         ← @TestSetup 相当のフィクスチャ
```

## Step 3: conftest.py テンプレート

```python
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import (
    create_async_engine,
    async_sessionmaker,
    AsyncSession,
)
from app.main import app
from app.db import Base, get_session

TEST_DATABASE_URL = "postgresql+asyncpg://app_user:password@localhost:5432/test_db"

@pytest_asyncio.fixture
async def engine():
    engine = create_async_engine(TEST_DATABASE_URL)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()

@pytest_asyncio.fixture
async def session(engine):
    async_session = async_sessionmaker(engine, class_=AsyncSession)
    async with async_session() as session:
        yield session
        await session.rollback()

@pytest_asyncio.fixture
async def client(session):
    def override_get_session():
        return session

    app.dependency_overrides[get_session] = override_get_session
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()
```

## テスト品質チェックリスト

- [ ] **Step 0 の API 契約 (`tests/contract.py` または同等) が存在し、テストはそこから URL を取得**（直書き禁止）
- [ ] **`curl /openapi.json` の paths と契約が完全一致**（Step 0-5 のチェック PASS）
- [ ] **README.md の curl 例 / API 表 の URL が実装と一致**（grep で確認）
- [ ] Apex テストの全 assert が pytest に変換されている
- [ ] 正常系・異常系の両方がカバーされている
- [ ] 境界値テスト（空文字、NULL、最大長）が含まれている
- [ ] DB 操作はトランザクション内で実行・ロールバック
- [ ] 外部依存はモック化されている
- [ ] テストが独立して実行可能（順序依存なし）
- [ ] カバレッジ **80% 以上**（`--cov-fail-under=80` で機械的にゲート）
- [ ] **具象 Repository に対する DB 統合テストが少なくとも 1 件**（mock のみではなく、SQLAlchemy 経由で DDL → CRUD → 検証 を回すケース）
- [ ] **Apex Batch クラスがある場合は `tests/test_jobs.py` で Batch 動作を検証**（最低: start フィルタ / execute 集計 / 冪等性 / finish 通知 / 任意月引数）

## 開発依存（`requirements-dev.txt`）

> ランタイム依存は `requirements.txt`、開発・検証依存は `requirements-dev.txt` に分離する。
> `pyproject.toml` で `[tool.mypy] strict = true` などを宣言する場合は、**対応するツールを `requirements-dev.txt` に必ず収録** すること（収録漏れは `No module named ...` で機械的検証が空回りする）。

```
mypy>=1.13.0
pytest-cov>=6.0.0
bandit>=1.8.0
ruff>=0.8.4   # ランタイム不要だが CI で実行するためここでも管理
```

## 実行コマンド

```bash
# 1. テスト + カバレッジ（80% 未満で失敗）
pytest tests/ -v --cov=app --cov-report=term-missing --cov-fail-under=80

# 2. 型チェック（pyproject.toml の [tool.mypy] strict 設定に従う）
mypy app/

# 3. セキュリティスキャン（HIGH/MEDIUM が出たら必ず確認）
bandit -r app/

# 4. lint
ruff check app/ tests/

# 特定テストのみ
pytest tests/unit/test_usecases.py -v -k "test_create"

# 並列実行
pytest tests/ -n auto
```

> **GREEN の定義**: 上記 4 コマンドすべての exit 0、または bandit のみ false positive で `# nosec B<id>` を理由付きで明示している状態。
> いずれかが失敗したまま「実装完了」と報告するのは禁止。
