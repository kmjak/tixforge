# /tixforge:dev — Phase 6：PR（強ゲート）

目的：明示的な確認の後にだけ PR を出し（`host: none` ではローカルでマージし）、完了まで見届ける。tixforge は PR をマージしない。

`repository.host` が `none` なら、下の「ローカルのみの場合」で進める。それ以外は `host: github` の手順。`GT-` のチケットなら `references/github/pr.md` を Read する。

## 再開（`pr:*` の Status から再開したとき）

- **`pr:in-progress`**：まず PR の有無を確かめる（下記「PR の存在確認」）。
  - PR が無い → 「PR の準備」から。
  - PR がある（開いている）→ PR を出した後の対応（コンフリクト・CI の失敗・修正依頼）の途中。手元のブランチがリモートより進んでいるか（`git fetch origin <ブランチ>` の後、`git rev-list --count origin/<ブランチ>..<ブランチ>`）を確かめる。進んでいれば、push していない修正がある：「PR の状況確認」の対応の最後（検証 → 変更の提示 → 確認 → push）から続ける。進んでいなければ「PR の状況確認」から。
- **`pr:awaiting-approval`**：ゲートを出し直す**前に**、PR が既にあるか確かめる（「PR の存在確認」）。開いている PR があれば、作成の後に中断したということなので、新しく作らずに URL を `## PR` に記録し、`Status: pr:awaiting-review` にして「PR の状況確認」へ。無ければゲートを出し直す。
- **`pr:awaiting-review`・`pr:ready-to-merge`**：「PR の状況確認」から。

## PR の存在確認

`gh pr list --head <ブランチ> --state all --json number,state,url` で探し、次の順に扱う：

1. 開いている（`OPEN`）PR があれば、それがこの run の PR。
2. 無く、マージ済み（`MERGED`）の PR があれば、完了している。URL を `## PR` に記録し、「PR の状況確認」の `merged` の扱いへ。
3. 閉じた（`CLOSED`）PR だけなら、それは使わない（以前に閉じたもの）。PR は無いものとして扱い、閉じた PR があったことだけ伝える。

## PR の準備

1. `Status: pr:in-progress` にする。「PR の存在確認」で PR が無いことを確かめる。
   - 開いている PR があれば（PR を出した後に Implement 以前へ戻した run など）、新しく作らない：その URL を `## PR` に書き、push していない commit（`git fetch origin <ブランチ>` の後、`git log --oneline origin/<ブランチ>..<ブランチ>`）を示して確認を得てから push し、`Status: pr:awaiting-review` にして「PR の状況確認」へ進む。
2. 取り返しのつかない操作の前に、次を提示する：**ブランチ**・**向き先ブランチ**（ヘッダ表の `Base`）・**PR タイトル**・**PR 本文の下書き**（タイトルと本文はドキュメント言語）。
   - **本文**：既定の PR テンプレート（`.github/pull_request_template.md`・`.github/PULL_REQUEST_TEMPLATE.md`・`docs/pull_request_template.md`・ルートの `pull_request_template.md`）があれば、その見出しに沿って埋める。無ければ「概要」「方針」「受け入れ条件（対応表の確かめ方と結果）」「検証」を書く。
   - **方針**は、Approach で合意した**結論と理由を 2〜3 行**だけ書く（検討した選択肢・試行錯誤の経緯は書かない。人のレビュアーに「なぜこうしたか」を伝えるためで、検討過程に引っ張らないため）。
   - **`LT-` のチケット**は PR から見えないので、受け入れ条件を必ず本文に転記する。
   - **`GT-` のチケット**なら、本文の末尾に `Closes #<番号>` を必ず入れる。
3. `Status: pr:awaiting-approval` にして、**停止して明示的な確認を求める。** このゲートは `gates` の設定や前段の自動通過に関係なく必ず発生する。勝手に push / PR しない。
4. 確認されたら：
   - `GT-` なら、push の**直前に** issue からチケットを取り直す（`references/github/fetch.md`）。変更があったら、PR を作らずに停止し、`<plugin>/skills/dev/rewind.md` の「チケットが変わったとき」で戻すか尋ねる（実装が変更後のチケットを満たしているとは限らないため）。
   - `Status` は `pr:awaiting-approval` のまま push して PR を作成する（例：`gh pr create --base <Base> --body-file <一時ファイル>`。`--fill` は使わず本文を明示する）。guard hook により、push・PR 作成のたびにユーザーの確認画面が出る。**確認画面で拒否されたら、言い換えて再実行せず、停止して指示を待つ**（共通規約のガードレール）。
   - `GT-` なら、作成後に `references/github/pr.md`「紐付けの確認」を行い、`bash <scripts>/issue-label.sh <番号> review` を実行する。
5. PR タイトル・向き先・URL を `## PR` に書き、`Status: pr:awaiting-review` にして URL を報告し、停止する。レビューとマージは人が行うので、tixforge は待つだけ。ユーザーには、レビューが進んだら（1 人なら CI が通ったら）`/tixforge:dev <ticket-id>` で再開するよう案内する。

## PR の状況確認

`bash <scripts>/pr-status.sh <PR URL>` を実行する。1 行目が判定、2 行目以降が詳細。`.tixforge/config.yml` の `review.required`（無ければ `true`）と合わせて、次のとおり進む：

- `merged` → `## PR` に結果を追記し、`Status: done` にする。`GT-` なら `references/github/pr.md`「マージされたとき」に従って issue のラベルとクローズを扱う。
- `approved`（Approve 済み・CI 成功・コンフリクトなし）→ `## PR` に結果を追記し、`Status: pr:ready-to-merge` にして停止する。マージはユーザーが行う。マージしたら `/tixforge:dev <ticket-id>` で再開すると `done` になることを伝える。
- `ready`（Approve は無いが、CI 成功・コンフリクトなし）→
  - `review.required: false` なら `approved` と同じく `pr:ready-to-merge` にする。
  - `review.required: true` なら `pending` と同じ（Approve 待ち）。1 人で開発していて自分の PR を Approve できない場合は、`/tixforge:project update` で `review.required: false` にできることを伝える。
- 詳細の `ci: none`（チェックが 1 つも無い）→ リポジトリに PR で動く workflow があるか（`.github/workflows/*.yml` に `pull_request` がある）を確かめる。あれば、CI がまだ始まっていないだけなので `pending` として扱う。無ければ CI の無いリポジトリなので、判定どおりに進む。
- `conflict`（Base とコンフリクト）→ `Status: pr:in-progress` に戻し、`git fetch origin <Base>` の後、`origin/<Base>` をブランチに取り込んで解消する。取り込み方は merge を既定とする（rebase は force push が必要になるため、ユーザーが望んだ場合だけ）。
- `ci_failing`（CI 失敗）→ `Status: pr:in-progress` に戻し、失敗したチェック（`failing_checks`）のログを確認して（`gh pr checks`・`gh run view --log-failed`）原因を直す。
- `changes_requested`（修正依頼）→ `Status: pr:in-progress` に戻し、指摘を要約して提示してから対応する。
- `pending`（draft・未レビュー・CI 実行中など）→ その旨と詳細を伝え、`pr:awaiting-review` のまま停止する（`pr:ready-to-merge` から戻ったなら `pr:awaiting-review` にする）。`commented_by` がある（コメントだけのレビュー）場合は内容を示し、対応するかユーザーに尋ねる。
- `closed`（マージされずにクローズ）→ 報告し、どうするか尋ねる。勝手に `done` にしない。

`conflict`・`ci_failing`・`changes_requested` への対応はブランチに commit し、`## Implementation Log` に「PR 対応：<判定>」（ドキュメント言語）として記録する。push の前に**検証**（`run.md`「検証」）を行い、変更内容と検証結果を提示して**停止し、確認を得てから push する**。push したら `Status: pr:awaiting-review` に戻して停止する。対応が方針や計画の変更を伴う大きさなら、その場で直さずに停止し、`rewind.md` の手順で戻るかユーザーに尋ねる（PR を出した後に戻ると、追加の commit は既存の PR に入り、設定によっては Approve が外れる）。

## ローカルのみの場合（`repository.host: none`）

push も PR も無い。Review の後、ヘッダ表の `Base` へローカルでマージして終える。PR が無いので、マージ commit を「このチケットでまとめて入った変更」の記録にする。

1. **再開の確認**：`Status` が `pr:*` から再開したら、ブランチが既に `Base` にマージ済みか（`git merge-base --is-ancestor <ブランチ> <Base>`）、ブランチが削除済みかを先に確かめる。そうなら、マージ commit を探して「マージの記録」へ進む。
2. **コンフリクトを先にブランチの上で解消する**：`Status: pr:in-progress` にする。`<Base>` をブランチに取り込めるか確かめる：先に `git rev-parse --verify <Base>` と `git rev-parse --verify <ブランチ>` で両方があることを確かめ、`git merge-tree --write-tree <Base> <ブランチ>` を実行する。終了コード 1 ならコンフリクトがある。それ以外の失敗（関係の無い履歴など）は、出力を示して止まる。コンフリクトがあれば、ブランチの上で `git merge <Base>` して解消し、commit して、**検証**をやり直す。Base の上で直接マージしながら解消しない（検証も確認も無い解消が Base に入るため）。
3. **マージの準備**：マージの内容を提示する：**ブランチ**・**マージ先**（`Base`）・取り込む commit の一覧（`git log --oneline <Base>..<ブランチ>`）・実行するコマンド・マージ commit のメッセージ。
   - コマンド：`git switch <Base>` → `git merge --no-ff <ブランチ> -F <メッセージのファイル>` → `git branch -d <ブランチ>`
   - メッセージ：`docs/context/commit.md` にマージ commit の形式があればそれに従う。無ければ件名 `Merge <ticket-id>: <チケットのタイトル>` とし、本文にチケットの要約（背景と受け入れ条件）を入れる（`LT-` のチケットは git に残らないので、ここが記録になる）。
   - `Base` に未コミットの変更があれば、先に示して止まる（勝手に stash しない）。
4. `Status: pr:awaiting-approval` にして、**停止して明示的な確認を求める。** マージとブランチの削除は、この 1 回の確認でまとめて承認をもらう（guard hook により、Base でのマージの前に確認画面も出る）。
5. 確認されたら実行する。手順 2 で解消済みなので、コンフリクトは起きないはず。起きたら自分で解決せず、`git merge --abort` で元に戻し、コンフリクトしたファイルを示して停止する（`Status` は `pr:awaiting-approval` のまま）。ブランチの削除は `git branch -d`（マージ済みでなければ失敗する安全な削除）だけを使う。`-D` は使わない。
6. **マージの記録**：`## PR` にマージ先・マージ commit の hash・削除したブランチを書き、`Status: done` にして報告する。リモートがある（GitHub 以外）場合、tixforge は push しないので、`Base` の push はユーザーが行うことを伝える。
