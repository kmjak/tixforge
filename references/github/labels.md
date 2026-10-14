# GitHub：状態ラベルと担当者

`GT-` のチケットで、状態が変わるときに読む。issue には状態ラベルが常に 1 つだけ付く（`bash <scripts>/issue-label.sh` が他を外す）。`tixforge:out-of-sync` は状態ではないので残る。

| 時点 | コマンド | ラベル |
|------|----------|--------|
| create | （`issue-sync.sh create` が付ける） | `tixforge:todo` |
| dev の開始（状態ファイルを新しく作るとき） | `bash <scripts>/issue-label.sh <番号> start` | `tixforge:in-progress`、assignee に自分 |
| PR の作成 | `bash <scripts>/issue-label.sh <番号> review` | `tixforge:in-review` |
| Base にマージ（Base が GitHub の default branch でなく、`repository.close_issues: release`） | `bash <scripts>/issue-label.sh <番号> merged` | `tixforge:merged`（リリースで閉じるまで開いたまま） |
| 完了（マージで閉じた・リリースで閉じた） | `bash <scripts>/issue-label.sh <番号> done` | `tixforge:done` |
| cancel | `bash <scripts>/issue-label.sh <番号> canceled` | `tixforge:canceled` |
| チケットを手放す | `bash <scripts>/issue-label.sh <番号> reset` | `tixforge:todo`、assignee から自分を外す |

- `start` が終了コード 4（他の人が assign されている）なら止まり、そのまま進めるか尋ねる（進めるなら `--force`）。終了コード 3（閉じている）なら止まって尋ねる（勝手に開き直さない）。
- ラベルが無いというエラーなら、`/tixforge:project init` の再実行（`issue-label.sh setup`）でラベルを作れることを伝える。
- 操作したら、スクリプトが出力した一行をユーザーに伝える。
