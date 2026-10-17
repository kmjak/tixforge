# GitHub：Actions（任意）

`project init` で、`tracker: github` のときに読む。ローカルの tixforge は誰かが実行したときにしか動かないので、サーバー側で次の workflow を動かす。雛形は `<plugin>/templates/github/`。選ばれたものを `.github/workflows/` にそのままコピーする（内容は変えない）。

| workflow | 起動 | 内容 |
|----------|------|------|
| `tixforge-issue-sync.yml` | PR の作成・再オープン・ready for review・本文の編集（開いている PR）・クローズ、issue のクローズ | PR 本文の `Closes #N` の issue（`tixforge:*` ラベル付きのものだけ）を `tixforge:in-review` に（`tixforge:merged` の issue は変えない。develop → main のリリース PR で戻らないように）。マージされたら：default branch 向けなら閉じて `tixforge:done`、それ以外は `repository.close_issues` に従う（`release` なら `tixforge:merged` にして開いたまま、`merge` なら閉じて `done`）。`tixforge:merged` の issue が完了として閉じられたら `tixforge:done` に（not planned で閉じたときは変えない） |
| `tixforge-pr-link.yml` | PR の作成・編集・push | `GT-<番号>-` ブランチの PR の本文に `Closes #<番号>` があるかを検査する。必須チェックにするかはユーザーがブランチ保護で決める（tixforge は設定しない） |
| `tixforge-issue-guard.yml` | issue のタイトル・本文の編集 | 本文のハッシュが合わなければ（GitHub 上で直接編集された）`tixforge:out-of-sync` とコメントを付け、合えば外す |

- `tixforge-issue-guard` か `tixforge-pr-link` を入れるときは、`<scripts>/messages.yml` を `.github/tixforge/` にもコピーする（コメントやエラーをドキュメント言語で出すため）。`tixforge-issue-guard` なら `<scripts>/ticket-hash.sh` も（ハッシュの計算方法をローカルと揃えるため）。
- Base が GitHub の default branch と違う運用（develop など）で `repository.close_issues: merge` にするなら、`tixforge-issue-sync` を強く勧める（無いと、issue は dev を再開したときにしか閉じない）。
- Actions が投稿するコメントは、直接編集の知らせ（issue-guard）とクローズの一言（issue-sync）だけ。
- フォークからの PR には対応しない（Actions のトークンが読み取り専用になるため）。
- 雛形の先頭のコメントにバージョン（`v2` など）がある。plugin を更新しても、コピーした workflow は自動では更新されない。
