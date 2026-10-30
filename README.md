# tixforge

チケット駆動でアプリ開発を回す Claude Code の plugin。チケットを作り、1 つのチケットを **Research → Approach → Plan → Implement → Review → PR** の 6 フェーズで実装から PR まで進める。進捗は 1 つのファイルに集約するので、どのフェーズで止めても後から再開できる。

| スキル | 内容 |
|--------|------|
| `/tixforge:project` | `init`：プロジェクトを tixforge で使える状態にする。`update`：設定を変える・チケット管理を切り替える・テンプレートを最新にする |
| `/tixforge:ticket` | `create`：チケットを対話で作る。`edit`：書き換える。`cancel`：キャンセル済みにする |
| `/tixforge:dev` | `<id>`：6 フェーズで進める（再開も同じ）。`rewind <id>`：前のフェーズに戻す |

典型的な流れ：`/tixforge:project init` → `/tixforge:ticket ログイン画面を作りたい` → `/tixforge:dev LT-000001`

どのスキルも明示起動専用（Claude が勝手に起動しない）。引数なしで起動すると、選択肢を出す。

## 導入

```sh
claude plugin marketplace add kmjak/tixforge
claude plugin install tixforge@tixforge
```

セッションの中なら `/plugin marketplace add kmjak/tixforge` → `/plugin install tixforge@tixforge`。次に起動するセッションから使える。更新は `claude plugin marketplace update tixforge` → `claude plugin update tixforge@tixforge`（`version` を上げたリリースだけが届く）。

plugin には、スキル 3 つ・Review 用の agent 2 つ（`tixforge:reviewer`・`tixforge:quality-reviewer`）・hook 2 つ（下記「hook」）が入っている。個別に導入・登録するものは無い。

### flow（1.x）からの移行

tixforge は、以前の `/flow`（`flow@flow-command`）の後継。

1. 古い plugin を外す：`claude plugin uninstall flow@flow-command`、`claude plugin marketplace remove flow-command`
2. 上の「導入」で tixforge を入れる
3. flow を使っていた各プロジェクトのルートで、移行スクリプトを実行する（まず試し実行で内容を確かめる）：
   ```sh
   bash ~/.claude/plugins/marketplaces/tixforge/scripts/migrate-from-flow.sh            # 試し実行
   bash ~/.claude/plugins/marketplaces/tixforge/scripts/migrate-from-flow.sh --apply    # 実行
   bash ~/.claude/plugins/marketplaces/tixforge/scripts/migrate-from-flow.sh --apply --github  # GitHub のラベルと issue も
   ```
   設定（`docs/flow.config.yml` → `.tixforge/config.yml`）、チケット（`docs/tickets/` → `.tixforge/<id>/ticket.md`。issue のあるものは `GT-`、無いものは `LT-`）、run（`docs/flow/` → `.tixforge/<id>/state.md`）、workflow（`flow-*.yml` → `tixforge-*.yml`）を移す。`--github` なら、`flow:*` のラベルを `tixforge:*` に変え、issue 本文の目印を書き換え、閉じた issue に `tixforge:done`・`tixforge:canceled` を付ける。最後に `git status` で確かめて commit する。
4. `/tixforge:project init` を実行して、足りない設定（`repository.close_issues` など）を足す

## 置き場所

| パス | 内容 | git |
|------|------|-----|
| `.tixforge/config.yml` | 設定（下記） | 管理する（チームで共有） |
| `.tixforge/.gitignore` | `*`・`!.gitignore`・`!config.yml`。それ以外を git から外す（プロジェクトの `.gitignore` は触らない） | 管理する |
| `.tixforge/<id>/ticket.md` | チケット（`LT-`：これが正本。`GT-`：issue の作業用コピー） | 管理しない |
| `.tixforge/<id>/state.md` | run の状態（Status・ブランチ・各フェーズの記録） | 管理しない |
| `.tixforge/<id>/history/` | 前のフェーズに戻したときの古い記録 | 管理しない |
| `docs/context/**` | サービス・ドメインの知識、commit 規約（`commit.md`） | 管理する |

チケットと run の状態は各個人の作業場所なので git に載せない。PR に載せるとレビュアーが検討過程に引っ張られるため。PR 本文には、合意した方針の結論と理由だけを書く。

## 設定（`.tixforge/config.yml`）

```yaml
language: ja            # チケット・context・run の記録・PR を書く言語
commands:               # dev が検証で書いた順に実行する（無ければ {}）
  test: npm test
  lint: npm run lint
ticket:
  tracker: github       # create が作るチケット：github（GT-。issue と連携）| local（LT-。手元のみ）
repository:
  host: github          # github（PR を出す）| none（ローカルでマージする）
  base_branch: develop  # dev がブランチを切る元・PR の向き先
  close_issues: release # base_branch が GitHub の default branch と違うとき：release | merge
review:
  required: true        # PR の Approve を必須にするか（1 人なら false）
gates: [approach, plan, pr]  # 必ず止まるゲート（pr は常に止まる）
```

`/tixforge:project init` が全てのキーを書く。値を変えるのは `/tixforge:project update`。スクリプトはこの形（2 段までの入れ子・1 行 1 キー・`#` コメント）だけを読む。値は全体を `"…"` で囲むか、まったく囲まない。

## チケット

- **id**：ローカルのチケットは `LT-000001`、GitHub issue のチケットは `GT-000123`（issue #123）。チケットの扱いは id の接頭辞で決まり、`ticket.tracker` は create が次にどちらを作るかだけを決める（切り替えても既存のチケットはそのまま使える）。
- **入力**：`gt-000123`（大文字小文字は問わない）・`#123`（issue 番号）・`123`（`ticket.tracker` に従う）。接頭辞付きで桁数が違う id（`GT-00123`）はエラーにして、0 を補わない（打ち間違いで別のチケットを指さないため）。
- **create**：中身はユーザーが書き、Claude は質問で引き出す（案を出すのは「考えて」と頼んだときだけ）。`/tixforge:ticket <作りたいもの>` のように文だけ渡してもよい。似たチケットがあれば示し、大きすぎれば分割を提案する。作った後は「開発を始める／別のチケットを作る／終わる」を選べる。
- **ローカルのチケット（`LT-`）** は手元にしか無い（1 人・1 台で使う前提）。GitHub に PR を出すときは、受け入れ条件が PR 本文に転記される。public リポジトリで「コードは公開、計画は手元」にしたいときにも使える。
- **既定と違うブランチから作る**チケット（hotfix など）は、チケットに `## Base` の節を書く。

## dev の 6 フェーズ

| # | フェーズ | 内容 |
|---|----------|------|
| 1 | Research | チケットと `docs/context/**` を読み、コードの調査は Explore agent に任せる。チケットの未決事項を 1 項目ずつ片付ける（何を作るかの決定はチケットに書き戻し、どう作るかの決定は Approach の表へ） |
| 2 | Approach | 実装方針（選択肢・採用案・トレードオフ）を決めて合意する |
| 3 | Plan | Base・ブランチ・**受け入れ条件 → 確かめ方の対応表**・commit 分割。確かめ方の種別（自動／Claude（ブラウザ）／Claude（API）／ユーザー）は項目ごとにユーザーが選ぶ。Plan は常に止まる |
| 4 | Implement | 計画どおりに実装・commit し、検証コマンド（`verify.sh`）と手動確認を通す。context と矛盾しないかもここで確かめる |
| 5 | Review | 2 つの reviewer agent を並列に起動する。`tixforge:reviewer` は合意とのズレ（相違・未実装・合意外の変更・決定の無い未決事項）、`tixforge:quality-reviewer` は品質を見る。2 ラウンド目からは前のラウンドからの差分と、直すと決めた指摘が直ったかを見る。指摘ごとに修正・計画の見直し・方針の見直し・受け入れをユーザーが選ぶ |
| 6 | PR | 明示的な確認の後にだけ push して PR を出し、レビュー・CI を見届ける（tixforge はマージしない）。`host: none` では、確認の後に Base へローカルでマージする |

- **ゲート**：`gates` にあるフェーズでは必ず止まる。無いフェーズは、止まる条件（未決事項・ユーザーの判断・対処が決まっていない指摘など）が無ければ自動で通過する。PR の前は常に止まる。止まった所が再開点になる。
- **Status**：`<phase>:in-progress`・`<phase>:awaiting-approval`、PR 後は `pr:awaiting-review`・`pr:ready-to-merge`（Approve・CI・コンフリクトの条件を満たしマージ待ち）。`done` はマージされたときだけ。
- **巻き戻し**：`/tixforge:dev rewind <id>`（または dev の最中に「Plan からやり直したい」と頼む）で、前のフェーズに戻す。後のフェーズの記録は `history/` に移る。ブランチに commit があれば、そのブランチの上で続けるか作り直すかを選ぶ。GitHub のチケットは、ここから他の人に渡せる（手放す）。

## GitHub 連携（`GT-` のチケット）

- issue が正本。チケットの全文と、tixforge が書いたことを確かめるハッシュを本文に載せる。本文とタイトルは GitHub 上で直接編集せず、`/tixforge:ticket edit` で変える（直接編集されると検知して、取り込むか尋ねる）。2 人が同時に edit しても、後から書き戻す人の古いコピーは拒否される。
- GitHub の画面で作られた issue も、`/tixforge:ticket create #<番号>` で取り込める（`project init` で issue フォームを入れておくと、見出しがそろう）。
- tixforge が投稿するコメントは、キャンセル・巻き戻し・手放すときの判断の記録と、クローズのときの一言だけ。コメントを編集・削除しない。

| ラベル | 意味 |
|--------|------|
| `tixforge:todo` | 誰もまだ着手していない |
| `tixforge:in-progress` | dev を進めている（assignee が担当） |
| `tixforge:in-review` | PR のレビュー・マージ待ち |
| `tixforge:merged` | Base（develop など）にマージ済み・リリース待ち |
| `tixforge:done` | 完了 |
| `tixforge:canceled` | キャンセル済み |
| `tixforge:out-of-sync` | GitHub 上で本文かタイトルが直接編集された |

状態ラベルは常に 1 つだけ付く。

**issue が閉じる時点**：Base が GitHub の default branch なら、PR のマージで閉じる。develop などの場合は `repository.close_issues` で選ぶ：`release` なら、develop にマージした時点では開いたまま `tixforge:merged` になり、main に入った時点（最初の commit の `Closes #N` により GitHub が閉じる）で `tixforge:done`。`merge` なら develop へのマージで閉じる（Actions の `tixforge-issue-sync` が必要）。

**Actions**（`project init` で任意に入れる。雛形は `templates/github/`）：

| workflow | 内容 |
|----------|------|
| `tixforge-issue-sync` | PR の作成・マージと issue のクローズに合わせて、状態ラベルを付け替え、issue を閉じる |
| `tixforge-pr-link` | `GT-<番号>-` ブランチの PR 本文に `Closes #<番号>` があるかを検査する（ブランチ保護で必須にできる） |
| `tixforge-issue-guard` | issue が GitHub 上で直接編集されたら `tixforge:out-of-sync` とコメントを付ける |

フォークからの PR には対応しない（Actions のトークンが読み取り専用になるため）。必要なら workflow を各自で改造する（`pull_request_target` にし、PR の作者がメンバーかを確かめる処理を足す。PR のコードは checkout しない）。

## hook

plugin を有効にしていれば、スキルを起動していないセッションや `--resume` で再開したセッションでも効く。tixforge の run が関わる場所でだけ判定し、それ以外は素通しする。

| hook | イベント | 内容 |
|------|----------|------|
| `scripts/guard.sh` | PreToolUse（`Bash\|Edit\|Write\|MultiEdit\|NotebookEdit\|mcp__.*`） | push・PR 作成・許可リスト外の git / gh 操作に確認画面を出し、force push と `Closes` の無い PR をブロックする。Plan の承認前の run があるときのコード編集にも確認画面を出す |
| `scripts/session-start.sh` | SessionStart（`compact\|resume`） | 会話の要約・再開の後、進行中の run と、読み直す手順ファイルを Claude に伝える |

`guard.sh` の判定：

| 場所 | 判定 | 対象 |
|------|------|------|
| run のブランチ・進行中の run の Base | **deny** | force push（`-f`・`--force-with-lease`・`+refspec`、`bash -c`・`eval` 経由も）。必要ならユーザーが `! git push --force-with-lease` で自分で実行する |
| `GT-` の run のブランチ | **deny** | 本文に `Closes #<番号>` の無い `gh pr create` |
| run のブランチ | **ask** | それ以外のすべての push・PR 作成（確認画面に Status・ブランチ・Base・PR の状況が出る） |
| run のブランチ・進行中の run の Base | **ask** | 許可リストに無い git / gh 操作（merge・rebase・reset・cherry-pick・clean・`commit --amend`・`branch -D`・`switch -f`・`checkout -B`・`fetch +refspec`・`gh pr merge`・書き込みの `gh api` など）と、GitHub / git の MCP ツールの読み取り以外 |
| 進行中の run の Base | **ask** | Base への commit・push |
| Plan の承認前の run があるとき | **ask** | `docs/`・`.tixforge/` 以外のファイルへの Edit / Write（Implement 以降の run のブランチの上では出さない） |

- `permissionDecision: "ask"` は、`permissions.allow` に `git push` を入れていても、auto モードでも確認画面を出す。
- 検知はあえて広めにしている（引用符を外して `git` と `push` の組み合わせを拾うなど）。誤検知しても確認画面が出るだけ。commit メッセージに「push -f」と書いただけならブロックしない（確認画面に注記が付く）。
- **事故防止の仕組みであって、完全な防御ではない。** Claude が実行できるコマンドは、どんな検知もすり抜ける書き方ができる。サーバー側で確実に守りたいことは、Actions（`tixforge-pr-link`）とブランチ保護で守る。

## statusline

Claude Code の画面の下に、今いる場所の run と Status を出せる（任意。plugin を入れただけでは出ない）。

```
LT-000001 · plan:awaiting-approval
```

今のブランチの run を出す。どの run のブランチでもなければ、Plan の承認前の run（まだブランチが無い）を出し、複数あれば先頭の 1 つに `(+<残りの数>)` を付ける。run が無い場所では何も出さない。

statusline を使っていなければ、`~/.claude/settings.json` に足す：

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/plugins/marketplaces/tixforge/scripts/statusline.sh"
}
```

自分の statusline のスクリプトがあれば、受け取った入力をそのまま渡して、出力を好きな位置に入れる：

```sh
input=$(cat)
tf=$(printf '%s' "$input" | bash ~/.claude/plugins/marketplaces/tixforge/scripts/statusline.sh)
```

## 困ったとき

- **run の状態ファイルが壊れた**：`.tixforge/<id>/state.md` を消せば、`/tixforge:dev <id>` で最初から始まる（チケットは残る）。
- **確認画面が出すぎる**：スキルの `allowed-tools` の事前承認は、起動したターンにだけ有効。常に許可したいスクリプトは `.claude/settings.json` の `permissions.allow` に足す。
- 起動時の `` !`bash …/project-status.sh` `` などは、`deny` に `Bash(bash:*)` のような広いルールがあるとスキルの起動自体が失敗する。

## tixforge 自体を開発する

```sh
brew install shellcheck shfmt actionlint zizmor editorconfig-checker jq   # 初回だけ
git config blame.ignoreRevsFile .git-blame-ignore-revs   # 初回だけ。整形だけの commit を blame から外す
claude --plugin-dir .                     # 作業ツリーをそのまま読み込む
make check                                # PR の前に。lint・テスト・macOS の bash 3.2 でのテスト・claude plugin validate
make fmt                                  # shfmt で整形（設定は .editorconfig）
```

- CI（`.github/workflows/test.yml`）は、どの変更でも lint と 4 つのテストを、gawk・mawk・macOS（bash 3.2 と BWK awk）で回す。ブランチルールで必須にするのは `result` だけ。

- `skills/<名前>/SKILL.md` が起動時に読まれ、共通規約（`references/common.md`）を `scripts/common-rules.sh` で差し込む。手順は `skills/<名前>/*.md` と `references/github/*.md` に分け、使う場面で読む。
- 結果が 1 つに決まる処理は `scripts/` に置き、テストで確かめる（gh はスタブに置き換える。`scripts.test.sh` には jq が要る。`json-get.test.sh` は jq があれば、guard が hook の入力を読む `json_get` を jq の結果とも突き合わせる）。
- スクリプトの中で、`$var` の直後に全角文字を続けない（`${var}` と書く）。テストが検出する。
- **リリース**：`.claude-plugin/plugin.json` の `version` を上げたものが、利用者に届く新しい版になる。version は release-please が管理する（`.github/workflows/release-please.yml`）。PR は squash でマージし、タイトルを Conventional Commits（`feat:`・`fix:` など）で書く。main に入るたびに、次の version と `CHANGELOG.md` を書き換えるリリース PR が更新され、それをマージすると `tixforge--v<version>` のタグ・GitHub Release・Discord 通知ができる。種類の選び方は `CLAUDE.md`。
- **テンプレート**：`templates/github/` を変えたら、先頭のコメントの版数（`(v3)` など）を上げる。`/tixforge:project update` はこれで更新の有無を判断する。

## License

[MIT](LICENSE)
