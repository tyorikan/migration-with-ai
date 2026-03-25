---
name: workshop-documentation
description: Automatically generate comprehensive architecture design documents and migration guides using Gemini. Use when the user needs to create system documentation, update Architecture Decision Records (ADR), or document migration steps.
---
# ドキュメント作成 (Documentation) スキル

このスキルは、Google Cloud環境およびモダナイズされたアプリケーション構成について、手動でのドキュメント作成負荷を下げるため、Geminiを活用して設計書や移行ドキュメント（ADR等）を自動生成するための支援を行います。

## 自動生成の利点と活用方法
*   **Infrastructure as Code (IaC) からの逆生成**: Terraformの構成ファイル群をGeminiに読み込ませることで、現在のインフラアーキテクチャ概要をMarkdownやMermaid記法で出力させることができます。
*   **コードからの仕様書生成**: モダナイズされたGoやPythonのコードから、不要な実装詳細を省いたAPI設計書（OpenAPI/Swagger等）のドラフトを生成します。

## プロンプトによるドキュメント生成例

### Mermaidによるインフラ構成図の生成
```markdown
以下のTerraformのソースコード（main.tf 等）を分析し、Google Cloudのインフラストラクチャー構成をMermaid記法のグラフで表現してください。
出力形式は以下の通りとします。
1. アーキテクチャの概要説明
2. Mermaidブロック (```mermaid ... ```)

【Terraformコード】
(ここにコードを挿入)
```

### ADR (Architecture Decision Record) の作成サポート
モダナイゼーションの過程で、「なぜCloud Runを選んだのか」「なぜそのデータベース構成にしたのか」という決定事項をドキュメント化します。

```markdown
以下のチャット履歴とインフラ構成を元に、ADR (Architecture Decision Record) を以下のフォーマットで作成してください。
- Title: 
- Status: 
- Context: (現在の課題と背景)
- Decision: (Google Cloudでの解決策)
- Consequences: (この決定による利点とトレードオフ)
```

## 継続的ドキュメンテーション (Continuous Documentation)
ドキュメントが陳腐化しないように、CIパイプライン（Cloud BuildやGitHub Actions）にドキュメント生成ステップ（Gemini APIなどのLLMを呼び出すスクリプトの実装）を組み込むアイデアをお客様と議論し、ドキュメントの鮮度を保つベストプラクティスを共有してください。
