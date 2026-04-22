# プロンプトテンプレート: ソースコードからの設計ドキュメント逆起こし

> **用途**: SFDX プロジェクトのソースコードから、システム概要書・ER図・API仕様書を AI に自動生成させる
> **対象 AI**: Claude Code via Vertex AI

---

## 使い方

Claude Code の対話モードで以下を指示するか、`claude "$(cat templates/reverse-engineering-prompt.md)"` で実行してください。

---

## プロンプト本文

```markdown
# 指示

あなたは Salesforce アプリケーションのリバースエンジニアリングスペシャリストです。
以下の SFDX プロジェクトのソースコードを分析し、**設計ドキュメント**を生成してください。

# 分析対象ファイル

1. Apex クラス: `force-app/main/default/classes/*.cls`
2. Apex トリガー: `force-app/main/default/triggers/*.trigger`
3. カスタムオブジェクト: `force-app/main/default/objects/*/*.object-meta.xml`
4. カスタムフィールド: `force-app/main/default/objects/*/fields/*.field-meta.xml`
5. Visualforce: `force-app/main/default/pages/*.page`（存在する場合）

# 生成すべきドキュメント

## 1. システム概要書

以下をそれぞれ出力してください：

### 1-1. クラス責務一覧テーブル
| クラス名 | 種別(REST/Service/Trigger/Batch/Test/Util) | 責務（1行で要約） | 依存先クラス | 行数 |

### 1-2. ビジネスロジックフロー図
Mermaid `flowchart TD` で、主要なビジネスフローを可視化。
- ユーザーの操作 → API → ビジネスロジック → DB 操作 → 結果返却
- 条件分岐（バリデーション、ステータス遷移）も含める

### 1-3. クラス間依存関係図
Mermaid `graph LR` で、クラス間の呼び出し関係を可視化。
- Controller → Service → Repository のレイヤーが見えるように
- Trigger → Handler のパターンも含める

### 1-4. 外部連携一覧
| 連携先 | 方式 | 該当クラス | 備考 |
（API コールアウト、メール送信、外部 REST 呼び出し等）

## 2. データモデル仕様書

### 2-1. ER 図
Mermaid `erDiagram` で、オブジェクト間のリレーション（Lookup / Master-Detail）を可視化。
各エンティティのフィールドも含める。

### 2-2. フィールド定義一覧
| オブジェクト | フィールド名 | API名 | 型 | 長さ | 必須 | デフォルト | 備考 |

### 2-3. Picklist 値一覧
| オブジェクト | フィールド名 | 選択肢 |

### 2-4. バリデーションルール一覧
| オブジェクト | ルール名 | 条件 | エラーメッセージ |

## 3. API 仕様書

### 3-1. REST エンドポイント一覧
| HTTPメソッド | パス | 概要 | リクエスト例 | レスポンス例 | Apex メソッド |

### 3-2. ステータス遷移図（存在する場合）
Mermaid `stateDiagram-v2` で、ステータス遷移ルールを可視化。

# 出力形式
- Markdown 形式で出力
- Mermaid 図を含める
- 日本語で記述

# 出力先
workshop-real/01-reverse-engineering/output/system_overview.md
```
