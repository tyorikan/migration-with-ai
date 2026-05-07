# 01. アーキテクチャの再設計

## 背景と課題
Salesforce (SFDC) 上の Apex コードなどは、データベースと密結合しており、プラットフォームに依存したステートフルな処理や特殊なトランザクション管理を行っているケースが多く見られます。
これをそのままモダンなクラウドネイティブアーキテクチャに「1対1の機械的な翻訳」で移行しようとすると、後々スケーラビリティやテスト容易性の面で大きな負債を抱えることになります。

## SFDC コンポーネント → Google Cloud マッピング

SFDC 上の各コンポーネントが、Google Cloud 上のどのサービスに対応するかを理解することが、再設計の第一歩です。

### ビジネスロジック層

| SFDC コンポーネント | 役割 | Google Cloud 移行先 | 補足 |
|---|---|---|---|
| **Apex Class** (Service / Controller) | ビジネスロジック、REST API | **Cloud Run** サービス / **GKE** Pod | Go, Python, TypeScript 等で再実装 |
| **Apex Trigger** | レコード変更時の自動処理 | **Eventarc** + Cloud Run / **Pub/Sub** + Cloud Run | イベント駆動アーキテクチャへ変換 |
| **Batch Apex** | 大量レコードのバッチ処理 | **Cloud Run Jobs** / **Cloud Tasks** + Cloud Run | スケジュール実行は Cloud Scheduler と連携 |
| **Scheduled Apex** | 定期実行ジョブ | **Cloud Scheduler** → Cloud Run Jobs | cron 式でジョブをスケジューリング |
| **Queueable Apex** | 非同期処理チェーン | **Cloud Tasks** / **Pub/Sub** | メッセージキューで非同期処理を実現 |
| **Platform Event** | イベント駆動メッセージング | **Pub/Sub** | フルマネージドなメッセージングサービス |
| **Apex REST / SOAP** | 外部向け API | **Cloud Run** + Cloud Endpoints / **Apigee** | API Gateway でセキュリティ・レート制限を管理 |

### UI / フロントエンド層

| SFDC コンポーネント | 役割 | Google Cloud 移行先 | 補足 |
|---|---|---|---|
| **Visualforce Page** | サーバーサイドレンダリング UI | **SPA** (React/Vue) + **Cloud Run** BFF | BFF パターンで API を提供 |
| **Lightning Web Component (LWC)** | モダン UI コンポーネント | **SPA** (React/Vue/Angular) | Firebase Hosting or Cloud Run で配信 |
| **Aura Component** | レガシー UI コンポーネント | **SPA** (React/Vue/Angular) | LWC 同様にモダンフレームワークへ |

### データ・設定層

| SFDC コンポーネント | 役割 | Google Cloud 移行先 | 補足 |
|---|---|---|---|
| **SOQL / SOSL** | データクエリ | **SQL** (Cloud SQL / Spanner) | 2-database-migration で詳細をカバー |
| **Custom Settings** | アプリ設定値 | **Secret Manager** / **Firestore** | 機密情報は Secret Manager、その他は Firestore |
| **Custom Metadata Type** | メタデータ定義 | **Firestore** / 設定ファイル (YAML) | デプロイ時に読み込む設定として管理 |
| **Custom Object** | データモデル | **Cloud SQL** / **Spanner** テーブル | 2-database-migration で詳細をカバー |
| **File / Attachment / ContentDocument** | ファイルストレージ | **Cloud Storage** | バケットポリシーで権限管理 |

### インフラ・連携層

| SFDC コンポーネント | 役割 | Google Cloud 移行先 | 補足 |
|---|---|---|---|
| **Flow / Process Builder** | ノーコードワークフロー | **Workflows** / **Eventarc** | 宣言的なワークフロー定義 |
| **Outbound Message** | 外部システム通知 | **Pub/Sub** → Cloud Run | Webhook パターンで再実装 |
| **Named Credential** | 外部認証情報 | **Secret Manager** | サービスアカウント + Secret Manager |
| **Connected App (OAuth)** | SSO / API 認可 | **Identity Platform** / **IAP** | Google Identity で認証基盤を構築 |

## ステートレス化へのパラダイムシフト

Cloud Run や GKE などのモダンなコンテナ基盤でアプリケーションを水平スケール（オートスケール）させるためには、アプリケーション自体を **ステートレス (Stateless)** に維持することが重要です。

### SFDC ではなぜ意識しなくて済んだか
SFDC プラットフォームでは、ViewState（Visualforce）やプラットフォームキャッシュ、静的変数などを通じて状態管理がプラットフォーム側で暗黙的に行われていました。クラウドネイティブ環境ではこれを **明示的に設計** する必要があります。

### 具体的な設計パターン

| 状態の種類 | SFDC での管理方法 | GCP での推奨パターン |
|---|---|---|
| セッション情報 | ViewState / プラットフォームキャッシュ | **Memorystore (Redis)** に外部化 |
| 一時データ | 静的変数 / Apex トランザクション | **Cloud SQL** / **Firestore** に永続化 |
| ファイル | ContentDocument | **Cloud Storage** に保存 |
| ジョブ進捗 | BatchableContext | **Firestore** / 専用テーブルで管理 |

### 冪等性 (Idempotency) 設計
コンテナは任意のタイミングでスケールイン/アウトされるため、**同じリクエストが複数回実行されても同じ結果になる**設計が必要です。

```
✅ 良い例: INSERT ... ON CONFLICT DO UPDATE (Upsert パターン)
❌ 悪い例: 呼び出すたびにカウンターをインクリメント
```

## クリーンアーキテクチャの導入

ビジネスの要件（ドメインロジック）と、技術的詳細（フレームワーク、UI、データベース接続）を分離することが、将来の変化に強いシステムを作ります。

### 推奨ディレクトリ構成（Go の場合）

```
my-modern-app/
├── cmd/
│   └── server/
│       └── main.go           # エントリーポイント (Frameworks & Drivers)
├── internal/
│   ├── domain/               # Entities: ビジネスルール
│   │   └── account.go        #   - 構造体、バリデーション
│   ├── usecase/              # Use Cases: アプリケーションロジック
│   │   └── account_service.go#   - ビジネスロジックの実装
│   ├── adapter/              # Interface Adapters: 変換層
│   │   ├── handler/          #   - HTTP ハンドラ (REST API)
│   │   └── repository/       #   - DB アクセス (Cloud SQL / Spanner)
│   └── infra/                # Frameworks & Drivers: 技術詳細
│       ├── database.go       #   - DB 接続設定
│       └── config.go         #   - 環境変数の読み込み
├── Dockerfile
├── go.mod
└── go.sum
```

### 各レイヤーの責務

1. **Entities / Domain**: ビジネスルールの中心。外部に一切依存しない。AI が最も得意とする論理的な変換対象。
2. **Use Cases**: アプリケーション固有のビジネスロジック。Repository インターフェースに依存する（実装には依存しない）。
3. **Interface Adapters**: REST API のハンドラや、DB を操作する Gateway/Repository 実装。
4. **Frameworks & Drivers**: Web フレームワーク (Go の `net/http` や `gin`、Python の `FastAPI` 等) や DB クライアント。

## 移行先判定チェックリスト

アーキテクチャ再設計の最後に、各ワークロードの移行先を判定します。

```markdown
# ワークロード判定シート

## 対象機能名: ________________

- [ ] HTTP リクエスト駆動のステートレスな処理である → Cloud Run 候補
- [ ] 定期実行のバッチ処理である → Cloud Run Jobs + Cloud Scheduler 候補
- [ ] 常時起動が必要（WebSocket / 長時間接続） → GKE Autopilot 候補
- [ ] Pod 間通信やサービスメッシュが必要 → GKE Autopilot 候補
- [ ] GPU / TPU が必要 → GKE Autopilot 候補
- [ ] gRPC / TCP / UDP プロトコルを使用 → GKE Autopilot 候補
- [ ] 複数コンテナの密結合（Sidecar）が必要 → GKE Autopilot 候補
- [ ] ゼロスケール（トラフィックなし時にインスタンス0）が望ましい → Cloud Run 候補
```

> **ヒント:** 判定に迷う場合は、まず Cloud Run で始めて、要件が合わなくなった時点で GKE Autopilot に移行するのが推奨パターンです。コンテナイメージは同じものを使えるため、移行コストは低く抑えられます。

👉 次のステップ: [02. AI 駆動でのコード変換](./02_ai_code_conversion.md)
