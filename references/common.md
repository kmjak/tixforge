# tixforge 共通規約

**会話の言語**：ユーザーへの質問・説明・選択肢（AskUserQuestion の文言を含む）は、`.tixforge/config.yml` の `language` で書く。設定が無いとき（init で言語を決める前を含む）は日本語。ユーザーが明らかに別の言語の文章で書いてきたときだけ、その言語に合わせる。スラッシュコマンドや選択肢の回答だけでは言語を判断しない（英語に切り替えない）。

`project`・`ticket`・`dev` の 3 つのスキルに共通する規約。各スキルの起動時にこのファイルの内容が差し込まれる。

手順ファイルの中の表記：

- `<plugin>` — plugin のディレクトリ（各スキルの「置き場所」に実際のパスがある）
- `<scripts>` — `<plugin>/scripts`。スクリプトは `bash <scripts>/<名前>.sh …` で実行する
- `references/<名前>.md` — `<plugin>/references/<名前>.md`

**会話が要約された後**（要約から再開したとき）は、続ける前に、今の手順ファイルと（dev なら）`.tixforge/<ticket-id>/state.md` を Read し直す。要約には手順の細部が残らないため。SessionStart hook（plugin に同梱）が、そのことを自動で伝える。

## 共通規約

チケット id を全ての基点にする：チケットと状態のフォルダ名・ブランチ接頭辞。

**チケット id の形式：** ローカルのチケットは `LT-<番号>`、GitHub issue のチケットは `GT-<番号>`。番号は 6 桁に 0 埋めする（`LT-000007`・`GT-000123`）。`GT-000123` は issue #123。番号が 6 桁を超えたら 0 埋めせずにそのまま使う。

- **チケットの扱いは id の接頭辞で決まる**：`LT-` は手元のファイルが正本、`GT-` は issue が正本（`references/github/`）。`.tixforge/config.yml` の `ticket.tracker` が決めるのは、create が次にどちらを作るかだけ。tracker を切り替えても、既存の `LT-` のチケットはそのまま `LT-` として完了まで進められる。
- `LT-` の番号は `ticket-id.sh next`（`.tixforge/` と手元のブランチ名の最大の番号 + 1）。ローカルのチケットは 1 人・1 台で使う前提。`GT-` の番号は issue 番号（create で issue を作成して得る。複数人で作っても衝突しない）。

**id は必ず `<scripts>/ticket-id.sh` で扱う**（手で 0 埋め・変換・解釈しない。シェルの算術に 0 埋めの数字を渡すと 8 進数になる）。出力はそのまま使う：

| 用途 | コマンド |
|------|----------|
| 引数からチケット id を取り出す | `bash <scripts>/ticket-id.sh detect "<引数>"` → `id: <id>`（無ければ `id: none`、形が不正なら `invalid: <語>`）と `rest: <id を除いた残り>`。明示的な形（`LT-…`・`GT-…`・`#123`）は文中でも拾い、裸の数字は引数全体が数字のときだけ拾う |
| 指定された id の正規化 | `bash <scripts>/ticket-id.sh normalize <引数>`（`LT-000123`・`GT-000123`（大文字小文字は問わない）・`#123`（issue 番号）・`123`（`ticket.tracker` に従う）。桁数が違う id は 0 埋めせずにエラー（終了コード 2）→ 正しい形を示して尋ねる） |
| そのチケットが実在するか | `bash <scripts>/ticket-id.sh exists <id>` → `ticket`（`LT-`）・`issue`・`pull-request`（その番号は PR）・`none` |
| id → issue 番号 | `bash <scripts>/ticket-id.sh number <GT-id>` |
| 次の id（`LT-`） | `bash <scripts>/ticket-id.sh next` |

- **id のエラーを自分で直さない。** `normalize` が終了コード 2（桁数違い・形が不正）を返したり、`detect` が `invalid:` を返したりしたら、0 を補う・接頭辞を付けるなどして再実行しない。エラーをそのまま示し、正しい id をユーザーに尋ねる（桁の打ち間違いで別のチケットを指すのを防ぐための規則）。
- 取り違えを防ぐため、dev・edit・cancel は始めるときに「`<id>`：<チケットのタイトル>」を必ずユーザーに示す。

| 用途 | パス |
|------|------|
| サービス／ドメイン知識 | `docs/context/**`（必要な分だけ読む。git 管理する） |
| tixforge 設定 | `.tixforge/config.yml`（git 管理する。チーム共通） |
| チケット | `.tixforge/<ticket-id>/ticket.md`（**git 管理外**）— `LT-`：これが正本。`GT-`：issue から作る作業用のコピー（`references/github/fetch.md`） |
| run の状態 | `.tixforge/<ticket-id>/state.md`（**git 管理外**。`<scripts>/run-state.sh` で作り、ヘッダを更新する） |
| ブランチ名 | `<ticket-id>-<slug>`（チケット id を接頭辞にする。slug は英小文字・数字・ハイフン） |

- **`.tixforge/` の中で git 管理するのは `config.yml` と `.gitignore` だけ。** `.tixforge/.gitignore`（`*`・`!.gitignore`・`!config.yml`）がそれ以外を管理外にする。無ければ `run-state.sh init` と `issue-sync.sh pull` が作る。プロジェクトの `.gitignore` は触らない。チケットと run の状態は各個人の作業場所であり、共有物ではない。また PR に含めるとレビュアーが検討過程に引っ張られ、実装そのものを見たレビューにならないため。PR 本文に書くのは、合意した方針の**結論と理由**（2〜3 行）だけにする。
- **ローカルのチケット（`LT-`）は PR から見えない。** GitHub に PR を出す（`host: github`）ときは、PR 本文に受け入れ条件を必ず転記する。`host: none` ではマージ commit の本文にチケットの要約を入れる。
- **ドキュメント言語**：チケット・`docs/context/**`・run の状態（`state.md`）の本文、および PR のタイトル・本文は `.tixforge/config.yml` の `language` で書く。既定は日本語（`ja`）。設定ファイルが無ければ日本語とする。チケットと context は見出しもこの言語にする（`state.md` の見出しは英語の固定キー）。
  ```yaml
  # tixforge settings (shared, committed)
  language: ja   # ja | en | その他の言語名
  commands:      # dev の検証で書いた順に実行する（init で決める。無ければ {}）
    test: npm test
    lint: npm run lint
  ticket:
    tracker: github   # create が作るチケット：github（GT-。issue と連携）| local（LT-。手元のみ）
  repository:
    host: github          # github（PR を出す）| none（ローカルのみ。PR フェーズはローカルでマージ）
    base_branch: main  # Plan の Base の既定値。host: none ではマージ先
    close_issues: merge   # Base が GitHub の default branch でないとき：merge（Base へのマージで閉じる）| release（default branch へのリリースで閉じる）
  review:
    required: true        # PR の Approve を必須にするか。1 人で開発するなら false
  gates: [approach, plan, pr]  # 必ず止まるゲート。pr は書かなくても必ず止まる（skills/dev/run.md「承認ゲート」）
  ```
  スクリプトはこの形（2 段までの入れ子・1 行 1 キー・`#` コメント）だけを読む。値は全体を `"…"` で囲むか、まったく囲まない（` #` を含むなら囲む）。
- 設定に必要なキーが無ければ、推測の既定値で補わず、`/tixforge:project init` の再実行で足せることを伝える（init は全てのキーを書く）。`review.required` が無ければ `true`、`gates` が無ければ `[approach, plan, pr]` として扱う。
- `ticket.tracker: github` は `repository.host: github` のときだけ使える。
- 上記パスは固定規約。`init` はこの規約どおりの雛形を作るだけで、パスの選択はしない。
- どのサブコマンドでも、既存ファイルを黙って上書きしない（`GT-` の作業用コピー `.tixforge/<id>/ticket.md` は、issue から作り直すものなので例外。作り直すときは差分を示す）。
- **キャンセル済みのチケット**（チケットに `Status: canceled`、または `state.md` の `Status` が `canceled`）は、どのサブコマンドでも操作しない。その旨を伝えて止まる。

### スクリプト（`<scripts>/`）

結果が 1 つに決まる処理と、一字も変えずに写すべき処理はスクリプトに任せ、手で同じことをしない。出力は要約せずにそのまま使う。

| スクリプト | 用途 |
|------------|------|
| `ticket-id.sh` | id の取り出し・正規化・実在の確認・issue 番号への変換・次の番号（上記） |
| `run-state.sh` | 状態ファイルの作成（`init`）、ヘッダの読み書き（`get` / `set`。`Status` の値を検査し、`Updated` も更新する）、前の版の形式からの更新（`migrate`） |
| `verify.sh` | 検証コマンドの実行と `Verification @ <hash>: …` の行の出力 |
| `review-input.sh` | Review の agent に渡す差分・commit 一覧をファイルに書き出す |
| `pr-status.sh` | PR の状況（レビュー・CI・コンフリクト）の判定 |
| `issue-sync.sh` / `issue-label.sh` / `github-preflight.sh` | GitHub issue との同期・ラベルと担当者・事前チェック（`references/github/`） |
| `project-status.sh` | 設定と進行中の run の一覧（起動時に上の「現在の状態」へ自動で入る） |

## 行動原則（全体を通して）

- 情報が不足・曖昧なときは**質問する**。チケットの内容・要件・存在しないファイルを勝手に作らない。
- 仮定を置いて進めるときは**その仮定を明示**し、ユーザーが直せるようにする（該当セクションにも記録する）。
- 不要な手順や成果物だと感じたら、黙ってやらず（黙って省きもせず）**指摘する**。
- 懸念や反対は**理由付きで率直に**言う。ユーザーが提案したというだけで同意しない。
- ユーザーとの会話は、冒頭の「会話の言語」に従う。チケット・context・`state.md` のセクション本文はドキュメント言語で書く。

## ガードレール

- dev の 1 run につき 1 チケット。作業が別チケットの範囲に広がりそうなら指摘する。
- 明示的な確認なしに push / PR 作成 / マージをしない（dev の PR フェーズ）。tixforge は PR をマージしない（`host: none` のローカルマージだけは、確認の後に行う）。
- **hook（guard）が push・PR 作成・一部の git / gh 操作・Plan 承認前のコード編集に確認画面を出したり、ブロックしたりする。ブロックされたら、また確認画面で拒否されたら、コマンドを言い換えるなどして回避・再実行しない。** 理由（拒否なら拒否されたこと）をユーザーに伝えて指示を待つ。確認画面はチャットでの承認の代わりではない（PR フェーズでは、チャットで確認を得てから実行する）。
- 外部システムの操作は、`GT-` のチケットの GitHub issue に対する、`references/github/` に定めた操作だけにする。issue のコメントは自由で、tixforge はコメントを編集・削除しない。それ以外の外部システム（Jira など）にチケットを作らない。

## 扱わないもの

- GitHub issue 以外のチケット管理（Jira など）・複数ブランチにまたがる 1 チケット・バックログの管理（分解・優先度）。求められたら、tixforge では扱わないことを伝え、1 チケット 1 ブランチの範囲でできることを行う（大きいチケットは分けることを提案する）。
