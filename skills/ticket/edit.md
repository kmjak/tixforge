# /tixforge:ticket edit — チケットの編集

目的：既存のチケットの内容を、ユーザーとの対話で書き換える。進行中の dev の run があれば、変更の影響に合わせてフェーズを戻す。

1. **準備**：引数のチケット id を `bash <scripts>/ticket-id.sh normalize <引数>` で正規化する（無ければ尋ねる。開いている `tixforge:*` の issue を候補として示す）。`references/github/fetch.md` と `references/github/sync.md` を Read する。
2. **チケットを読む**：
   - `fetch.md` の手順で issue から手元のコピーを作り直してから読む（issue が正本。GitHub 上で直接編集されていたら、そこで取り込むか尋ねる）。取り込んだ変更は、「フェーズを戻す」の影響判断に含める。
   - 読んだら「`<ticket-id>`：<タイトル>」を示す（取り違えの防止）。
   - **編集しないで止まる場合**：`.tixforge/<ticket-id>/state.md` の `Status` が `done` か `canceled`／`closed_as` が `open` 以外（完了・キャンセル済み・手で閉じられた）／`labels` に `tixforge:merged` がある（Base にマージ済みでリリース待ち。issue は開いている）。完了・中止した内容を書き換えると、実装や記録と食い違うため。変えたいことがあるなら、新しいチケットを `/tixforge:ticket create` で作るよう勧める。
   - `labels` に `tixforge:in-review` がある（PR が出ている）なら、そのことを示し、編集を続けるか尋ねる。
3. **対話で決める**：今の内容を示し、何を変えたいかを尋ねる。create の「対話で埋める」と同じ決まりで対話する：**中身はユーザーが書く**（Claude が案を出すのは「考えて」と頼まれたときだけ）、**要件を捏造しない**、決まらない点は「未決事項」に残す、必要なら `docs/context/**` やコードを読んで質問を具体的にする。Base を変えるなら `## Base` の節を足す・直す・消す（既定に戻すなら節ごと消す）。
   - 追加がチケットの範囲を大きく広げる（別の機能・別の受け入れ条件の塊になる）なら、このチケットに足さず、別のチケットに分けることを提案する。
4. 変更後の全文と差分を示して合意を得る。issue のタイトル・本文がどう変わるかも示す。
5. **書き換える**：チケットを書き換え、すぐに `bash <scripts>/issue-sync.sh push <番号> .tixforge/<ticket-id>/ticket.md` で issue に書き戻す（終了コードが 0 以外なら `sync.md` のとおりに扱う）。
6. **フェーズを戻す**：進行中の run がある場合（`.tixforge/<ticket-id>/state.md` があり、`Status` が `done`・`canceled` 以外）は、`<plugin>/skills/dev/rewind.md` を Read し、その「チケットが変わったとき」の手順でフェーズを戻すか決める。
7. 行ったことと issue の URL を伝える。
8. **commit はしない**（チケットは git で管理しない）。
