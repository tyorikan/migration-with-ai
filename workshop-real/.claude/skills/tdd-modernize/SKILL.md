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
1. RED:    Apex テストクラスから pytest テストを生成 → 実行 → 失敗を確認
2. GREEN:  最小限の実装でテストをパスさせる
3. REFACTOR: リファクタリング（テストは緑のまま）
4. REPEAT: 次のテストケースへ
```

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

- [ ] Apex テストの全 assert が pytest に変換されている
- [ ] 正常系・異常系の両方がカバーされている
- [ ] 境界値テスト（空文字、NULL、最大長）が含まれている
- [ ] DB 操作はトランザクション内で実行・ロールバック
- [ ] 外部依存はモック化されている
- [ ] テストが独立して実行可能（順序依存なし）
- [ ] カバレッジ 80% 以上

## 実行コマンド

```bash
# テスト実行
pytest tests/ -v

# カバレッジ付き
pytest tests/ --cov=app --cov-report=term-missing

# 特定テストのみ
pytest tests/unit/test_usecases.py -v -k "test_create"

# 並列実行
pytest tests/ -n auto
```
