Step 1 Phase 0: SFDX プロジェクトの再帰探索 + ナレッジ抽出

## SFDX ソースディレクトリ
`$ARGUMENTS`

引数が空の場合は `./examples` をデフォルトとして使用してください。
以下、`<SOURCE>` は指定されたディレクトリを指します。

---

## Phase 0-1: ディレクトリ構造の再帰探索

まず指定されたディレクトリの **全体像** を再帰的に把握してください。
固定パス（`force-app/main/default/`）を前提にせず、実際のファイルシステムを走査してください。

### 実行手順

```bash
# 1. Tree 構造の取得（.git, node_modules, .sfdx を除外）
find <SOURCE> -type f \
  -not -path '*/.git/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.sfdx/*' \
  -not -name '*.cls-meta.xml' \
  -not -name '*.trigger-meta.xml' \
  -not -name '*.js-meta.xml' \
  -not -name '*.page-meta.xml' \
  | sort

# 2. ファイル種別ごとの統計
find <SOURCE> -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn
```

### 出力: `source_tree.md`

以下の形式で出力してください:

```markdown
# ソースコード Tree マップ

## プロジェクト概要
- ルートディレクトリ: <SOURCE>
- sfdx-project.json: (存在する場合はその内容の要約)
- 総ファイル数: N 件
- 総行数: N 行（概算）

## ファイル種別統計
| 拡張子 | ファイル数 | 主な用途 |
|--------|----------|---------|
| .cls | N | Apex クラス |
| .trigger | N | Apex トリガー |
| .object-meta.xml | N | カスタムオブジェクト定義 |
| .field-meta.xml | N | フィールド定義 |
| .page | N | Visualforce ページ |
| .js | N | LWC JavaScript |
| .html | N | LWC テンプレート |
| .flow-meta.xml | N | フロー定義 |
| .permissionset-meta.xml | N | 権限セット |
| .profile-meta.xml | N | プロファイル |
| .layout-meta.xml | N | レイアウト |
| .email-meta.xml | N | メールテンプレート |
| .app-meta.xml | N | アプリケーション定義 |
| .tab-meta.xml | N | タブ定義 |
| その他 | N | ... |

## ディレクトリ Tree

```
<SOURCE>/
├── force-app/
│   └── main/
│       └── default/
│           ├── classes/           (N files)
│           │   ├── XxxController.cls
│           │   ├── XxxService.cls
│           │   └── ...
│           ├── triggers/          (N files)
│           ├── objects/           (N dirs)
│           │   ├── Account__c/
│           │   │   ├── Account__c.object-meta.xml
│           │   │   └── fields/
│           │   │       ├── FieldA__c.field-meta.xml
│           │   │       └── ...
│           │   └── ...
│           ├── pages/             (N files)
│           ├── lwc/               (N dirs)
│           ├── aura/              (N dirs)
│           ├── flows/             (N files)
│           ├── layouts/           (N files)
│           ├── permissionsets/    (N files)
│           └── ...
├── data/                          (CSV export)
└── sfdx-project.json
```
```

## ファイル一覧（フルパス）

すべてのソースファイルをフルパスで列挙し、以下の列を付与:
| # | パス | 種別 | 行数 | 概要（1行） |

---

## Phase 0-2: コード規模感の速攻把握

```bash
# Apex コードの総行数
find <SOURCE> -name '*.cls' -o -name '*.trigger' | xargs wc -l | tail -1

# オブジェクト数
find <SOURCE> -name '*.object-meta.xml' | wc -l

# フィールド数
find <SOURCE> -name '*.field-meta.xml' | wc -l

# テストクラスの数
find <SOURCE> -name '*Test.cls' -o -name '*_Test.cls' | wc -l
```

---

## Phase 0-3: ナレッジ抽出（コードパターンカタログ）

**全 `.cls` ファイルと `.trigger` ファイルを読み込み**、以下のパターンを grep / 目視で検出してください。
これは後続 Step で移行先を設計する際の **暗黙ナレッジ** として極めて重要です。

### 3-A: SFDC プラットフォーム依存 API

以下の API/キーワードをソース全体から検索し、**出現箇所を記録** してください:

| カテゴリ | 検索キーワード | 移行先パターン |
|---------|-------------|-------------|
| 認証/ユーザー | `UserInfo.getUserId()`, `UserInfo.getName()` | JWT / IAP / Firebase Auth |
| DB 操作 | `Database.query`, `Database.getQueryLocator`, `[SELECT` | SQLAlchemy Query |
| DML | `insert `, `update `, `delete `, `upsert ` | SQLAlchemy Session |
| トランザクション | `Database.setSavepoint`, `Database.rollback` | SQLAlchemy Transaction |
| バッチ | `Database.Batchable`, `Database.executeBatch`, `Database.Stateful` | Cloud Run Jobs |
| スケジュール | `Schedulable`, `System.schedule` | Cloud Scheduler |
| メール | `Messaging.SingleEmailMessage`, `Messaging.sendEmail` | SendGrid / Cloud Tasks |
| REST | `@RestResource`, `@HttpGet`, `@HttpPost` | FastAPI Router |
| Callout | `Http`, `HttpRequest`, `HttpResponse`, `@future(callout=true)` | httpx / Cloud Tasks |
| キュー | `Queueable`, `System.enqueueJob` | Cloud Tasks / Pub/Sub |
| プラットフォームイベント | `EventBus.publish` | Pub/Sub |
| 承認プロセス | `Approval.ProcessSubmitRequest` | Workflows / 要再設計 |
| 共有 | `with sharing`, `without sharing`, `inherited sharing` | 認可ミドルウェア |
| ガバナ制限対策 | `Limits.getQueries()`, `Limits.getLimitQueries()` | 不要（削除対象） |
| Visualforce | `ApexPages`, `PageReference` | フロントエンド刷新（スコープ外候補） |
| カスタム設定/メタデータ | `CustomSetting__c`, `CustomMetadata__mdt` | 環境変数 / Config |

### 3-B: ビジネスロジックパターン

| パターン | 検出方法 | 記録すべき情報 |
|---------|---------|-------------|
| **ステータス遷移** | `Status__c`, `Map<String, Set<String>>` | 遷移テーブル全体 |
| **バリデーション** | `throw new`, `addError(`, `errors.add(` | ルール + エラーメッセージ |
| **集計計算** | `AggregateResult`, `AVG(`, `COUNT(`, `SUM(` | 対象フィールド + 条件 |
| **親子操作** | `Master-Detail`, `CASCADE`, `Savepoint` | 親子関係 + 操作パターン |
| **重複チェック** | `LIMIT 1`, `duplicates`, `existing` | 重複検知条件 |
| **外部 ID** | `ExternalId`, `upsert ... ExternalId` | フィールド + 用途 |
| **レコードタイプ** | `RecordType`, `RecordTypeId` | 分岐ロジック |
| **数式フィールド** | `formula`, `FormulaField` (XML 内) | 計算式 + 参照先 |
| **ロールアップ集計** | `summarizedField`, `RollupSummary` (XML 内) | 集計元 + 関数 |

### 3-C: コーディングスタイル/慣習

| 観点 | 記録すべき情報 |
|------|-------------|
| 命名規則 | クラス名の接尾辞パターン（Controller/Service/Handler/Util/Batch 等） |
| レイヤー分離 | Controller → Service → Repository の有無 |
| エラーハンドリング | カスタム例外の有無、エラーレスポンス形式 |
| テストデータ作成 | `@TestSetup` vs テストメソッド内、TestFactory の有無 |
| コメント/ドキュメント | Javadoc スタイルの有無、日本語/英語 |
| Trigger パターン | 直接実装 vs Handler 委譲パターン |

---

## 出力先

以下の 2 ファイルを出力してください:

1. **`01-reverse-engineering/output/source_tree.md`** — Tree 構造 + ファイル一覧 + 統計
2. **`01-reverse-engineering/output/knowledge_catalog.md`** — ナレッジ抽出カタログ（3-A, 3-B, 3-C の全結果）

## この Phase の完了条件

- [ ] ソースディレクトリの全ファイルが走査されている
- [ ] `.cls` / `.trigger` / `.object-meta.xml` / `.field-meta.xml` の件数が正確
- [ ] SFDC 依存 API の出現箇所が `grep` で検証可能なレベルで記録されている
- [ ] ビジネスロジックパターンが具体的なコード箇所付きで記録されている
- [ ] コーディング慣習が後続 Step のアーキテクチャ判断に使えるレベルで記録されている

> [!IMPORTANT]
> この Phase で生成した `source_tree.md` と `knowledge_catalog.md` は、
> 後続の `/project:reverse-engineer` と `/project:assess-migration` の **インプット** になります。
> 先にこのコマンドを実行してから、`/project:reverse-engineer` を実行してください。
