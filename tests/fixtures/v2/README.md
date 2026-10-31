# v2 のデータ

tixforge v2 が利用者のリポジトリに残したものの見本。plugin を v3 に上げても、これらは書き換わらない。`tests/scripts.test.sh` の「v2 data」で使う。中身は v2.2.0 の書き方のまま変えない（変えるとテストの意味が無くなる）。

| ファイル | 中身 | 確かめること |
|---|---|---|
| `state-implement.md` | Implement の途中の run。`Format` の行が無い（形式 2）。まだ書いていないセクションと、書いたセクションの上に初期文言（HTML コメント）が残る | `run-state.sh migrate` で形式 3 になる |
| `issue-closed.json`・`issue-closed-sync.json`・`issue-canceled.json` | 英語のコメント（`Closed by tixforge`・`Closed by tixforge-issue-sync`・`Canceled by tixforge: `）で閉じた issue。ラベルは外してある | `issue-sync.sh check` の `closed_as`。GitHub のコメントは移行できないので、読み続ける |

v3 が出てしばらくして v2 の run が残っていないと言えるようになったら（v4 の頃）、`migrate` の形式 2 の段と一緒に消す。
