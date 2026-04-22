---
name: sfdc-to-python
description: Salesforce Apex → Python/FastAPI 変換パターン集。ガバナ制限、Trigger、共有モデル、Batch Apex、Formula、承認プロセスの変換ルールを定義。SFDC コードの移行時に必ず参照すること。
---

Salesforce 固有のパターンを Python/FastAPI に変換する際のドメインナレッジ。

## When to Activate
- Apex クラスを Python に変換するとき
- SFDC Trigger を FastAPI のアーキテクチャに変換するとき
- ガバナ制限回避コードをリファクタリングするとき
- Batch Apex を Cloud Run Jobs に変換するとき
- Formula フィールドの移行戦略を決定するとき

## 1. ガバナ制限 → Python の設計パターン

SFDC にはガバナ制限（SOQL 100回、DML 150回 等）があり、Apex コードはこれを回避する設計になっている。
Python 移行時はガバナ制限が存在しないため、**よりシンプルな設計に書き直す**。

| SFDC パターン | 理由 | Python 変換 |
|-------------|------|------------|
| SOQL をループ外に出す | 100回制限の回避 | 素直に必要な場所でクエリ発行可。ただし N+1 問題は `selectinload` で回避 |
| `Map<Id, SObject>` でキャッシュ | SOQL 回数削減 | SQLAlchemy の relationship + eager loading |
| バルク DML（`insert listOfRecords`） | DML 150回制限 | `session.add_all()` でバッチ INSERT（そのまま活用可） |
| `@future` / `Queueable` | ガバナ制限リセット | Cloud Tasks / Pub/Sub + Cloud Run（非同期処理） |
| `Database.Batchable` | 大量データ処理 | Cloud Run Jobs（バッチサイズは環境変数で制御） |

### 変換例: SOQL ループ回避パターン

```apex
// SFDC: ガバナ制限回避のための Map キャッシュ
Map<Id, Account> accountMap = new Map<Id, Account>(
    [SELECT Id, Name FROM Account WHERE Id IN :accountIds]
);
for (Contact c : contacts) {
    Account a = accountMap.get(c.AccountId);
    // ...
}
```

```python
# Python: SQLAlchemy の eager loading でシンプルに
contacts = await session.execute(
    select(Contact)
    .options(selectinload(Contact.account))
    .where(Contact.id.in_(contact_ids))
)
for contact in contacts.scalars():
    account = contact.account  # N+1 なし
```

## 2. 共有モデル（Sharing）→ 認可設計

| SFDC | 意味 | Python 変換 |
|------|------|------------|
| `with sharing` | 実行ユーザーの共有ルールを適用 | **デフォルト**: ルーター層で認証済みユーザーの権限チェック |
| `without sharing` | 管理者権限で実行（共有ルール無視） | 内部サービス間呼び出し or システムアカウントで実行 |
| `inherited sharing` | 呼び出し元の共有を継承 | コンテキスト伝搬（リクエストスコープで認可情報を保持） |

**重要**: `without sharing` が使われている箇所は、移行後にセキュリティリスクにならないか必ず確認すること。

## 3. Trigger → Python のイベント設計

| SFDC Trigger | タイミング | Python 変換 |
|-------------|----------|------------|
| `before insert` | INSERT 前のバリデーション | Pydantic モデルの `@validator` or usecase 層のバリデーション |
| `after insert` | INSERT 後の副作用 | usecase 層で明示的に実行（暗黙の副作用を避ける） |
| `before update` | UPDATE 前のバリデーション | usecase 層での状態遷移チェック |
| `after update` | UPDATE 後の副作用（親テーブル更新等） | usecase 層で明示的に実行 |
| `before delete` | 削除条件チェック | usecase 層での削除可否判定 |
| `after delete` | 削除後の集計更新 | usecase 層で明示的に実行 |

**設計方針**: SFDC の Trigger は暗黙的に発火するが、Python では **usecase 層で明示的に副作用を管理** する。
`StoreVisitTriggerHandler` のようなパターンは、usecase の `update_visit()` メソッド内で直接呼び出す。

### 変換例: Trigger Handler → usecase

```apex
// SFDC: TriggerHandler パターン
trigger StoreVisitTrigger on StoreVisit__c (after update) {
    StoreVisitTriggerHandler.handleAfterUpdate(
        Trigger.new, Trigger.oldMap
    );
}
public class StoreVisitTriggerHandler {
    public static void handleAfterUpdate(
        List<StoreVisit__c> newList,
        Map<Id, StoreVisit__c> oldMap
    ) {
        for (StoreVisit__c visit : newList) {
            if (visit.Status__c != oldMap.get(visit.Id).Status__c) {
                // 親レコードの集計を更新
            }
        }
    }
}
```

```python
# Python: usecase 層で明示的に副作用管理
class StoreVisitUseCase:
    def __init__(self, visit_repo: StoreVisitRepository):
        self._repo = visit_repo

    async def update_visit(
        self, visit_id: str, update: StoreVisitUpdate
    ) -> StoreVisit:
        visit = await self._repo.get_by_id(visit_id)
        old_status = visit.status

        updated = await self._repo.update(visit_id, update)

        # 副作用を明示的に管理（Trigger の after update 相当）
        if old_status != updated.status:
            await self._update_parent_summary(updated)

        return updated
```

## 4. Batch Apex → Cloud Run Jobs

| SFDC Batch | Python 変換 |
|-----------|------------|
| `Database.Batchable<SObject>` | 独立した Python スクリプト（Cloud Run Jobs で実行） |
| `start()` → QueryLocator | SQLAlchemy のクエリ（ページネーション付き） |
| `execute()` → scope | バッチサイズごとの処理ループ（`BATCH_SIZE` 環境変数） |
| `finish()` → 完了処理 | ログ出力 + 結果通知（Cloud Logging / Pub/Sub） |
| `System.schedule()` | Cloud Scheduler → Cloud Run Jobs のトリガー |

### 変換テンプレート

```python
import os
import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

logger = structlog.get_logger()
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "200"))

async def run_batch(session: AsyncSession) -> dict:
    """Batch Apex の execute() 相当"""
    offset = 0
    total_processed = 0

    while True:
        # start() 相当: QueryLocator
        result = await session.execute(
            select(TargetModel)
            .where(TargetModel.needs_processing == True)
            .limit(BATCH_SIZE)
            .offset(offset)
        )
        batch = result.scalars().all()

        if not batch:
            break

        # execute() 相当: バッチ処理
        for record in batch:
            await process_record(record)
            total_processed += 1

        await session.commit()
        offset += BATCH_SIZE
        logger.info("batch_progress", processed=total_processed)

    # finish() 相当: 完了処理
    logger.info("batch_complete", total=total_processed)
    return {"processed": total_processed}
```

## 5. Formula フィールド → 計算戦略

| 方針 | 条件 | 実装 |
|------|------|------|
| **DB 計算カラム** | 単純な計算式 | `GENERATED ALWAYS AS (...)` |
| **アプリ計算** | 他テーブル参照が必要 | Pydantic の `@computed_field` or usecase 層 |
| **非正規化** | 頻繁に参照、更新は稀 | 別カラムとして保持、更新時に再計算 |

**注意**: SFDC の Formula はリアルタイム計算だが、PostgreSQL の `GENERATED` カラムは INSERT/UPDATE 時のみ計算される。

## 6. 承認プロセス → ステータス遷移

SFDC の承認プロセスは `stateDiagram-v2` で可視化し、usecase 層で状態マシンとして実装する。

```python
# ステータス遷移の定義例
VALID_TRANSITIONS = {
    "Draft": ["Submitted"],
    "Submitted": ["Approved", "Rejected"],
    "Rejected": ["Draft"],  # 差し戻し後の再編集
    "Approved": [],          # 最終状態
}

def validate_transition(current: str, next_status: str) -> bool:
    """遷移の妥当性チェック"""
    allowed = VALID_TRANSITIONS.get(current, [])
    if next_status not in allowed:
        raise ValueError(
            f"Invalid transition: {current} → {next_status}. "
            f"Allowed: {allowed}"
        )
    return True
```

## 7. Apex テストクラス → pytest テストシナリオの変換

Apex テストクラスの `System.assertEquals()` / `System.assert()` は **移行先の仕様そのもの**。

| Apex テストパターン | pytest 変換 |
|-------------------|------------|
| `@TestSetup` → テストデータ作成 | `@pytest.fixture` でフィクスチャ定義 |
| `Test.startTest()` / `Test.stopTest()` | 不要（pytest は自動管理） |
| `System.assertEquals(expected, actual)` | `assert actual == expected` |
| `System.assert(condition, message)` | `assert condition, message` |
| `try { ... } catch (AuraHandledException e)` | `with pytest.raises(HTTPException)` |
| `System.runAs(user)` | テスト用の認証モック |

## 8. よくある間違い（AI が陥りやすいミス）

| ❌ 間違い | ✅ 正しい変換 |
|-----------|-------------|
| SFDC の Id を UUID に変換する | SFDC Id（18桁 VARCHAR）をそのまま保持し、新規レコードには UUID v4 を採番 |
| Trigger の副作用をイベントリスナーで実装 | usecase 層で明示的に呼び出す（暗黙の副作用を避ける） |
| `without sharing` を無視する | 認可要件として明示的に記録し、適切な権限チェックを実装 |
| ガバナ制限回避のコードをそのまま移植 | シンプルな設計に書き直す（N+1 対策は必要） |
| Batch の scope サイズ（200）をハードコード | 環境変数 `BATCH_SIZE` で外部化 |
| Formula フィールドをカラムとして作成 | コメントとして記載し、計算戦略を選択（上記参照） |
