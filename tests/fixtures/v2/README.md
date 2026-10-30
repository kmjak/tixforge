# v2 のデータ

tixforge v2 が利用者のリポジトリに残したものの見本。v3 に上げても、v2 で始めた run を続けられることを `tests/scripts.test.sh` と `tests/guard.test.sh` の「v2 data」で確かめる。中身は v2.2.0 の書き方のまま変えない（変えるとテストの意味が無くなる）。

| ファイル | 中身 |
|---|---|
| `state-plan.md` | Plan のゲートで止まった run（`plan:awaiting-approval`、Branch はまだ無い）。後のセクションに初期文言（HTML コメント）が残る |
| `state-implement.md` | Implement の途中の run（`implement:in-progress`、Base は develop）。書いたセクションの上にも初期文言が残る |
| `state-done.md` | 完了した run（`done`） |
| `config-merge.yml`・`config-release.yml` | `repository.close_issues` のある config |
| `issue-closed.json`・`issue-closed-sync.json`・`issue-canceled.json` | 英語のコメント（`Closed by tixforge`・`Closed by tixforge-issue-sync`・`Canceled by tixforge: `）で閉じた issue。ラベルは無い（手で外された場合） |
