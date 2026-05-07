Step 3 Phase 1: Apex ソースコードからテストシナリオを抽出

## SFDX ソースディレクトリ
`$ARGUMENTS`

引数が空の場合は `./examples` をデフォルトとして使用してください。
以下、`<SOURCE>` は指定されたディレクトリを指します。

## 入力（自動参照）

### 主入力（Step 1 の成果物）
- Code Wiki: `01-reverse-engineering/output/wiki/classes/`（メソッド一覧・依存関係・ビジネスルール）
- 統合設計書: `01-reverse-engineering/output/system_overview.md`（API 仕様・テストケース一覧）

### 補足入力（Wiki に assert 詳細が不足している場合のみ）
- Apex テストクラス: `<SOURCE>/force-app/main/default/classes/*Test.cls`
- Apex ソースコード: `<SOURCE>/force-app/main/default/classes/*.cls`
- Apex トリガー: `<SOURCE>/force-app/main/default/triggers/*.trigger`

> [!NOTE]
> Step 1 の Wiki にテストメソッド一覧と assert が十分記載されている場合は、生の Apex を再読みする必要はありません。
> assert の具体的な値（期待値・引数）が Wiki に不足している場合のみ、補足入力として参照してください。

## 指示
**テストシナリオの一覧だけ**を出力してください。コードの変換や実装は行わないでください。

## 抽出すべきテストシナリオ
1. 各 REST エンドポイント（`@HttpGet`/`@HttpPost`/`@HttpPatch`/`@HttpDelete`）の正常系
2. 各エンドポイントの異常系（バリデーションエラー、存在しないID、権限不足等）
3. ビジネスルール（ステータス遷移、計算ロジック、条件分岐）
4. Trigger の副作用（レコード更新、子レコード連動）
5. Batch の入出力仕様
6. 境界値（数値の上限/下限、空文字列、NULL）
7. CASCADE 削除の動作
8. **Apex テストクラスの assert から抽出した期待動作**（テストクラスが存在する場合）

## 出力形式
| # | カテゴリ | シナリオ | 期待結果 | 元の Apex コード箇所 | Apex テストの assert（あれば） |

## 出力先
`03-code-modernization/output/TEST_SCENARIOS.md`
