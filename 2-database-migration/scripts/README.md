# DDL Generator Scripts

このディレクトリには、SFDC のメタデータを入力として受け取り、Google Gen AI SDK (`google-genai`) 経由で Gemini API を呼び出し、PostgreSQL の DDL を自動生成する評価用のサンプル Python スクリプトが含まれています。

## ファイル構成
| ファイル | 説明 |
| :--- | :--- |
| `gemini_ddl_generator.py` | Gemini に SFDC スキーマ JSON を渡して DDL を生成するメインスクリプト |
| `sample_sfdc_schema.json` | Account / Contact オブジェクト風のダミーメタデータ JSON |
| `requirements.txt` | スクリプト実行に必要な Python ライブラリ（`google-genai`, `pydantic`） |
| `output_generated.sql` | スクリプト実行後に生成される DDL（実行時に自動作成） |

## セットアップ手順

### 1. 仮想環境の作成とアクティベート (推奨)
```bash
python3 -m venv venv
source venv/bin/activate
```

### 2. 依存ライブラリのインストール
```bash
pip install -r requirements.txt
```

### 3. Google Cloud 認証の設定
Application Default Credentials (ADC) を設定します。
```bash
gcloud auth application-default login
```

### 4. 環境変数の設定 (任意)
スクリプトは以下の環境変数を参照します。未設定の場合はデフォルト値が使用されます。

| 環境変数 | 説明 | デフォルト値 |
| :--- | :--- | :--- |
| `GOOGLE_CLOUD_PROJECT` | GCP プロジェクト ID | `your-project-id` |
| `GOOGLE_CLOUD_LOCATION` | Vertex AI のリージョン | `global` |
| `GEMINI_MODEL` | 使用する Gemini モデル名 | `gemini-3.1-pro-preview` |

```bash
export GOOGLE_CLOUD_PROJECT="your-project-id"
export GOOGLE_CLOUD_LOCATION="global"
```

### 5. 実行
```bash
python gemini_ddl_generator.py
```

成功すると、生成された DDL がコンソールに表示され、`output_generated.sql` に保存されます。

## カスタマイズ
- **自社の SFDC スキーマを使う場合:** `sample_sfdc_schema.json` を自社のメタデータ JSON に差し替えるか、スクリプトの `schema_file` 変数を変更してください。
- **プロンプトの調整:** `generate_ddl_from_sfdc()` 関数内のプロンプトを編集して、自社のポリシー（命名規則、インデックス戦略など）に合わせたルールを追加できます。
