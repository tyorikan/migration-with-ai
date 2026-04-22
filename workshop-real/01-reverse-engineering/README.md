# Step 1: AI による設計ドキュメント逆起こし（10:30 – 12:00）

> [!IMPORTANT]
> **ワークショップ最大の目玉ステップ。** 設計書なしの状況を逆手に取り、ソースコードから AI に設計を逆起こしさせる。
> ここで生成した設計書が、Step 2 以降すべてのインプットになる。

## 🎯 ゴール

| 成果物 | 内容 |
|--------|------|
| **システム概要書** | 全 Apex クラスの責務一覧、依存関係図、ビジネスフロー図 |
| **データモデル仕様書** | ER 図、フィールド定義一覧、Picklist 値一覧 |
| **API 仕様書** | REST エンドポイント一覧、入出力定義 |
| **移行影響分析レポート** | コンポーネント別の難易度スコアリング、SFDC 依存部分のマッピング |

> [!TIP]
> 出力先: `01-reverse-engineering/output/` 配下

---

## 1-1. システム概要書の生成（30分）

Claude Code にお客様のソースコードディレクトリを指定し、以下のプロンプトを実行します。

```bash
# Claude Code で実行
claude "以下の指示に従ってください。$(cat workshop-real/templates/reverse-engineering-prompt.md)"
```

または Claude Code の対話モードで `templates/reverse-engineering-prompt.md` の内容を指示します。

### 期待される出力

1. **クラス責務一覧テーブル**
   | クラス名 | 種別 | 責務 | 依存先 |
   |---------|------|------|--------|
   | `XxxController` | REST API | ○○の CRUD 操作 | `XxxService`, `XxxRepository` |
   | `XxxTrigger` | Trigger | ○○更新時の副作用処理 | `XxxHandler` |
   | ... | ... | ... | ... |

2. **ビジネスロジックフロー図**（Mermaid `flowchart TD`）

3. **クラス間依存関係図**（Mermaid `graph LR`）

4. **外部連携一覧**（API コールアウト、メール送信、外部システム連携等）

### 🤖 AI セルフレビュー

生成後、Claude Code に以下を追加で指示：

```
生成したシステム概要書をレビューしてください。
- 漏れているクラスはないか？
- 依存関係の方向は正しいか？
- ビジネスフロー図は Apex のロジックと整合しているか？
```

---

## 1-2. データモデル・API 仕様の生成（20分）

### データモデル

`.object-meta.xml` と `.field-meta.xml` を Claude Code に読み込ませ、以下を生成：

- **ER 図**（Mermaid `erDiagram`）
  - オブジェクト間のリレーション（Lookup / Master-Detail）
  - 各フィールドの型と制約

- **フィールド定義一覧**
  | オブジェクト | フィールド | API名 | 型 | 必須 | 備考 |
  |------------|----------|------|------|------|------|
  | ... | ... | ... | ... | ... | ... |

- **Picklist 値一覧**（CHECK 制約のインプットになる）

### API 仕様

Apex REST コントローラーから OpenAPI 仕様のドラフトを生成：

- エンドポイント一覧（HTTP メソッド、パス、概要）
- リクエスト/レスポンスの型定義
- ステータス遷移ルール（ある場合）
- バリデーションルール

---

## 1-3. 移行影響分析レポート（20分）

`templates/migration-assessment-prompt.md` を使い、以下を生成：

### コンポーネント別 移行難易度スコアリング

| コンポーネント | 種別 | 行数 | SFDC依存度 | 難易度 | 移行パターン |
|-------------|------|------|-----------|--------|------------|
| `XxxController` | REST | 〜200 | 低 | S | FastAPI REST API |
| `XxxTrigger` | Trigger | 〜100 | 中 | M | Pub/Sub + Cloud Run Worker |
| `XxxBatch` | Batch | 〜300 | 中 | M | Cloud Run Jobs |
| `XxxFlow` | Flow | — | 高 | L | Workflows / 要再設計 |

### SFDC プラットフォーム依存のマッピング

| SFDC 依存 | 出現箇所 | 移行先パターン | 難易度 |
|-----------|---------|---------------|--------|
| `UserInfo.getUserId()` | Controller 系 | 認証基盤（IAP / Firebase Auth） | M |
| `Database.DMLOptions` | Service 系 | SQLAlchemy トランザクション | S |
| `System.schedule()` | Batch 系 | Cloud Scheduler | S |
| `Messaging.SingleEmailMessage` | Trigger 系 | SendGrid / Cloud Tasks | M |
| `ApexPages.addMessage()` | VF Controller | FastAPI HTTPException | S |

---

## 1-4. レビュー＆ディスカッション（20分）

> [!IMPORTANT]
> AI が生成した設計書は**出発点**です。人間にしか分からないビジネスコンテキストを補完するのがこのフェーズの目的。

### 議論ポイント

1. **AI の出力に誤りや漏れはないか？**
   - クラスの責務の解釈は正しいか？
   - ER 図のリレーションは正しいか？

2. **暗黙知の補完**
   - コードに現れない業務ルール（例: 「月末は集計処理が重い」）
   - コードに現れない運用要件（例: 「この画面は毎朝100人が同時アクセスする」）

3. **PoC 対象の再確認**
   - 影響分析の結果を踏まえて、Step 0 で選んだ PoC 対象は妥当か？
   - 難易度が S or M のコンポーネントが PoC に適している

### 成果物の確定

```bash
# 生成された設計書を確認
ls -la workshop-real/01-reverse-engineering/output/

# Git にコミット
git add workshop-real/01-reverse-engineering/output/
git commit -m "Step 1: AI による設計ドキュメント逆起こし完了"
```

---

## ⏭️ 次のステップ

Step 1 で生成した以下を、Step 2 以降で利用します：

| 成果物 | 利用先 |
|--------|--------|
| ER 図 + フィールド定義 | → Step 2: DDL 変換のインプット |
| API 仕様書 | → Step 3: テストシナリオのインプット |
| 移行影響分析 | → Step 5: ロードマップのインプット |
