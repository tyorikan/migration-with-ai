# Step 0: 事前準備＆キックオフ

## 🎯 ゴール

参加者全員が同じコンテキストを持ち、ワークショップを開始できる状態にする。

---

## 📋 事前準備チェックリスト

### お客様側（ワークショップ前日まで）

- [ ] **ソースコードの共有**
  - SFDX プロジェクト形式でソースコードを export
    ```bash
    sf project retrieve start --metadata ApexClass ApexTrigger CustomObject CustomField
    ```
  - Git リポジトリに push（ワークショップ用ブランチ推奨）

- [ ] **主要カスタムオブジェクトの一覧**（名前だけでOK）
  - 例: `DailyReport__c`, `CounselingRecord__c`, `StoreVisit__c` ...

- [ ] **実データのエクスポート**（Step 2 のデータ移行で使用）
  - 移行対象オブジェクトの CSV をエクスポートしておく
  - **方法A: sf CLI（推奨 — 手軽で高速）**
    ```bash
    # 対象オブジェクトごとに SOQL で CSV エクスポート
    sf data query --query "SELECT Id, Name, StoreCode__c, StoreName__c, Region__c, Address__c, Phone__c, IsActive__c FROM Store__c" --result-format csv > data/Store__c.csv
    sf data query --query "SELECT Id, Name, Store__c, VisitDate__c, Status__c, Purpose__c, Summary__c, NextAction__c, Rating__c, Visitor__c, CreatedDate, LastModifiedDate FROM StoreVisit__c" --result-format csv > data/StoreVisit__c.csv
    sf data query --query "SELECT Id, Name, StoreVisit__c, Category__c, Description__c, DueDate__c, IsCompleted__c, Priority__c FROM VisitDetail__c" --result-format csv > data/VisitDetail__c.csv
    ```
  - **方法B: Data Loader（大量データ向け — 数万件以上）**
    - Salesforce Data Loader を使用し、対象オブジェクトを CSV でエクスポート
    - 各オブジェクトのフィールドは全選択（漏れ防止）
  - **方法C: レポートエクスポート（非技術者向け — 最も簡単）**
    - Salesforce のレポート機能でカスタムレポートを作成し、「エクスポート」→「CSV」
  - エクスポートした CSV は `data/` フォルダにまとめて Git にコミット
    ```
    data/
    ├── Store__c.csv
    ├── StoreVisit__c.csv
    ├── VisitDetail__c.csv
    └── MonthlyVisitSummary__c.csv  （あれば）
    ```

  > [!TIP]
  > CSV のエンコーディングは **UTF-8** にしてください。
  > Data Loader のデフォルトは Shift-JIS の場合があるので注意。

- [ ] **Claude Code の動作確認**
  ```bash
  # Vertex AI 接続の確認
  claude --version
  claude /model  # Claude Opus が選択可能か確認
  ```

- [ ] **Docker / docker-compose の準備**
  ```bash
  docker --version    # Docker 24+ 推奨
  docker compose version  # Compose V2
  ```

### Google 側（ワークショップ前日まで）

- [ ] お客様のソースコードを事前に受領し、構造を把握
- [ ] Vertex AI プロジェクトのセットアップ確認
- [ ] `workshop-real/` リポジトリの最新化
- [ ] docker-compose の動作確認（PostgreSQL 起動テスト）

---

## 🎤 当日の Step 0（10:00 – 10:30）

### 1. ワークショップのゴール合意（10分）

> 🧠 **マインドセット転換**
>
> 「設計書がないから移行できない」ではなく、「**ソースコードこそが唯一の真実**」。
> AI に設計を逆起こしさせ、TDD で品質を保証し、1日で移行パスを明確にする。

| 項目 | 従来アプローチ | 今日のアプローチ |
|------|--------------|----------------|
| **設計書** | ベンダーに依頼して待つ | 🤖 AI がソースコードから逆起こし |
| **コード変換** | 人間が手動で書き直す | 🤖 AI が変換、人間はレビュー |
| **テスト** | 変換後に手動で書く | 🤖 TDD: テストを先に書いてから実装 |
| **品質保証** | シニアレビュアーが目視 | 🤖 AI セルフレビュー + docker-compose 検証 |

### 2. SFDC アプリの概要説明（5分）

お客様から口頭で：
- このアプリは**何をするもの**か？（ビジネスコンテキスト）
- **誰が使う**のか？（ユーザーペルソナ）
- **特に重要な機能**は？

### 3. ソースコード構造の確認（10分）

```bash
# Apex クラスの数
find force-app -name "*.cls" | wc -l

# Apex トリガーの数
find force-app -name "*.trigger" | wc -l

# カスタムオブジェクトの数
find force-app -name "*.object-meta.xml" | wc -l

# ファイル一覧をざっと確認
find force-app -name "*.cls" -o -name "*.trigger" | sort
```

### 4. PoC 対象コンポーネントの選定（5分）

以下の基準で、**代表1コンポーネント**を選ぶ：

| 基準 | 説明 |
|------|------|
| ✅ **ビジネスインパクト** | 移行後に実際に使われるもの |
| ✅ **適度な複雑さ** | 複雑すぎず、シンプルすぎない（CRUD + バリデーション程度） |
| ✅ **自己完結性** | 外部 API 連携が少なく、単体で動作確認できる |
| ❌ **避けるべき** | 外部システム連携が多い / バッチ処理のみ / UI だけ |

→ **選定結果**: `________________`（ここにワークショップ当日記入）

### 5. docker-compose 環境の起動確認（残り時間）

```bash
cd workshop-real

# PostgreSQL の起動確認
docker compose up -d db

# 接続テスト
docker compose exec db psql -U app_user -d migration_db -c "SELECT version();"
# 期待結果: PostgreSQL 16.x

# 準備完了！
echo "✅ 環境準備完了。Step 1 に進みましょう！"
```
