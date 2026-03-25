# 事前準備 (Prerequisites)

ワークショップを円滑に進めるため、参加者の皆様には以下の事前準備をお願いしています。

## 1. アカウント構成と権限

### Google Cloud アカウント
- Google アカウント (Workspaceアカウント または 個人の Gmail 等) を用意してください。
- ワークショップ用の **Google Cloud プロジェクト**へのアクセス権 (通常は `編集者 (Editor)` や各種リソースの `管理者` ロール) が付与されていることを確認してください。
- ※もしご自身でプロジェクトを作成される場合は、**有効な請求先アカウント (Billing Account)** と紐づいている必要があります。

## 2. 開発ツール・CLIのインストール

各ハンズオン作業では、ローカル開発環境（または Cloud Shell）を利用します。以下のツール群がインストールされていることを確認してください。

### ① Google Cloud CLI (`gcloud` コマンド)
Google Cloud のリソースをコマンドラインから操作するための公式ツールです。
- インストール手順: [公式ドキュメント](https://cloud.google.com/sdk/docs/install)
- インストール後、初期化とログインを実行してください：
  ```bash
  gcloud init
  gcloud auth login
  gcloud auth application-default login
  ```

### ② Terraform
Infrastructure as Code (IaC) を実践するためのツールです。
- インストール手順: [HashiCorp 公式](https://developer.hashicorp.com/terraform/downloads) または OSのパッケージマネージャー (Homebrew 等) からインストール
- `terraform -v` でバージョンが表示されることを確認してください。

### ③ Git
ソースコードや構成ファイルのバージョン管理に使用します。
- ターミナルで `git --version` が通れば問題ありません。

### ④ VS Code (Visual Studio Code) などの IDE
Gemini Code Assist プラグインが利用できる統合開発環境を推奨します。
- [VS Code のダウンロード](https://code.visualstudio.com/)

---

## 3. 推奨事項: Cloud Shell の利用
もし社内PCのセキュリティ制限等でローカルへのツールインストールが難しい場合、ブラウザから即座に利用できる無料の管理環境 **Cloud Shell** が利用可能です。
- Cloud コンソールの右上にある「>_ (Cloud Shell をアクティブにする)」アイコンをクリックすることで起動します。
- 上記の `gcloud`、`terraform`、`git` などのツールがあらかじめインストールされています。
