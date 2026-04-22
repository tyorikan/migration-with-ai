# 03. CI テスト統合 (CI Test Integration)

テストを「書く」だけでなく、「自動で実行し続ける」仕組みを Google Cloud 上で構築します。

## 1. Google Cloud Build での実行
Cloud Build を使うと、リポジトリへのプッシュをトリガーにコンテナ上でテストを走らせることができます。

### 設定例 (cloudbuild.yaml)
```yaml
steps:
  # 1. Unit Test の実行
  - name: 'golang:1.26'
    id: 'run-unit-tests'
    entrypoint: 'go'
    args: ['test', './...', '-v']

  # 2. 脆弱性スキャン (オプション)
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Running security checks..."

  # 3. ビルドとデプロイ (テストが成功した場合のみ実行される)
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/$PROJECT_ID/my-app', '.']
```

## 2. 統合テスト用の環境変数
Secret Manager を活用して、テスト用のデータベース接続情報を安全に渡す構成にします。

```yaml
  - name: 'golang:1.26'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        export DB_PASSWORD=$_DB_PASSWORD
        go test ./integration/...
    secretEnv: ['_DB_PASSWORD']

availableSecrets:
  secretManager:
    - versionName: projects/$PROJECT_ID/secrets/test-db-password/versions/latest
      env: '_DB_PASSWORD'
```

## 3. Testcontainers を使った統合テスト

CI 環境でも Cloud SQL への接続なしに PostgreSQL の統合テストを実行できます。
[Testcontainers for Go](https://golang.testcontainers.org/) を使うと、テスト実行時に使い捨ての PostgreSQL コンテナが自動起動されます。

### Cloud Build での実行

```yaml
  # Testcontainers 用: Docker-in-Docker を有効化
  - name: 'golang:1.23'
    id: 'run-integration-tests'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        export TESTCONTAINERS_RYUK_DISABLED=true
        export DOCKER_HOST=unix:///var/run/docker.sock
        go test -v -tags=integration ./integration/...
    volumes:
      - name: 'docker-socket'
        path: '/var/run/docker.sock'
```

### サンプルコード

- [`sample/integration_test.go`](sample/integration_test.go) — Account CRUD、FK 制約の ON DELETE SET NULL 検証、1000 件バルクインサートのパフォーマンステスト

## 4. テスト結果の可視化
`go tool cover` などを使用してカバレッジを出力し、Cloud Storage にホスティングすることで、チーム全員が品質状況を確認できるようにします。

### スクリプト例
```bash
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
gsutil cp coverage.html gs://my-project-test-reports/
```

## 5. ワークショップの課題
1.  `cloudbuild.yaml` にテスト実行ステップを追加してみましょう。
2.  意図的にテストを失敗させるコードをプッシュし、デプロイが自動的に止まることを確認しましょう。
3.  `sample/integration_test.go` を参考に、自分の移行対象テーブルの統合テストを書いてみましょう。
