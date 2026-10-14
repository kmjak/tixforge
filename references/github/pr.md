# GitHub：PR と issue の紐付け・クローズ

`GT-` のチケットで、dev の Implement（最初の commit）と PR フェーズで読む。

## commit と PR 本文

- **最初の commit のメッセージに `Closes #<番号>` のトレーラーを入れる**（本文の最後の行）。Base が GitHub の default branch でない運用（develop など）では、PR 本文の `Closes` が効かない。commit メッセージの `Closes` は、その commit が default branch に入ったとき（リリース）に issue を閉じる。
- **PR 本文の末尾に `Closes #<番号>` を必ず入れる**（下書きを示す時点で入っていること）。guard hook は、これが無い PR 作成をブロックする。
- PR を作成したら `bash <scripts>/issue-label.sh <番号> review`。

## 紐付けの確認

- Base が default branch なら、`gh pr view <PR> --json closingIssuesReferences` にその番号が含まれることを確かめる。含まれなければ本文を直して（`gh pr edit`）もう一度確かめる。
- Base が default branch 以外なら、本文に `Closes #<番号>` があることだけ確かめる（GitHub はこの PR では紐付けない）。

## マージされたとき（`pr-status.sh` が `merged`）

- Base が default branch → issue がまだ開いていれば `gh issue close <番号> --comment "Closed by tixforge: <PR URL> merged"`。`bash <scripts>/issue-label.sh <番号> done`。
- Base が default branch 以外：
  - `.tixforge/config.yml` の `repository.close_issues` が `release` → `bash <scripts>/issue-label.sh <番号> merged`。issue は閉じない（リリースで、最初の commit の `Closes` により GitHub が閉じる。Actions の `tixforge-issue-sync` があれば、そのとき `tixforge:done` に付け替わる）。
  - `merge`（既定）→ 上の default branch と同じく閉じて `done`。
- Actions の `tixforge-issue-sync` を入れていれば、同じ付け替えはマージの時点で済んでいる。スクリプトの出力が `unchanged` 相当でも問題ない。
