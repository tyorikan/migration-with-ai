# 05. GKE Autopilot へのデプロイ

## 目的
前のステップで Artifact Registry にプッシュしたコンテナイメージを、コンテナオーケストレーションの事実上の標準である **Google Kubernetes Engine (GKE)** にデプロイします。
本ワークショップでは、ノード（VM）の管理が不要で Cloud Run に近い運用感を実現しながらも Kubernetes の完全な API と機能を享受できる **GKE Autopilot** モードを扱います。

## GKE Autopilot の選定基準の復習
- Cloud Run のようなサーバーレスの運用体験を得つつ、複雑なシステムを維持したい。
- デーモンセット、サイドカーコンテナなどを必要とするアーキテクチャである。
- 常時稼働（Always On）の重いバッチや、ゼロスケールさせたてはいけないバックエンド処理が含まれている。
- オンプレミスや他クラウドから、既存の Helm Chart や k8s マニフェストをそのまま移行したい。
- VPA (Vertical Pod Autoscaling), HPA (Horizontal Pod Autoscaling) を細かく制御したい。

---

## 1. GKE Autopilot クラスタの作成と認証

まず、アプリケーションをホストするクラスター（インフラストラクチャ）をデプロイします。Autopilot のためノードプールなどの指定は不要です。

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="asia-northeast1"
export CLUSTER_NAME="migration-workshop-cluster"

# Autopilot クラスタの作成 (数分かかります)
gcloud container clusters create-auto ${CLUSTER_NAME} \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --release-channel="regular"

# クラスタへの認証情報を現状の kubectl コンテキストとして取得
gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION}

# アクセス確認 (ノードが Google によって管理されていることがわかります)
kubectl get nodes
```

## 2. Kubernetes マニフェスト (YAML) の適用

Cloud Run が単一の `gcloud run deploy` コマンドだけでコンテナとネットワークをデプロイするのに対し、GKE ではインフラの状態を YAML 形式の「マニフェスト」で宣言的に記述します。

本ワークショップの `sample/modern_go_sample/k8s` ディレクトリに、基本的な2つのファイルが用意されています。

### 2.1. Deployment (Podの定義)
`k8s/deployment.yaml` に目を通してください。
- `spec.replicas`: 常時起動しておく Pod（コンテナの最小実行単位）の数。
- `image`: Artifact Registry のパス。
- `resources`: Autopilot では CPU と Memory の **requests** （最小要求量）に基づいて Pod のサイズが決まり、それに従ってクラスタが自動的にスケーリング（ノード追加）および課金計算を行います。

### 2.2. Service (ネットワークの定義)
`k8s/service.yaml` に目を通してください。
- クラスター内の Pod （IPが変動する）を束ねて、一意のエンドポイント（Service）を提供します。
- 外部からアクセスするため、一般的には `type: LoadBalancer` や、Ingress オブジェクトと連携させますが、サンプルではシンプルに `LoadBalancer` を使用しています。

### 2.3. デプロイの実行

コマンドでマニフェストをクラスターに適用します。事前に `deployment.yaml` 内のイメージ URI を、自分が AR にプッシュしたパスに修正してください。

```bash
# マニフェストが存在するディレクトリへ移動
cd sample/modern_go_sample/k8s

# （エディタ等で deployment.yaml の image を編集）
# 例: asia-northeast1-docker.pkg.dev/[PROJECT_ID]/migration-workshop-repo/app-modern-go:v1.0.0

# マニフェストの適用
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# 適用状況の確認
kubectl get pods -w
```
Pod が `Pending` から `Running` になったら起動成功です。

## 3. 動作確認

```bash
# Service (LoadBalancer) の外部IPアドレスを取得
kubectl get service app-modern-go-service
```
`EXTERNAL-IP` が `pending` からIPアドレス（例: 104.198.xxx.xxx）に変わったら、curl でアクセスしてみましょう。

```bash
curl http://[EXTERNAL-IP]:8080/api/convert
```
これで、Gemini 移行後の Go アプリケーションが GKE Autopilot 上で稼働していることが完了です。

## 4. Workload Identity の設定 (ベストプラクティス)

Cloud Run でシークレットや他の Google Cloud API (Cloud SQLなど) にアクセスする際に IAM セキュリティを組んだように、GKE でも強いセキュリティが求められます。
Kubernetes 上の Pod に Google Cloud IAM 権限を渡すための最適な方法が **Workload Identity** です。
キーファイルを Pod に埋め込むことは絶対に避けてください。

1. Google Cloud サービスアカウント (GSA) の作成
2. Kubernetes サービスアカウント (KSA) の作成
3. GSA と KSA を紐付ける（バインディング）
4. Pod (deployment.yaml) に KSA を指定する。

> 詳細は、ハンズオンの中で Workload Identity を利用した Cloud SQL プロキシへの接続や、Secret Manager 連携を行う際に解説・構築します（4-infra-pipeline 編でもTerraform でこれを定義します）。

---

👉 デプロイ手段としての Cloud Run / GKE への流れが完了しました。次に、インフラ自体のコード化とパイプラインの構築に進みます: [4-infra-pipeline](../4-infra-pipeline)
