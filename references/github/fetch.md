# GitHub：チケットを取ってくる・探す

「取ってくる」：dev・edit・cancel を始めるときと、dev の PR 作成の直前に行う。issue が正本で、手元のファイル（以下 `<ファイル>`）は issue から作るコピー（git 管理外）。手元と issue が違えば、常に issue を採用する。`<ファイル>` は、dev は `.tixforge/<ticket-id>/snapshot.md`、edit は `.tixforge/<ticket-id>/editing.md`。cancel は手順 1〜3 だけを行い、手元のファイルは作らない。呼び出し元には、チケットの状態（`check` の `status:`）と担当者（`assignees:`）、変わったかを返す。

1. **事前チェック**：`bash <scripts>/github-preflight.sh`。`ok:` 以外なら、出力をそのまま示して止まる（`gh auth login` は対話式なので、ユーザーに `! gh auth login` を実行してもらう）。
2. **状況を見る**：`bash <scripts>/issue-sync.sh check <番号> <ファイル>`（cancel はファイルを渡さない）。1 行目が同期の判定、以降に `status`・`local`・`assignees` など。
3. **閉じたチケット**（`status` が `open`・`in-review`・`merged` 以外）：取ってこずに、状態を呼び出し元に返す。
   - `completed` — 呼び出し元の「完了済み」の扱いに従う。
   - `canceled` — その旨を伝えて止まる（どのサブコマンドでも操作しない）。
   - `closed-completed`・`closed-not-planned`・`closed` — tixforge 以外の方法で閉じられた（手で閉じたなど）。呼び出し元に扱いがあればそれに従う。無ければ状況（`state_reason`・`labels`）を示して止まり、どうするか尋ねる。勝手に開き直さない。`closed-not-planned` なら、`/tixforge:ticket cancel` でキャンセルとして記録し直せることを添える。
4. **判定ごとに取ってくる**（開いているチケット）。dev（`snapshot.md`）で `check` の `base` が `changed`（手元に書き戻していない変更がある）なら、取ってくる前に差分を示し、「書き戻す」（`sync.md`）か「捨てる」（そのまま取ってくる）かを尋ねる。`snapshot.md` が無く v2 の `ticket.md` があるときも同じく、差分を示して「移して取ってくる」か「止める」かを尋ねる。edit（`editing.md`）は下の「編集の続き」に従う。差分は `pull … --dry-run` で出す（判定が `edited` なら `--accept-edited --dry-run`、`no-markers` なら下の `no-markers` の扱いに従う）。
   - **`in-sync`・`no-hash`** → `bash <scripts>/issue-sync.sh pull <番号> <ファイル>`。出力の `moved:` の行（v2 のコピーを移した知らせ）は判定に含めない。それ以外の出力が `unchanged`・`created` 以外なら、何が変わったかを一行で伝え、呼び出し元に「変更あり」として返す（進行中の run があれば、呼び出し元が `<plugin>/skills/dev/rewind.md`「チケットが変わったとき」でフェーズを戻すか判断する）。
   - **`edited`**（GitHub 上で直接編集された）→ `bash <scripts>/issue-sync.sh pull <番号> <ファイル> --accept-edited --dry-run` の差分を示し、AskUserQuestion で尋ねる：
     - **取り込む（推奨）** — `bash <scripts>/issue-sync.sh pull <番号> <ファイル> --accept-edited` で手元を作り直し、`bash <scripts>/issue-sync.sh push <番号> <ファイル> --force` でハッシュを付け直す（`tixforge:out-of-sync` も外れる）。以降は「変更あり」として扱う。
     - **直接編集を取り消す** — `check` の `local` が `same` のとき**だけ**出す（手元のコピーが tixforge が最後に書いた版と同じ＝最新の正しい版）。`bash <scripts>/issue-sync.sh push <番号> <ファイル> --force` で手元の内容に戻す。`differs`・`missing` のときは、手元が古い可能性があるので出さない。
     - **止める** — 何もせずに止める（直接編集した人に確認する）。
   - **`no-markers`**（tixforge の目印が無い）→ 取り込まない。本文を示し、次のどちらかを尋ねる：
     - `local` が `same` なら「手元の内容で issue を上書きする（`push --force`。目印とハッシュも戻る）」／「止める」。
     - それ以外（GitHub 上で作られた issue など）なら、`/tixforge:ticket create #<番号>` で tixforge のチケットとして取り込めることを伝えて止まる。
5. 手元のファイルは commit しない。

## 編集の続き（edit）

`editing.md` が取ってくる前から既にあれば、前の edit が書き戻す前に止まったもの。手順 3 まで（状況を見る）を済ませた後、手順 4 の代わりに `check <番号> .tixforge/<ticket-id>/editing.md` の `base`・`remote` で分ける：

- **`base: none`**（ハッシュが無い。adopt の途中で止まったなど）— 中身を示し、「捨てる」か「止める」かを尋ねる（ハッシュが無いと、書き戻すときに他の人の変更とのぶつかりを検出できないため、続きには使わない）。
- **`base: same`**（変えていない）— 尋ねずに捨てる。
- **`base: changed`・`remote: same`**（前の edit の変更があり、その後 issue は変わっていない）— `pull … --dry-run` の差分（＝前の edit の変更）を示し、「続きとして使う」「捨てる」を尋ねる。
- **`base: changed`・`remote: changed`**（前の edit の変更の後に、issue も変わった。GitHub 上での直接編集を含む）— 差分には前の edit の変更と他の人の変更が混ざり、見分けられない。`editing.md` の中身を示し、捨てて取り直すよう勧める（前の変更は、取り直した後に手で当て直す）。「捨てる」「止める」を尋ねる。

- **続きとして使う** — 取ってこない。edit の手順 4 では、issue との差分全体（前の edit の変更を含む）を示す。
- **捨てる** — `editing.md` と `.editing.md.hash` を消してから、手順 4 で取ってくる。

## 探す

- **着手できるチケット**（dev の候補）：`gh issue list --state open --label tixforge:todo --limit 100 --json number,title`。
- **開いているチケット**（edit の候補）：`gh issue list --state open --limit 100 --json number,title,labels` のうち、`tixforge:` で始まるラベルがあるもの。
- **似たチケット**（create）：`gh issue list --state open --search "<タイトルの語> in:title" --limit 100 --json number,title`。
- 番号は `bash <scripts>/ticket-id.sh normalize '#<番号>'` で id にして示す。
