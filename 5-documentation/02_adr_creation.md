# アーキテクチャ決定レコード (Architecture Decision Record - ADR) の作成

ADR は「なぜその技術的決定を下したのか」を記録するための軽量なドキュメントフォーマットです。モダナイゼーションでは多くの意思決定（ツールの選定、アーキテクチャの変更など）が行われるため、ADR の作成を強く推奨します。

## Gemini を用いた ADR の起草

ゼロから ADR を記述するのは手間がかかるため、議論のメモや比較検討した資料を Gemini に入力し、ADR のフォーマットに整形させます。

### プロンプト・テンプレート

```markdown
以下のチャット履歴（またはミーティングのメモ）をもとに、Architecture Decision Record (ADR) を Markdown 形式で作成してください。

フォーマット要件:
1. タイトル (Title)
2. ステータス (Status: 提案中 / 承認済み など)
3. コンテキストと問題提起 (Context)
4. 決定事項 (Decision)
5. 決定の理由 (Rationale / consequences)
   - 選ばなかった代替案 (Alternatives considered) とその理由も含めること。

【インプット（メモ）】
- 現状: SFDCのデータモデルをRDBに移行するにあたり、データベースエンジンの選定が必要。
- 検討案: 1. Cloud SQL for PostgreSQL, 2. Cloud SQL for MySQL, 3. Cloud Spanner
- 決定案: Cloud SQL for PostgreSQL。理由は、SFDCの複雑なデータ型（JSON、配列など）や分析クエリに対する親和性が高く、`pgloader` などのオープンソース移行ツールが充実しているため。Spannerは初期段階ではオーバースペックと判断。
```

## ADR 管理のベストプラクティス

1. **リポジトリでの一元管理:** `docs/architecture/` のようなディレクトリを切り、コードと一緒にバージョン管理します。
2. **連番のファイル名:** `adr-001-use-cloud-run-for-batch.md` のようにプレフィックスに番号をつけ、時系列で把握しやすくします。
3. **不可逆な記録:** 一度承認された ADR を書き換えるのではなく、決定が覆った場合は「新しい ADR を追加し、古いものを Deprecated にする」という運用を行います。

## 記入済みサンプル

実際の移行プロジェクトにおける ADR の記入例を用意しています。

- [ADR 001: データベースエンジンの選定 (Cloud SQL for PostgreSQL)](docs/architecture/adr-001-database-engine-selection.md)
  - Cloud SQL / AlloyDB / Spanner の3つの選択肢を比較し、コスト効率・PostgreSQL 互換性・運用経験の観点から Cloud SQL を選定した ADR です。
  - 新しい ADR を書く際の参考にしてください。

