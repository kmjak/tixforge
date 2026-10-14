# GitHub：チケットの変更を issue に書き戻す

`GT-` のチケットを edit で書き換えたときに読む。

- 書き換えた直後に `bash <scripts>/issue-sync.sh push <番号> .tixforge/<ticket-id>/ticket.md` を行う。終了コードが 0 以外なら、下のとおりに扱う。
- **終了コード 5**（このコピーを取ってきた後に issue が更新された＝他の人が edit した可能性）：書き戻さない。他の人の変更を消さないよう、次の順で当て直す：
  1. `bash <scripts>/issue-sync.sh pull <番号> <ファイル> --dry-run` で、issue の最新との差分を示す。
  2. 自分の変更（合意した差分）を控える（`pull` は手元のファイルを issue の内容で上書きするため）。
  3. `bash <scripts>/issue-sync.sh pull <番号> <ファイル>` で取ってき直す。
  4. 控えた変更を当て直し、全文と差分を示してもう一度合意を得てから push する。
- **終了コード 4**（編集中に GitHub 上で直接編集された）：`bash <scripts>/issue-sync.sh pull <番号> <ファイル> --accept-edited --dry-run` で差分を示し、取り込むか尋ねる。
  - 取り込むなら、自分の変更を控えてから `pull <番号> <ファイル> --accept-edited` で取り込み、変更を当て直して合意を得てから `bash <scripts>/issue-sync.sh push <番号> <ファイル> --force` で書き戻す（`--accept-edited` は手元を作り直すだけで issue のハッシュは古いままなので、`--force` なしでは同じ理由で止まる）。
  - 取り込まないなら止まる（直接編集した人に確認する）。
- **終了コード 3**（issue の本文から tixforge の目印が消えている）：`fetch.md` の `no-markers` と同じく、issue の本文を示し、「手元の内容で issue を上書きする（`push … --force`。目印とハッシュも戻り、issue の今の本文は消える）」「止める」を尋ねる。
- 他の終了コード（gh の失敗など）なら、出力を示して止まる。
- 手元から issue の本文を書き換えるのは、この手順（チケットを書き換えたとき）だけにする。
