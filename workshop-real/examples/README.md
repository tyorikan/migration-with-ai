# サンプル SFDX プロジェクト: 店舗訪問記録管理

> [!NOTE]
> これはワークショップのデモ用サンプルデータです。
> お客様の実際の SFDX プロジェクトの代わりに使用できます。

## ビジネスドメイン

**店舗訪問記録管理（Store Visit Management）**

営業担当者が担当店舗を訪問した際の活動記録を管理するシステム。
訪問記録の作成・提出・承認のワークフローと、月次の訪問実績集計を行う。

## データモデル

```
Store__c（店舗マスタ）
  ├── StoreVisit__c（訪問記録） ← Lookup
  │     └── VisitDetail__c（訪問詳細/アクションアイテム） ← Master-Detail
  └── MonthlyVisitSummary__c（月次集計） ← Lookup
```

## ステータス遷移

```
Draft → Submitted → Approved
                  → Rejected → Draft（差し戻し後に再編集可能）
```

## ファイル一覧

### Apex クラス（7クラス: 実装5 + テスト2）

| クラス | 種別 | 責務 |
|--------|------|------|
| `StoreVisitController` | REST API | 訪問記録の CRUD エンドポイント |
| `StoreVisitService` | Service | ステータス遷移、バリデーション、検索 |
| `StoreVisitTriggerHandler` | Trigger Handler | 訪問記録更新時の副作用処理（平均評価計算、最終訪問日更新） |
| `StoreVisitMonthlyBatch` | Batch | 月次集計処理（訪問回数、平均評価、未完了アクション数） |
| `StoreVisitScheduler` | Scheduler | 月次バッチのスケジュール登録 |
| `StoreVisitControllerTest` | **Test** | Controller の CRUD + ステータス遷移 + バリデーション検証（14テストメソッド） |
| `StoreVisitServiceTest` | **Test** | Service のステータス遷移ルール + Trigger 連動 + 境界値検証（12テストメソッド） |

> [!TIP]
> テストクラスの `System.assertEquals()` / `System.assert()` は **SFDC 上の期待動作そのもの**。
> Step 3 の `/project:extract-test-scenarios` で、これらの assert を移行先 pytest のテストシナリオに自動変換できます。

### Apex トリガー（1ファイル）
| ファイル | 対象オブジェクト | イベント |
|---------|----------------|---------|
| `StoreVisitTrigger.trigger` | StoreVisit__c | after insert, after update, before delete |

### カスタムオブジェクト（4オブジェクト）
| オブジェクト | ラベル | フィールド数 |
|------------|--------|------------|
| `Store__c` | 店舗 | 8 |
| `StoreVisit__c` | 店舗訪問記録 | 7 |
| `VisitDetail__c` | 訪問詳細 | 5 |
| `MonthlyVisitSummary__c` | 月次訪問サマリー | 7 |

### Visualforce ページ（1ファイル）
| ファイル | 機能 |
|---------|------|
| `StoreVisitSearch.page` | 検索画面（フィルタ、一覧表示、CSV エクスポート） |

### Lightning Web Component（1コンポーネント）
| コンポーネント | 機能 |
|--------------|------|
| `storeVisitForm` | 訪問記録入力フォーム（星型評価、アクションアイテム動的追加） |

## サンプルデータ（CSV）

`examples/data/` に SFDC Data Loader 形式のエクスポート CSV を用意しています。
Step 2 のデータ移行で使用します。

| ファイル | レコード数 | 内容 |
|---------|-----------|------|
| `Store__c.csv` | 10件 | 全国10店舗（渋谷、新宿、池袋、梅田、心斎橋、名古屋栄、天神、札幌、広島、横浜） |
| `StoreVisit__c.csv` | 10件 | 各ステータス（Draft/Submitted/Approved/Rejected）を含む訪問記録 |
| `VisitDetail__c.csv` | 15件 | 商品配置、販促物設置、クレーム対応等のアクションアイテム |

> [!NOTE]
> CSV は SFDC のエクスポート形式（Id は18桁、日時は `YYYY-MM-DDThh:mm:ss.000+0000`）を忠実に再現しています。
> ワークショップ当日はお客様自身の CSV に差し替えてください。

## ワークショップでの使い方

```bash
# ファイル数の確認
find examples/force-app -name "*.cls" | wc -l          # → 5
find examples/force-app -name "*.trigger" | wc -l       # → 1
find examples/force-app -name "*.object-meta.xml" | wc -l  # → 4
find examples/force-app -name "*.field-meta.xml" | wc -l   # → 27

# Step 1 で Claude Code に渡す
cd examples
claude "このプロジェクトを分析して設計ドキュメントを生成して"
```
