Step 1: ソースコードからの設計ドキュメント逆起こし

以下の SFDX プロジェクトのソースコードを分析し、設計ドキュメントを生成してください。

# SFDX ソースディレクトリ
`$ARGUMENTS`

引数が空の場合は `./examples` をデフォルトとして使用してください。
以下、`<SOURCE>` は指定されたディレクトリを指します。

# 事前成果物の参照（Phase 0）

**`/project:discover-source` を先に実行済みの場合**、以下のファイルをインプットとして参照してください:
- `01-reverse-engineering/output/source_tree.md` — ディレクトリ Tree + ファイル一覧
- `01-reverse-engineering/output/knowledge_catalog.md` — ナレッジ抽出カタログ（SFDC 依存 API + パターン）

**未実行の場合**は、自分で `<SOURCE>` を再帰的に走査してください。

# 分析対象ファイル

`source_tree.md` のファイル一覧に基づき、以下を **再帰的に** 読み込んでください。
固定パスではなく、実際のディレクトリ構造に沿って探索してください。

1. Apex クラス: `**/*.cls`（テストクラスを含む）
2. Apex トリガー: `**/*.trigger`
3. カスタムオブジェクト: `**/*.object-meta.xml`
4. カスタムフィールド: `**/fields/*.field-meta.xml`
5. Visualforce: `**/*.page`（存在する場合）
6. LWC: `**/lwc/*/`（存在する場合）
7. フロー: `**/*.flow-meta.xml`（存在する場合）

# 生成すべきドキュメント（すべて1ファイルにまとめて出力）

## 1. システム概要書
- クラス責務一覧テーブル: | クラス名 | 種別(REST/Service/Trigger/Batch/Test/Util) | 責務 | 依存先 | 行数 |
- ビジネスロジックフロー図（Mermaid `flowchart TD`）
- クラス間依存関係図（Mermaid `graph LR`）— Controller → Service → Repository のレイヤーが見えるように
- 外部連携一覧: | 連携先 | 方式 | 該当クラス | 備考 |

## 2. データモデル仕様書
- ER 図（Mermaid `erDiagram`）— Lookup / Master-Detail のリレーション + 各フィールド
- フィールド定義一覧: | オブジェクト | フィールド名 | API名 | 型 | 長さ | 必須 | デフォルト | 備考 |
- Picklist 値一覧: | オブジェクト | フィールド名 | 選択肢 |
- バリデーションルール一覧（コード中から抽出）: | オブジェクト | ルール | 条件 | エラーメッセージ |

## 3. API 仕様書
- REST エンドポイント一覧: | HTTPメソッド | パス | 概要 | リクエスト例 | レスポンス例 | Apex メソッド |
- ステータス遷移図（Mermaid `stateDiagram-v2`）— 存在する場合

## 4. Apex テスト仕様の抽出（テストクラスが存在する場合）
- テストケース一覧: | テストメソッド | テスト対象 | 検証内容（assert） | ビジネスルール |
  ※ assert の内容は移行先 Python の pytest テストシナリオの基礎になる

# 出力ルール
- Markdown 形式、日本語で記述
- Mermaid 図を積極的に使用
- 出力先: `workshop-real/01-reverse-engineering/output/system_overview.md`

# セルフレビュー
生成後、以下を自己検証してください:
- 漏れているクラスはないか？
- 依存関係の方向は正しいか？
- ER 図のリレーション（Lookup/Master-Detail）は XML 定義と整合しているか？
- ビジネスフロー図は Apex のロジックと整合しているか？
修正が必要な場合は自動修正してください。
