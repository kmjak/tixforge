# /tixforge:ticket edit — チケットの編集

目的：既存のチケットの内容を、ユーザーとの対話で書き換える。進行中の dev の run があれば、変更の影響に合わせてフェーズを戻す。

1. **準備**：`references/github/fetch.md` と `references/github/sync.md` を Read する。引数のチケット id を `bash <scripts>/ticket-id.sh normalize <引数>` で正規化する（無ければ尋ねる。「探す」の開いているチケットを候補として示す）。
2. **チケットを読む**：
   - `fetch.md` の手順で、issue から `.tixforge/<ticket-id>/editing.md` に取ってきて読む（issue が正本。GitHub 上で直接編集されていたら、そこで取り込むか尋ねる）。取り込んだ変更は、「フェーズを戻す」の影響判断に含める。
   - ただし `editing.md` が既にあれば（前の edit が書き戻す前に止まった）、`fetch.md` の「編集の続き」を行う。「続きとして使う」なら取ってこずに、下の確認（タイトルを示す・止まる場合・`in-review`）を行ってから手順 3 へ進む。
   - 読んだら「`<ticket-id>`：<タイトル>」を示す（取り違えの防止）。
   - **編集しないで止まる場合**：`.tixforge/<ticket-id>/state.md` の `Status` が `done` か `canceled`／チケットの状態が `open`・`in-review` 以外（完了・キャンセル済み・手で閉じられた・`merged`＝Base にマージ済みでリリース待ち）。完了・中止した内容を書き換えると、実装や記録と食い違うため。変えたいことがあるなら、新しいチケットを `/tixforge:ticket create` で作るよう勧める。
   - 状態が `in-review`（PR が出ている）なら、そのことを示し、編集を続けるか尋ねる。
3. **対話で決める**：今の内容を示し、何を変えたいかを尋ねる。create の「対話で埋める」と同じ決まりで対話する：**中身はユーザーが書く**（Claude が案を出すのは「考えて」と頼まれたときだけ）、**要件を捏造しない**、決まらない点は「未決事項」に残す、必要なら `docs/context/**` やコードを読んで質問を具体的にする。Base を変えるなら `## Base` の節を足す・直す・消す（既定に戻すなら節ごと消す）。
   - 追加がチケットの範囲を大きく広げる（別の機能・別の受け入れ条件の塊になる）なら、このチケットに足さず、別のチケットに分けることを提案する。
4. 変更後の全文と差分を示して合意を得る。issue のタイトル・本文がどう変わるかも示す。
5. **書き換える**：`editing.md` を書き換え、すぐに「書き戻す」（`sync.md`）を行う。書き戻せたら、`editing.md` と `.editing.md.hash` を消す。`.tixforge/<ticket-id>/snapshot.md` か v2 の `ticket.md` があれば、続けて `fetch.md` の手順 2 と 4 で `snapshot.md` に取ってくる（`<ファイル>` は `snapshot.md`。`base: changed` なら手順 4 のとおり尋ねる。出た差分は手順 6 の判断に含め、dev では尋ね直さない）。書き換える前に止まるとき（手順 2 で止まる・手順 4 で合意しない）は `editing.md` と `.editing.md.hash` を消す。書き換えた後、書き戻す前に止まるとき（「続き」で手順 4 に合意しなかったときを含む）は、残すか尋ねる（残せば次の edit で続きに使える）。
6. **フェーズを戻す**：進行中の run がある場合（`.tixforge/<ticket-id>/state.md` があり、`Status` が `done`・`canceled` 以外）は、`<plugin>/skills/dev/rewind.md` を Read し、その「チケットが変わったとき」の手順でフェーズを戻すか決める。
7. 行ったことと issue の URL を伝える。
8. **commit はしない**（チケットは git で管理しない）。
