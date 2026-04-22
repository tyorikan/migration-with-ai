# 01. 移行戦略とデータベース選定

本ドキュメントでは、SFDC から Google Cloud のデータベースへの移行アプローチおよび製品選定の指針について解説します。

## 0. 移行の全体フロー

SFDC から Google Cloud への DB 移行は、以下の 5 つのフェーズで構成されます。各フェーズのドキュメントと成果物を順に進めることで、移行パスが明確になります。

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Phase 1     │───▶│ Phase 2     │───▶│ Phase 3     │───▶│ Phase 4     │───▶│ Phase 5     │
│ 戦略策定    │    │ スキーマ設計 │    │ DDL 生成    │    │ データ移行   │    │ 検証・      │
│ (本ドキュメント)│  │ (02_*.md)   │    │ (03_*.md)   │    │ (04_*.md)   │    │  カットオーバー│
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
  成果物:            成果物:            成果物:            成果物:            成果物:
  ・DB選定結果       ・型マッピング表    ・DDL (.sql)       ・CSV データ       ・件数照合結果
  ・移行方式決定     ・ER図（概要）     ・Gemini プロンプト ・GCS バケット構成  ・整合性チェック結果
```

## 1. データベースの選定 (Cloud SQL vs AlloyDB)

移行先として、PostgreSQL 互換のフルマネージドサービスを選択します。お客様の要件（規模、SLA、パフォーマンス要件など）に基づいて決定します。

| サービス | 特徴とユースケース |
| :--- | :--- |
| **Cloud SQL for PostgreSQL** | ・標準的な PostgreSQL エンジン<br>・運用負担の軽減（自動バックアップ、パッチ適用）<br>・中小〜中規模のトランザクション要件に適している |
| **AlloyDB for PostgreSQL** | ・Google Cloud 独自にストレージ階層を最適化したエンタープライズ向け DB<br>・標準の PostgreSQL との 100% 互換性<br>・トランザクション処理（OLTP）が最大 4 倍高速、分析（OLAP）が最大 100 倍高速<br>・大規模かつミッションクリティカルな要件、ハイブリッド（HTAP）処理に適している |

**推奨:**
ワークショップレベルの検証や中規模アプリであれば **Cloud SQL**、エンタープライズの基幹システムを長期的・大規模にモダナイズする場合は **AlloyDB** を第一候補として推奨します。

### Cloud SQL インスタンスの作成例 (gcloud CLI)

```bash
# Cloud SQL for PostgreSQL インスタンスの作成
gcloud sql instances create sfdc-migration-db \
  --database-version=POSTGRES_17 \
  --tier=db-custom-2-8192 \
  --region=asia-northeast1 \
  --storage-size=20GB \
  --storage-auto-increase \
  --availability-type=ZONAL \
  --project=${GOOGLE_CLOUD_PROJECT}

# データベース作成
gcloud sql databases create sfdc_app \
  --instance=sfdc-migration-db \
  --project=${GOOGLE_CLOUD_PROJECT}

# ユーザー作成
gcloud sql users create app_user \
  --instance=sfdc-migration-db \
  --password=<SECURE_PASSWORD> \
  --project=${GOOGLE_CLOUD_PROJECT}
```

> **Note:** ワークショップでは `db-custom-2-8192` (2vCPU / 8GB RAM) で十分です。本番環境ではワークロードに応じてスケールしてください。

## 2. データ移行アプローチ

SFDC からデータベースへのデータ移行は、業務のダウンタイム許容時間に応じてアプローチを選択します。

### a) 一括エクスポートと初期ロード（ビッグバン移行）
- **概要:** SFDC 側をメンテナンスモードにし、Bulk API 等でデータを一括エクスポート後、Cloud SQL / AlloyDB にインポート。
- **メリット:** 仕組みがシンプルであり、データの不整合が起こりにくい。
- **デメリット:** データ量に応じて長時間のダウンタイムが発生する。
- **適用目安:** 数百万レコード以下、または数時間のメンテナンスウィンドウが許容される場合。

### b) 継続的レプリケーション（段階的移行 / ゼロダウンタイム）
- **概要:** 初期データをロードした後、SFDC 側の変更（CDC: Change Data Capture など）をキャッチし、Pub/Sub や Dataflow などを経由してリアルタイムにターゲット DB へ同期する。
- **メリット:** アプリケーションの切り替え（カットオーバー）時のダウンタイムを極小化できる。
- **デメリット:** 同期パイプラインの開発や監視のコストがかかる。
- **適用目安:** 24/7 稼働要件がある基幹システム、データ量が数千万レコード以上。

**ワークショップでの方針:**
本ワークショップのハンズオンでは、まずは **a) 一括エクスポートと初期ロード** に焦点を当ててスキーマやインポートの検証を行います。必要に応じて、CDCパターンのアーキテクチャディスカッションを実施します。

## 3. 移行対象オブジェクトの棚卸し

移行を開始する前に、SFDC 上のオブジェクトを棚卸しし、移行対象を決定します。

### 棚卸しチェックリスト

| # | 確認項目 | 例 |
| :--- | :--- | :--- |
| 1 | 対象となる標準オブジェクト | Account, Contact, Opportunity, Lead, Case 等 |
| 2 | 対象となるカスタムオブジェクト (`__c`) | Invoice__c, Project__c 等 |
| 3 | 各オブジェクトのレコード件数 | Data Loader の Export で概算取得 |
| 4 | オブジェクト間のリレーション（親子関係） | Account → Contact (Lookup), Account → Opportunity (Master-Detail) |
| 5 | 数式項目・積み上げ集計項目の有無 | RDB では計算ロジックをアプリ層またはビューに移す必要あり |
| 6 | 添付ファイル・コンテンツの有無 | ContentDocument / Attachment → Cloud Storage への移行を検討 |

## 4. 次のステップ
ターゲットとなるデータベースと移行アプローチが決定したら、[スキーマ設計とマッピング (02_schema_design.md)](02_schema_design.md) に進み、SFDC 固有のデータ構造を RDB（PostgreSQL）にどのように落とし込むかを定義します。
