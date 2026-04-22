"""
SFDC スキーマメタデータ (JSON) から PostgreSQL DDL を自動生成するスクリプト。

Google Gen AI SDK (google-genai) を使用し、Vertex AI 上の Gemini モデルを呼び出します。
"""

import os
import sys
from google import genai

# ---- 設定 -----
# GCP プロジェクトとリージョンを指定
# 環境変数 GOOGLE_CLOUD_PROJECT が未設定の場合はデフォルト値を使用
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "your-project-id")
REGION = os.environ.get("GOOGLE_CLOUD_LOCATION", "global")
MODEL_ID = os.environ.get("GEMINI_MODEL", "gemini-3.1-pro-preview")

# Vertex AI バックエンドを使用して Client を初期化
# 環境変数 GOOGLE_GENAI_USE_VERTEXAI=1 を設定するか、
# ここで vertexai=True を明示指定することで Vertex AI 経由で呼び出します。
client = genai.Client(
    vertexai=True,
    project=PROJECT_ID,
    location=REGION,
)


def generate_ddl_from_sfdc(sfdc_schema_json: str) -> str:
    """SFDC スキーマ JSON を受け取り、Gemini で PostgreSQL DDL を生成して返す。"""
    prompt = f"""\
あなたは Google Cloud の Data Architect です。
以下のSFDCスキーマメタデータ(JSON)を読み取り、PostgreSQL用のDDLに変換してください。

【PostgreSQLのベストプラクティス】
- SFDCの `Id` を主キーとして保持するため `VARCHAR(18) PRIMARY KEY` と定義すること。
- データ型をPostgreSQLの標準仕様(VARCHAR, NUMERIC, BOOLEAN, TIMESTAMPなど)に沿って適切に設定すること。
- オブジェクト間のリレーションシップを解釈し、外部キー制約(`FOREIGN KEY`)を付与すること。
- 実装の意図がわかるように各カラムにCOMMENT文を付与すること。
- テーブル名はスネークケース（小文字 + アンダースコア）に変換すること。
- SFDC のカスタムオブジェクト名の末尾 `__c` は除去し、適切な名前に正規化すること。

生成するDDLのSQLコードブロックのみを出力してください。

スキーマ:
{sfdc_schema_json}
"""

    print(f"Gemini API ({MODEL_ID}) へリクエストを送信しています...")
    try:
        response = client.models.generate_content(
            model=MODEL_ID,
            contents=prompt,
        )
        return response.text
    except Exception as e:
        print(f"エラー: Gemini API の呼び出しに失敗しました: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    schema_file = "sample_sfdc_schema.json"

    # スキーマファイルの読み込み
    try:
        with open(schema_file, "r", encoding="utf-8") as f:
            sfdc_data = f.read()
    except FileNotFoundError:
        print(f"エラー: {schema_file} が見つかりません。")
        sys.exit(1)

    ddl_output = generate_ddl_from_sfdc(sfdc_data)

    print("\n--- 生成されたDDL ---")
    print(ddl_output)

    # 生成出力をファイルに保存
    output_file = "output_generated.sql"
    with open(output_file, "w", encoding="utf-8") as f:
        f.write(ddl_output)
    print(f"\n{output_file} に結果を保存しました。")
