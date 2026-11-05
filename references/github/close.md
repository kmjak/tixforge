# GitHub：チケットを閉じる

- 操作したら、スクリプトが出力した一行をユーザーに伝える。
- ラベルが無いというエラーなら、`/tixforge:project init` の再実行（`issue-label.sh setup`）でラベルを作れることを伝える。

## 完了（PR がマージされたとき）

- Base が GitHub の default branch → issue がまだ開いていれば `gh issue close <番号> --comment "Closed by tixforge: <PR URL> merged"`。`bash <scripts>/issue-label.sh <番号> done`。
- Base が default branch 以外：
  - `.tixforge/config.yml` の `repository.close_issues` が `release` → `bash <scripts>/issue-label.sh <番号> merged`。issue は閉じない（リリースで、最初の commit の `Closes` により GitHub が閉じる。Actions の `tixforge-issue-sync` があれば、そのとき `tixforge:done` に付け替わる）。
  - `merge`（既定）→ 上の default branch と同じく閉じて `done`。
- Actions の `tixforge-issue-sync` を入れていれば、同じ付け替えはマージの時点で済んでいる。スクリプトの出力が `unchanged` 相当でも問題ない。

## キャンセル（cancel）

- 確認一覧には「issue を削除せずに閉じる（予定なし）。`tixforge:canceled` にする」と載せる（`closed-not-planned` のときは「`tixforge:canceled` にする」だけ）。
- issue を **削除せずに** `gh issue close <番号> --reason "not planned" --comment "Canceled by tixforge: <理由>"` で閉じ、`bash <scripts>/issue-label.sh <番号> canceled` を実行する。
- チケットの状態が `closed-not-planned`（手で閉じられた）のときは、閉じる操作を省き、`issue-label.sh <番号> canceled` だけを行う。
- 手元のコピーには書き足さない（キャンセル済みかどうかは issue が表す）。
