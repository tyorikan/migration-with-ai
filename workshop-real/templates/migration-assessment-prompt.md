# プロンプトテンプレート: 移行影響分析

> **用途**: SFDC のコンポーネントを分析し、移行難易度・リスク・SFDC依存度をスコアリングする
> **対象 AI**: Claude Code via Vertex AI

---

## プロンプト本文

```markdown
# 指示

あなたは Salesforce から Google Cloud への移行スペシャリストです。
以下の SFDX プロジェクトのソースコードを分析し、**移行影響分析レポート**を生成してください。

# 分析対象
force-app/ 配下の全 Apex クラス、Trigger、Batch

# 生成すべきレポート

## 1. コンポーネント別 移行難易度スコアリング

各 Apex ファイルについて以下を評価:

| コンポーネント | 種別 | 行数 | SFDC依存度(高/中/低) | 外部連携(有/無) | 移行難易度(S/M/L/XL) | 推奨移行先 |

### 難易度の判定基準
- **S（Small）**: 単純な CRUD、外部依存なし、200行以下
- **M（Medium）**: バリデーションあり、Trigger 連動あり、200-500行
- **L（Large）**: 外部 API 連携あり、複雑なビジネスロジック、500行以上
- **XL（Extra Large）**: Flow/Process Builder との連動、複数オブジェクト横断、再設計が必要

## 2. SFDC プラットフォーム依存のマッピング

コード中に出現する SFDC 固有の API/機能を洗い出し、移行先パターンを提案:

| SFDC 依存 API/機能 | 出現ファイル | 出現行 | 移行先パターン | 難易度 | 備考 |

### 代表的なマッピング例（参考）
- `UserInfo.getUserId()` → 認証基盤（IAP / Firebase Auth）
- `Database.insert/update/delete` → SQLAlchemy ORM
- `Database.DMLOptions` → SQLAlchemy トランザクション
- `System.schedule()` → Cloud Scheduler
- `Messaging.SingleEmailMessage` → SendGrid / Cloud Tasks
- `ApexPages.addMessage()` → FastAPI HTTPException
- `Schema.SObjectType.describe()` → 静的型定義 / Pydantic モデル
- `Test.startTest()/stopTest()` → pytest fixture
- `System.runAs()` → テスト用モック

## 3. リスク評価

| リスク項目 | 該当コンポーネント | 影響度(高/中/低) | 対策案 |

リスクの例:
- ガバナ制限に依存したロジック（バッチサイズ制御等）
- `without sharing` キーワードを使用したセキュリティ例外
- `@future` や `Queueable` を使った非同期処理
- Platform Event / Change Data Capture の利用

## 4. 移行推奨順序

影響分析の結果を踏まえた移行推奨順序:
1. 最初に移行すべき: [理由]
2. 次に移行すべき: [理由]
3. 最後に移行すべき: [理由]

# 出力形式
- Markdown 形式で出力
- 日本語で記述

# 出力先
workshop-real/01-reverse-engineering/output/migration_assessment.md
```
