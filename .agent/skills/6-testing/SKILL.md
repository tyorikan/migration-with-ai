---
name: workshop-testing
description: Generate automated test code and build testing environments for modernized applications. Use when the user requests unit tests, integration tests, CI test integrations, or wants to verify application code correctness.
---
# テスト (Testing) スキル

このスキルは、継続的な運用に不可欠な「テストコード」の自動生成と、CIパイプライン上での自動テスト環境の構築を支援します。特に、モダナイズされた新しいアプリケーションに対する単体テスト(Unit Test)や結合テスト(Integration Test)のアプローチに焦点を当てます。

## テスト戦略のベストプラクティス
1. **テストピラミッドの意識**
   - 実行が早く安価なUnit Testを厚くし、外部依存のある結合テストやE2Eテストは重要なパスに絞る戦略をお客様に伝えます。
2. **モック (Mock) と スタブ (Stub) の活用**
   - Cloud Spanner や Pub/Sub などの Google Cloud サービスに依存する部分は、インターフェースを切ってモック化し、ローカルで実際のDB無しでもテストが回る設計（クリーンアーキテクチャ等）を推奨します。
3. **Spanner エミュレータの活用**
   - 結合テストが必要な場合は、Google Cloudが提供する Spanner Emulator コンテナをテスト実行時に立ち上げて使用するアプローチも有用です。

## AI(Gemini)を活用したテストコード自動生成
実装済みのビジネスロジックに対して、エッジケースを網羅するテストコードをGeminiに生成させます。

### テストコード生成のプロンプト例
```markdown
以下のGo言語の関数（ビジネスロジック）に対するテーブルドリブンテスト(Table-Driven Tests)の実装コードを生成してください。
要件:
- 標準の `testing` パッケージを使用すること
- 正常系、異常系、境界値のテストケースを網羅すること
- DBへのアクセスレイヤーは、提供されているインターフェースをモック化して利用する想定で書くこと

【対象コード】
(ここにコードを挿入)
```

## CI/CD 連携の手引き
テストコードが完成したら、`cloudbuild.yaml` や GitHub Actions にテスト実行ステップを組み込みます。

### Cloud Build でのテスト組み込み例
```yaml
steps:
  # テスト実行
  - name: 'golang:1.26'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        # モジュールダウンロードとテスト実行
        go mod download
        go test -v -cover ./...
```
テストカバレッジが一定ラインを超えないとビルド（後続のデプロイ）が失敗するような「品質ゲート (Quality Gate)」の概念をお客様に説明し、信頼性の高い開発フローへの移行を目指すよう支援してください。
