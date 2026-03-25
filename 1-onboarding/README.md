# 1. オンボーディング (Onboarding) フェーズ 資料

本ディレクトリは、「Migration with AI: SFDC to Google Cloud」ワークショップの第1フェーズである「オンボーディング」に必要な資料とスクリプトをまとめています。

お客様と Google エンジニアがスムーズにコラボレーションを開始できるよう、Google Cloud の基礎知識から検証環境の立ち上げ、および生成 AI ツールの使い方について定義しています。

## 📁 ディレクトリ内の資料一覧

1. [**01_gcp_fundamentals.md**](./01_gcp_fundamentals.md)
   - Google Cloud の基礎知識、リソース階層、IAM。
   - ワークショップで利用する主要サービス (Compute, DB, AI, Analytics) の概要。

2. [**02_prerequisites.md**](./02_prerequisites.md)
   - ワークショップ参加者に求める事前準備（アカウントとローカルツール群）。
   - `gcloud`, `terraform`, `git`, VS Code などの導入ガイダンス。

3. [**03_environment_setup.md**](./03_environment_setup.md)
   - 検証用環境の構築手順マニュアル。
   - 必要な API の有効化と、基本的なネットワーク (VPC) の作成手順。

4. [**04_gemini_usage_guide.md**](./04_gemini_usage_guide.md)
   - Gemini for Google Cloud (コンソール) および Gemini Code Assist (IDE) の使い方。
   - 移行やモダナイゼーションにおける効果的なプロンプトエンジニアリングの基本。

5. [**check_env.sh**](./check_env.sh)
   - 参加者のローカル環境に、必要なツール群が正しくインストール・設定されているかを自動診断する実用スクリプト。

## ワークショップの進め方
このフェーズでは、参加者の方々が**「自信を持って Google Cloud 上での検証作業を開始できる状態」**になることを目指します。不明点があれば、随時コンソールの Gemini に質問しながら学習を深めるよう推奨してください。
