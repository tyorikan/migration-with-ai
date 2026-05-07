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

## 0. `@RestResource` → FastAPI URL prefix 設計（**最優先**）

> **過去の事故**: `@RestResource(urlMapping='/store-visits/*')` の Apex を移行する際、
> README で `/api/v1/store-visits` とバージョン prefix を加える設計判断をしたにも関わらず、
> 実装側で `app.include_router(router)` (prefix なし) のまま生成されてしまい、
> README ↔ 実装が不整合のまま pytest 全 PASS で進んでしまった事故あり。
>
> **必ず以下の表を確認してから実装すること**。

### 0-1: Apex urlMapping → FastAPI のマッピング表

| Apex 元仕様 | Apex がホスト側で持つ prefix | Python 移行時に決めるべき URL |
|------------|----------------------------|-----------------------------|
| `@RestResource(urlMapping='/store-visits/*')` | `/services/apexrest` | **`/api/v1/store-visits`** （バージョン prefix を追加するのが推奨） |
| `@RestResource(urlMapping='/leads/*')` | 同上 | `/api/v1/leads` |

### 0-2: FastAPI 実装パターン (3 種)

```python
# パターン (A) include 側でバージョン prefix を集中管理 ★推奨★
# app/main.py
app.include_router(store_visit_router, prefix="/api/v1")
# app/router/store_visit_router.py
router = APIRouter(prefix="/store-visits", tags=["store-visits"])
# → 公開 URL: /api/v1/store-visits

# パターン (B) router 側に全部入り
app.include_router(store_visit_router)              # main
router = APIRouter(prefix="/api/v1/store-visits")   # router
# → 公開 URL: /api/v1/store-visits

# パターン (C) リバースプロキシで剥離
app = FastAPI(root_path="/api/v1")                  # main
app.include_router(store_visit_router)
router = APIRouter(prefix="/store-visits")          # router
# → 公開 URL は /api/v1/store-visits だが、アプリ内部 URL は /store-visits
#   (ALB / API Gateway で剥離する構成のとき)
```

### 0-3: インフラエンドポイントは prefix なし

```python
# /healthz, /readyz, /metrics は K8s/Cloud Run probe の慣例で
# バージョン prefix を付けず root に置く
@app.get("/healthz")
async def healthz():
    return {"status": "ok"}
```

### 0-4: 実装後の必須確認

```bash
# 1. /openapi.json の paths を確認
curl -fsS http://localhost:8080/openapi.json | jq -r '.paths | keys[]'
# 期待: ["/api/v1/store-visits", "/api/v1/store-visits/{visit_id}", "/healthz"]

# 2. README.md / system_overview.md に書かれた URL と完全一致するか
grep -hE "/api/v1/[a-z][a-z0-9/_{}-]*" README.md ../../01-reverse-engineering/output/system_overview.md \
  | sort -u
```

`tdd-modernize` skill の §Step 0 (API 契約) も併せて参照すること。

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

> **MUST**: `Database.Batchable` を implements する Apex クラスは **すべて** `app/jobs/<job_name>.py` として Python に移植する。スコア評価で「Batch 未着手」は Apex 変換正確性 ≤ 3 に直結するため省略不可。

| SFDC Batch | Python 変換 |
|-----------|------------|
| `Database.Batchable<SObject>` | 独立した Python モジュール（Cloud Run Jobs で実行） |
| `Database.Stateful` 状態保持 | クロージャ or インスタンス変数で実装（async main で集約） |
| `start()` → QueryLocator | SQLAlchemy のクエリ（必要に応じてページネーション） |
| `execute()` → scope | バッチサイズごとの処理ループ（`BATCH_SIZE` 環境変数） |
| `finish()` → 完了処理 | ログ出力 + 結果通知（Cloud Logging / Pub/Sub / メール） |
| `System.schedule()` | Cloud Scheduler → Cloud Run Jobs のトリガー |
| `upsert` | **`INSERT ... ON CONFLICT (key) DO UPDATE` で冪等性担保（必須）** |

### 変換テンプレート（`app/jobs/<job_name>.py`）

```python
"""Monthly aggregation batch — replaces Apex StoreVisitMonthlyBatch.

Run with:
    python -m app.jobs.monthly_visit_batch [YYYY-MM]
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from datetime import date

import structlog
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import SessionLocal
from app.models import MonthlyVisitSummary, Store, StoreVisit, VisitDetail
from app.notifier import EmailMessage, EmailNotifier

logger = structlog.get_logger()
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "200"))


@dataclass
class BatchResult:
    stores_processed: int
    visits_processed: int
    errors: list[str]


async def run_monthly_batch(
    session: AsyncSession,
    notifier: EmailNotifier,
    *,
    month_start: date | None = None,
    month_end: date | None = None,
    admin_email: str | None = None,
) -> BatchResult:
    """Batch Apex の start/execute/finish を 1 関数に集約。冪等。"""
    today = date.today()
    if month_start is None or month_end is None:
        month_start = (today.replace(day=1) - _months(1))
        month_end = today.replace(day=1) - _days(1)

    errors: list[str] = []
    stores_processed = 0
    visits_processed = 0

    # start() 相当: アクティブ店舗を取得
    stores = (await session.execute(
        select(Store).where(Store.is_active == True).order_by(Store.region, Store.store_code)
    )).scalars().all()

    # execute() 相当: バッチごとに集計 + upsert
    for chunk_start in range(0, len(stores), BATCH_SIZE):
        chunk = stores[chunk_start : chunk_start + BATCH_SIZE]
        store_ids = [s.id for s in chunk]

        stats_rows = (await session.execute(
            select(
                StoreVisit.store_id,
                func.count(StoreVisit.id).label("visit_count"),
                func.avg(StoreVisit.rating).label("avg_rating"),
                func.min(StoreVisit.rating).label("min_rating"),
                func.max(StoreVisit.rating).label("max_rating"),
            )
            .where(
                StoreVisit.store_id.in_(store_ids),
                StoreVisit.visit_date.between(month_start, month_end),
                StoreVisit.status.in_(["Submitted", "Approved"]),
            )
            .group_by(StoreVisit.store_id)
        )).all()
        stats_by_store = {r.store_id: r for r in stats_rows}

        pending_rows = (await session.execute(
            select(
                StoreVisit.store_id,
                func.count(VisitDetail.id).label("pending_count"),
            )
            .join(StoreVisit, StoreVisit.id == VisitDetail.store_visit_id)
            .where(
                StoreVisit.store_id.in_(store_ids),
                VisitDetail.is_completed == False,
                VisitDetail.due_date <= month_end,
            )
            .group_by(StoreVisit.store_id)
        )).all()
        pending_by_store = {r.store_id: r.pending_count for r in pending_rows}

        rows = []
        for store in chunk:
            stats = stats_by_store.get(store.id)
            rows.append({
                "id": _generate_summary_id(store.id, month_start),
                "name": f"{store.store_code}-{month_start.strftime('%Y%m')}",
                "store_id": store.id,
                "month_start": month_start,
                "month_end": month_end,
                "visit_count": int(stats.visit_count) if stats else 0,
                "average_rating": stats.avg_rating if stats else None,
                "min_rating": int(stats.min_rating) if stats and stats.min_rating else None,
                "max_rating": int(stats.max_rating) if stats and stats.max_rating else None,
                "pending_action_count": pending_by_store.get(store.id, 0),
            })
            stores_processed += 1
            visits_processed += int(stats.visit_count) if stats else 0

        # ★ 冪等性: ON CONFLICT (store_id, month_start) DO UPDATE
        try:
            stmt = pg_insert(MonthlyVisitSummary).values(rows)
            stmt = stmt.on_conflict_do_update(
                constraint="monthly_visit_summaries_store_month_unique",
                set_={
                    "visit_count": stmt.excluded.visit_count,
                    "average_rating": stmt.excluded.average_rating,
                    "min_rating": stmt.excluded.min_rating,
                    "max_rating": stmt.excluded.max_rating,
                    "pending_action_count": stmt.excluded.pending_action_count,
                    "month_end": stmt.excluded.month_end,
                },
            )
            await session.execute(stmt)
            await session.commit()
        except Exception as e:  # noqa: BLE001 — Apex 元実装も DML 例外を catch して継続
            await session.rollback()
            errors.append(f"DML Error: {e}")
            logger.error("batch_chunk_failed", error=str(e))

    # finish() 相当: 通知
    if admin_email:
        body = (
            f"月次集計バッチが完了しました。\n\n"
            f"対象期間: {month_start} 〜 {month_end}\n"
            f"処理店舗数: {stores_processed}\n"
            f"処理訪問数: {visits_processed}\n"
        )
        if errors:
            body += "\n⚠️ エラー:\n" + "\n".join(errors)
        notifier.send(EmailMessage(
            to_address=admin_email,
            subject=f"【月次集計完了】店舗訪問記録 {month_start} 〜 {month_end}",
            body=body,
        ))

    logger.info(
        "batch_complete",
        stores=stores_processed,
        visits=visits_processed,
        errors=len(errors),
    )
    return BatchResult(stores_processed, visits_processed, errors)


# Helpers omitted — see actual implementation
```

### 必須テストパターン（`tests/test_jobs.py`）

| # | テスト | カバー範囲 |
|---|-------|----------|
| 1 | `test_batch_only_active_stores` | start() のフィルタ |
| 2 | `test_batch_aggregates_submitted_approved_only` | execute() 集計の WHERE |
| 3 | `test_batch_creates_zero_summary_for_stores_with_no_visits` | execute() のゼロ件処理 |
| 4 | `test_batch_idempotent_on_rerun_via_on_conflict_do_update` | ★ 冪等性検証（同月 2 回実行で件数が増えない） |
| 5 | `test_batch_finish_sends_admin_email` | finish() 通知 |
| 6 | `test_batch_accepts_arbitrary_month_arg` | 任意月引数 |

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

## 9. Repository wiring パターン（ABC + 具象 + DI）

> **MUST**: ABC だけ定義して `get_usecase` を `NotImplementedError` のまま提出するのは不合格。
> production 起動時にすぐ 500 になり、`docker compose up` で実 API 検証ができない。
> 必ず ABC + 具象 SQLAlchemy 実装 + `dependencies.py` での Depends チェーンの 3 点セットを揃える。

### a) ABC + dataclass（`app/repository/<entity>_repository.py`）

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import date

@dataclass
class StoreVisitRecord:
    id: str
    store_id: str
    visit_date: date
    status: str
    purpose: str

class StoreVisitRepository(ABC):
    @abstractmethod
    async def get_by_id(self, visit_id: str) -> StoreVisitRecord | None: ...
    @abstractmethod
    async def list_visits(self, *, status: str | None = None, ...) -> list[StoreVisitRecord]: ...
```

### b) 具象 SQLAlchemy 実装（`app/repository/<entity>_repository_sqlalchemy.py`）

```python
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import StoreVisit as StoreVisitORM
from app.repository.store_visit_repository import (
    StoreVisitRecord, StoreVisitRepository,
)

class SqlAlchemyStoreVisitRepository(StoreVisitRepository):
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_id(self, visit_id: str) -> StoreVisitRecord | None:
        row = (await self.session.execute(
            select(StoreVisitORM).where(StoreVisitORM.id == visit_id)
        )).scalar_one_or_none()
        return _to_record(row) if row else None

    # ...
```

### c) DI チェーン（`app/dependencies.py`）

```python
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.notifier import EmailNotifier, NoopNotifier
from app.repository.store_visit_repository_sqlalchemy import (
    SqlAlchemyStoreVisitRepository,
)
from app.usecase.store_visit_usecase import StoreVisitUsecase

SessionDep = Annotated[AsyncSession, Depends(get_session)]

def get_visit_repo(session: SessionDep) -> SqlAlchemyStoreVisitRepository:
    return SqlAlchemyStoreVisitRepository(session)

def get_notifier() -> EmailNotifier:
    return NoopNotifier()  # production では SmtpNotifier 等に差し替え

def get_usecase(
    visit_repo: Annotated[SqlAlchemyStoreVisitRepository, Depends(get_visit_repo)],
    # ... store_repo, user_repo
    notifier: Annotated[EmailNotifier, Depends(get_notifier)],
) -> StoreVisitUsecase:
    return StoreVisitUsecase(
        visit_repo=visit_repo, ..., notifier=notifier,
    )
```

### d) router 側（テスト時は `app.dependency_overrides[get_usecase]` で上書き可能）

```python
from app.dependencies import get_usecase  # routers から見た import 元はここに統一

@router.get("")
async def list_visits(
    usecase: Annotated[StoreVisitUsecase, Depends(get_usecase)],
    ...
): ...
```

---

## 8. よくある間違い（AI が陥りやすいミス）

| ❌ 間違い | ✅ 正しい変換 |
|-----------|-------------|
| SFDC の Id を UUID に変換する | SFDC Id（18桁 VARCHAR）をそのまま保持し、新規レコードには UUID v4 を採番 |
| Trigger の副作用をイベントリスナーで実装 | usecase 層で明示的に呼び出す（暗黙の副作用を避ける） |
| `without sharing` を無視する | 認可要件として明示的に記録し、適切な権限チェックを実装 |
| ガバナ制限回避のコードをそのまま移植 | シンプルな設計に書き直す（N+1 対策は必要） |
| Batch の scope サイズ（200）をハードコード | 環境変数 `BATCH_SIZE` で外部化 |
| Formula フィールドをカラムとして作成 | コメントとして記載し、計算戦略を選択（上記参照） |
| `app.include_router(router)` で公開（prefix なし） | **README/system_overview.md が `/api/v1/...` を仕様化していたら必ず `app.include_router(router, prefix="/api/v1")` で揃える**（§0 参照） |
| テストで URL を直書き (`client.get("/store-visits")`) | `tests/contract.py` に集約し、テストはそこを import（`tdd-modernize` §Step 0 参照） |
