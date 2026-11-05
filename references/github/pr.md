# GitHub：PR と issue の紐付け

dev の Implement（最初の commit）と PR フェーズで読む。

## commit と PR 本文

- **最初の commit のメッセージに `Closes #<番号>` のトレーラーを入れる**（本文の最後の行）。Base が GitHub の default branch でない運用（develop など）では、PR 本文の `Closes` が効かない。commit メッセージの `Closes` は、その commit が default branch に入ったとき（リリース）に issue を閉じる。
- **PR 本文の末尾に `Closes #<番号>` を必ず入れる**（下書きを示す時点で入っていること）。guard hook は、これが無い PR 作成をブロックする。

## 紐付けの確認

- Base が default branch なら、`gh pr view <PR> --json closingIssuesReferences` にその番号が含まれることを確かめる。含まれなければ本文を直して（`gh pr edit`）もう一度確かめる。
- Base が default branch 以外なら、本文に `Closes #<番号>` があることだけ確かめる（GitHub はこの PR では紐付けない）。
