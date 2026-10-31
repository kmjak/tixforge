# /tixforge:project update — 設定とテンプレートの更新

目的：init の後に、既にある設定の値を変える・v2 のローカルのチケット（`LT-`）を issue に移す・プロジェクトにコピーしたテンプレートを最新にする。init は足りない設定を足すだけで既存の値を変えないので、変えるときはこちらを使う。

`.tixforge/config.yml` が無ければ、`/tixforge:project init` を案内して止まる。

1. **何を更新するか**を AskUserQuestion で尋ねる（単一選択。引数で指定されていればそれに従う）。SKILL.md の「現在の状態」に「移行が要る」があれば、尋ねずに「v2 の LT を issue に移す」から行う：
   - **設定の値を変える**
   - **v2 の LT を issue に移す**
   - **テンプレートと Actions を最新にする**
2. 選んだものの手順（下記）に進む。どれも、変える内容を差分で示し、確認を得てから書く。書いたファイルは commit しない（一覧で示し、commit するかはユーザーに任せる。commit するなら `docs/context/commit.md` の規約に従う）。

## 設定の値を変える

- 今の `.tixforge/config.yml` を示し、何を変えたいか尋ねる。キーの意味は共通規約の設定の例を使って説明する。
- 値の決め方と確かめ方は init の同じ手順に揃える（init の手順ファイル `<plugin>/skills/project/init.md` の該当手順を Read する）：
  - `repository.base_branch`・`close_issues` → 「ブランチ運用」。develop に変えるのに develop が無ければ、作るか尋ねる（`git fetch origin <今の base_branch>` の後に `git branch develop origin/<今の base_branch>`）。リモートに develop が無ければ push を勧める（コマンドを示して確認を得てから。push しないと dev の Plan で止まる）。進行中の run（`state.md` の `Base`）は変わらないことを伝える。
  - `commands` → 「検証コマンド」（値は全体を囲むか囲まないか）。
  - `review.required` → 人数に合わせる（1 人なら `false`）。
  - `language`・`gates` → そのまま書き換える。`language` を変えたら、前の言語で作ったもの（issue フォーム `.github/ISSUE_TEMPLATE/tixforge-ticket.yml`・PR テンプレート・`docs/context/**`、フォームから取り込んだチケットの見出し）は前の言語のまま残ることを伝える（訳し直しはしない）。
- `ticket.tracker` は `github` のままにする。

## v2 の LT を issue に移す

v3 は GitHub が必須で、チケットを issue にだけ置く。v2 の `LT-` のチケット・`tracker: local`・`repository.host: none` を移す。

1. `bash <scripts>/github-preflight.sh`。`ok:` 以外なら出力を示し、済ませてもらってから確かめ直す（remote が無いなら init の「リポジトリ」の手順で用意する）。GitHub のリポジトリを使わないなら、tixforge v2 に留まるよう伝えて止まる。
2. init の「チケット管理」（ラベル・issue フォーム）と「GitHub Actions」を行う。
3. 移すもの（`.tixforge/LT-*/` のうち、`ticket.md` に `Status: canceled` が無く、`state.md` が無いか `Status` が `done`・`canceled` 以外のもの）を一覧で示し、1 枚ずつ次から尋ねる。`state.md` で run が進行中のものは、issue にすると新しい `GT-` の id で dev を始め直すことになると添える。
   - **issue にする**（`ticket.md` があるときだけ出す）— `references/github/create.md` を Read し、`bash <scripts>/issue-sync.sh create <LT- の ticket.md>` を実行する。元の `ticket.md` のタイトル行の下に `Status: canceled` と `Reason: <GT-id> に移した` の 2 行を足す。
   - **やめる** — `ticket.md` があれば、タイトル行の下に `Status: canceled` と `Reason: <理由>` の 2 行を足す（理由を 1 行で尋ねる）。
   - **issue にせず、PR を手で終える**（`state.md` の `Status` が `pr:*` のときだけ出す）— `## PR` の PR の URL を示し、マージかクローズは GitHub で行うよう伝える。`bash <scripts>/run-state.sh set <LT-id> Status done` を実行する。
   - 「issue にする」「やめる」では、`state.md` があれば `bash <scripts>/run-state.sh set <LT-id> Status canceled` を実行する。
4. `ticket.tracker` が `local` なら `github` に書き換え、`repository.host` のキーがあれば消す。`host: none` だったなら、init の「レビューの要否」（人数を尋ねる）・「PR テンプレート」・「CI」も行う。
5. `bash <scripts>/project-status.sh` を実行し、「移行が要る」が出なくなったことを確かめる。

## テンプレートと Actions を最新にする

plugin を更新しても、プロジェクトにコピーしたファイルは自動では変わらない。plugin 側と比べて、古いものを更新する。

| プロジェクトのファイル | plugin 側 | 比べ方 |
|------------------------|-----------|--------|
| `.github/workflows/tixforge-issue-sync.yml`・`tixforge-pr-link.yml`・`tixforge-issue-guard.yml` | `<plugin>/templates/github/` の同名ファイル | 先頭のコメントのバージョン（`(v2)` など）と内容 |
| `.github/tixforge/ticket-hash.sh`・`messages.yml` | `<scripts>/` の同名ファイル | 内容（ハッシュの計算方法がずれると、直接編集の誤検知になる） |
| `.github/ISSUE_TEMPLATE/tixforge-ticket.yml` | `<plugin>/templates/github/ISSUE_TEMPLATE/` | バージョン（訳した見出しはプロジェクト側を保つ） |
| `.github/workflows/tixforge-ci.yml` | `<plugin>/templates/github/tixforge-ci.yml` | バージョンだけ。中身はプロジェクトに合わせて埋めたものなので置き換えない。雛形の変更点（差分）を示し、取り込むか尋ねる |

- 違うものを一覧で示し（ファイルごとに差分）、置き換えるものを選んでもらってから書く。同じものは「最新」と伝える。
- 足りないラベル（新しい版で増えたもの）を作る：init の「チケット管理」と同じく `references/github/labels.md` を Read し、無いラベルを意味と一緒に示して確認を得てから、`bash <scripts>/issue-label.sh setup` を実行する。
- プロジェクトに無いファイルは作らない（入れたいなら init の「GitHub Actions」を案内する）。
