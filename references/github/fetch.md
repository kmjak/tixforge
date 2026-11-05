# GitHub：チケットを取ってくる・探す

「取ってくる」：dev・edit・cancel を始めるときと、dev の PR 作成の直前に行う。issue が正本で、手元の `.tixforge/<ticket-id>/ticket.md` は issue から作る作業用のコピー（git 管理外）。手元と issue が違えば、常に issue を採用する。呼び出し元には、チケットの状態（`check` の `status:`）と担当者（`assignees:`）、変わったかを返す。

1. **事前チェック**：`bash <scripts>/github-preflight.sh`。`ok:` 以外なら、出力をそのまま示して止まる（`gh auth login` は対話式なので、ユーザーに `! gh auth login` を実行してもらう）。
2. **状況を見る**：`bash <scripts>/issue-sync.sh check <番号> .tixforge/<ticket-id>/ticket.md`。1 行目が同期の判定、以降に `status`・`local`・`assignees` など。
3. **閉じたチケット**（`status` が `open`・`in-review`・`merged` 以外）：取ってこずに、状態を呼び出し元に返す。
   - `completed` — 呼び出し元の「完了済み」の扱いに従う。
   - `canceled` — その旨を伝えて止まる（どのサブコマンドでも操作しない）。
   - `closed-completed`・`closed-not-planned`・`closed` — tixforge 以外の方法で閉じられた（手で閉じたなど）。呼び出し元に扱いがあればそれに従う。無ければ状況（`state_reason`・`labels`）を示して止まり、どうするか尋ねる。勝手に開き直さない。`closed-not-planned` なら、`/tixforge:ticket cancel` でキャンセルとして記録し直せることを添える。
4. **判定ごとに取ってくる**（開いているチケット）：
   - **`in-sync`・`no-hash`** → `bash <scripts>/issue-sync.sh pull <番号> .tixforge/<ticket-id>/ticket.md`。出力が `unchanged`・`created` 以外なら、何が変わったかを一行で伝え、呼び出し元に「変更あり」として返す（進行中の run があれば、呼び出し元が `<plugin>/skills/dev/rewind.md`「チケットが変わったとき」でフェーズを戻すか判断する）。
   - **`edited`**（GitHub 上で直接編集された）→ `bash <scripts>/issue-sync.sh pull <番号> <ファイル> --accept-edited --dry-run` の差分を示し、AskUserQuestion で尋ねる：
     - **取り込む（推奨）** — `bash <scripts>/issue-sync.sh pull <番号> <ファイル> --accept-edited` で手元を作り直し、`bash <scripts>/issue-sync.sh push <番号> <ファイル> --force` でハッシュを付け直す（`tixforge:out-of-sync` も外れる）。以降は「変更あり」として扱う。
     - **直接編集を取り消す** — `check` の `local` が `same` のとき**だけ**出す（手元のコピーが tixforge が最後に書いた版と同じ＝最新の正しい版）。`bash <scripts>/issue-sync.sh push <番号> <ファイル> --force` で手元の内容に戻す。`differs`・`missing` のときは、手元が古い可能性があるので出さない。
     - **止める** — 何もせずに止める（直接編集した人に確認する）。
   - **`no-markers`**（tixforge の目印が無い）→ 取り込まない。本文を示し、次のどちらかを尋ねる：
     - `local` が `same` なら「手元の内容で issue を上書きする（`push --force`。目印とハッシュも戻る）」／「止める」。
     - それ以外（GitHub 上で作られた issue など）なら、`/tixforge:ticket create #<番号>` で tixforge のチケットとして取り込めることを伝えて止まる。
5. 手元のコピーは commit しない。

## 探す

- **着手できるチケット**（dev の候補）：`gh issue list --state open --label tixforge:todo --json number,title`。
- **開いているチケット**（edit の候補）：`gh issue list --state open --json number,title,labels` のうち、`tixforge:` で始まるラベルがあるもの。
- **似たチケット**（create）：`gh issue list --state open --search "<タイトルの語> in:title" --json number,title`。
- 番号は `bash <scripts>/ticket-id.sh normalize '#<番号>'` で id にして示す。
