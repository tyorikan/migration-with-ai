Step 3 Phase 1: Apex ソースコードからテストシナリオを抽出

## 入力（自動参照）
- Apex ソースコード: `force-app/main/default/classes/*.cls`
- Apex トリガー: `force-app/main/default/triggers/*.trigger`
- Apex テストクラス: `force-app/main/default/classes/*Test.cls`（存在する場合）
- Step 1 の API 仕様: `workshop-real/01-reverse-engineering/output/system_overview.md`

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
`workshop-real/03-code-modernization/output/TEST_SCENARIOS.md`
