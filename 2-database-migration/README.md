# 2. データベース移行 (Database Migration)

本フェーズでは、現在 Salesforce (SFDC) 上で稼働しているデータモデルおよびデータを、Google Cloud のフルマネージドデータベース（Cloud SQL または AlloyDB for PostgreSQL）へ移行するための戦略・設計・検証を実施します。

## ゴール
- SFDC のオブジェクトモデルを PostgreSQL クラスターのスキーマ（DDL）へ変換する。
- AI（Gemini）を活用し、自動でのスキーマ定義生成や SOQL から SQL へのクエリ変換を検証する。
- データの抽出と初期ロード、および検証手順を確立する。

## 進め方フロー

```
┌──────────────────┐
│ 01_migration_    │  DB 選定（Cloud SQL or AlloyDB）・移行方式の決定
│ strategy.md      │  アウトプット: 選定結果、移行対象オブジェクト一覧
└────────┬─────────┘
         ▼
┌──────────────────┐
│ 02_schema_       │  SFDC オブジェクト→PostgreSQL テーブルの型マッピング設計
│ design.md        │  アウトプット: データ型マッピング表、命名規則、ER 図（概要）
└────────┬─────────┘
         ▼
┌──────────────────┐
│ 03_ai_conversion │  Gemini を使って DDL を自動生成 & SOQL→SQL 変換
│ _guide.md        │  アウトプット: 生成済み DDL (.sql)、変換後の SQL クエリ
└────────┬─────────┘
         ▼
┌──────────────────┐
│ 04_data_export_  │  SFDC からの CSV 抽出・Cloud SQL へのロード・検証
│ and_load.md      │  アウトプット: ロード済みデータ、検証チェックリスト（全項目 ☑）
└────────┬─────────┘
         ▼
┌──────────────────┐
│ scripts/         │  DDL 生成スクリプト・サンプルデータ
│ README.md        │  アウトプット: output_generated.sql
└──────────────────┘
```

## 目次

| # | ドキュメント | 内容 | 主なアウトプット |
| :--- | :--- | :--- | :--- |
| 1 | [移行戦略とデータベース選定](01_migration_strategy.md) | Cloud SQL / AlloyDB の比較・選定、移行方式決定 | DB 選定結果、gcloud 作成コマンド |
| 2 | [スキーマ設計とマッピング](02_schema_design.md) | データ型マッピング、リレーション設計、インデックス戦略 | マッピング表、DDL 設計方針 |
| 3 | [AI を活用したスキーマ変換・SQL 生成](03_ai_conversion_guide.md) | Gemini による DDL 自動生成、SOQL→SQL 変換ガイド | プロンプトテンプレート、生成 DDL |
| 4 | [データ移行手順とロード戦略](04_data_export_and_load.md) | データ抽出・変換・ロード・検証の実作業手順 | CSV データ、検証チェックリスト |
| 5 | [ハンズオン・検証用スクリプト](scripts/README.md) | DDL 生成 Python スクリプト | output_generated.sql |

## 前提条件
- `1-onboarding` フェーズにて、Google Cloud プロジェクトがセットアップ済みであること。
- 対象となる SFDC のオブジェクト定義（Account, Contact など）の要件を把握していること。
- （ハンズオン検証用）Cloud SQL または AlloyDB インスタンスが準備されている、または作成する権限があること。
- Python 3.10+ がインストール済みであること（スクリプト実行用）。
