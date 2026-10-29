# /tixforge:project init — プロジェクト初期化

目的：このプロジェクトで tixforge を使える状態にする。最初に 1 回実行する想定だが、**何度実行しても安全**にする（済んでいる項目は飛ばし、足りない設定だけを足す）。**既にある設定の値は変えない**（変えるのは `/tixforge:project update`）。引数は取らない（チケット id が渡されたら無視せず、`/tixforge:ticket create` を案内する）。

各手順は太字の名前で参照する（例：「チケット管理」）。質問は AskUserQuestion で、選択肢に推奨を付けて出す。

1. **現状の確認**：`docs/context/`・`.tixforge/` の有無と中身、git リポジトリかどうか、commit が 1 つでもあるか（`git rev-parse --verify -q HEAD`）、remote（`git remote -v`）。
   `.tixforge/config.yml` が既にある場合（再実行）は読み込み、**値があるキーは尋ねずにそのまま使う**。以降の手順は、値が無いキーについてだけ行う。
2. **開発の人数**：「1 人で開発しますか？」と尋ねる（設定のキーが全て埋まっていれば尋ねない）。答えは「チケット管理」「ブランチ運用」「レビューの要否」の推奨に使い回す（同じことを 2 度尋ねない）。
3. **リポジトリ**（`repository.host`）：tixforge はブランチと commit を前提にし、PR は GitHub に出す。
   - **git リポジトリでない**：`git init` するか尋ねる（ブランチ名は「ブランチ運用」で決める）。しないなら、tixforge は使えないことを伝えて中止する。
   - **remote がある**：`bash <scripts>/github-preflight.sh` を実行する。
     - `ok: <owner>/<repo>` → `host: github`（SSH の Host エイリアスや GitHub Enterprise でも、gh が知っていれば GitHub と判定できる）。
     - 終了コード 3・4（gh が無い・未ログイン）→ `git remote get-url origin` が `github.com` を含めば GitHub の可能性が高い。出力の案内（インストール、`! gh auth login`）を示し、済ませてもらってから確かめ直す。
     - 終了コード 5（gh が知らないホスト。GitLab など）→ PR は GitHub にしか出せないことを伝え、`host: none`（PR を出さず、ローカルでマージする）で使うか、中止するかを尋ねる。`host: none` なら、**tixforge は push しないので、ローカルでマージした結果をリモートに反映するのはユーザー自身**であることも伝える。
   - **remote が無い**：GitHub リポジトリが要るか尋ねる：
     - **AI と対話して作る** — 下記「リポジトリを作る場合」。
     - **自分で作る** — `gh repo create` か GitHub の画面で作って `git remote add origin <URL>` する手順を示し、済ませてもらってから、この手順をもう一度行う。
     - **不要（ローカルのみ）** — `host: none`。チケット管理は `local` に決まる。

   **リポジトリを作る場合**：先に `bash <scripts>/github-preflight.sh` の終了コードが 3・4 でないことを確かめる（3・4 なら案内して待つ）。次の項目を**1 つずつ**尋ね、全部決まったら、実行するコマンド（`gh repo create <owner>/<name> --<visibility> --source=. --remote=origin [--description "<説明>"]`）と作るもの（LICENSE を含む）を一覧で示して確認を得てから作る。push は「commit」の後に行う。
   - **オーナー** — 既定は個人アカウント（`gh api user --jq .login`）。所属 organization（`gh api user/orgs --jq '.[].login'`）を選択肢に加える。
   - **リポジトリ名** — 既定はリポジトリのルートディレクトリ名。GitHub で使えない文字（英数字・`-`・`_`・`.` 以外）は `-` に置き換えた案を示す。`gh repo view <owner>/<name>` で同名のものが既にあれば、先に伝えて別の名前を尋ねる。
   - **公開範囲** — 既定は **private**。public・（organization なら）internal から選ぶ。public を選んだら、コードが誰でも見られるようになることを念押しする。
   - **説明** — 省略可。README の 1 行目があれば候補にする。
   - **LICENSE**（public のときだけ。既に LICENSE ファイルがあれば尋ねない）— MIT・Apache-2.0・GPL-3.0・付けない、から選ぶ（その他は自由入力）。「付けない」には、他の人は法的に使えない（全著作権を保持する）ことを添える。著作権者は `git config user.name`、年は今年を既定にして確認する。本文は記憶から書かず、`gh api licenses/<キー>`（例：`mit`）の `body` を使い、年と著作権者の欄を埋める。
   - **push するか** — 既定は「する」。public のときは、先に `.env`・鍵ファイルなどの秘密情報が git で追跡されていないか確かめ、あれば示して止まる。

   config にはオーナー・リポジトリ名・公開範囲は書かない（remote と GitHub から分かり、書くと食い違うため）。
4. **ブランチ運用**（`repository.base_branch`・`repository.close_issues`）：`base_branch` は、dev がブランチを切る元であり、PR の向き先（`host: none` ではマージ先）。
   - **新しく作るリポジトリ**（`git init` した・「リポジトリを作る場合」・commit がまだ 1 つも無い）：運用を尋ねる。ブランチ名は自由入力で変えられる。
     - **main だけ**（1 人なら推奨）— `base_branch: main`。
     - **main + develop**（develop で開発し、main はリリース用）— `base_branch: develop`。develop は「commit」の後に作る（init のファイルを両方に含めるため）。GitHub の default branch は main のままにする。
   - **既存のリポジトリ**：GitHub の default branch（`gh repo view --json defaultBranchRef`、取れなければ `git symbolic-ref --short refs/remotes/origin/HEAD`、`host: none` なら今のブランチ）を既定にする。ローカル（`git show-ref`）とリモート（`git ls-remote --heads origin`）に `develop`・`dev`・`development` があり、default と違えば、どちらを `base_branch` にするか尋ねる。見つからなければ尋ねない。
   - **issue を閉じる時点**（`host: github` で、`base_branch` が GitHub の default branch と違うときだけ尋ねる）：
     - **リリースで閉じる**（`close_issues: release`）— develop へのマージでは閉じず、main に入ったとき（commit メッセージの `Closes #N` により GitHub が閉じる）。間は `tixforge:merged`。このときは squash の設定を確かめる：`gh api repos/{owner}/{repo} --jq '.squash_merge_commit_title + " " + .squash_merge_commit_message'` が `PR_TITLE BLANK`（squash の commit メッセージが PR タイトルだけ）なら、squash マージで `Closes` が消えて issue が閉じなくなることを伝え、設定を変えるか「マージで閉じる」にするか尋ねる。
     - **マージで閉じる**（`close_issues: merge`）— develop へのマージで閉じる。これには Actions の `tixforge-issue-sync` が要る（無いと dev を再開したときにしか閉じない）ので、「GitHub Actions」で強く勧める。
   - `.tixforge/config.yml` に書く例：
     ```yaml
     repository:
       host: github          # github | none（ローカルのみ）
       base_branch: develop  # dev がブランチを切る元・PR の向き先
       close_issues: release # base_branch が default branch と違うときだけ：release | merge
     ```
5. **ドキュメント言語**（`language`）：「日本語（推奨・既定）」「English」を選択肢にして尋ねる（その他は自由入力）。以降のチケットと `docs/context/**` はこの言語で書き、この後の会話（質問・説明）もこの言語で行う。ここまでの会話は日本語で行う。
6. **検証コマンド**（`commands`）：dev の Implement・Review で Claude が実行する、テスト・lint・型チェックなどのコマンド。
   - 先にプロジェクトから候補を読み取る（`package.json` の scripts、`Makefile`、`justfile`、`Taskfile.yml`、`pyproject.toml`、`Cargo.toml`、`go.mod`、CI 設定（`.github/workflows/*`）など）。CI で実行しているコマンドがあれば優先して候補にする。
   - 候補を出典のファイル付きで示し、どれを使うかをユーザーに確定してもらう。**確認なしに推測のコマンドを書かない。**
   - キー名は用途を表す短い名前（`test`・`lint`・`typecheck` など）にする。書いた順に実行する。値は、**全体を `"…"` で囲むか、まったく囲まないかのどちらか**にする（一部だけを囲まない）。` #` を含むなら全体を囲む。
   - 検証コマンドが無い（テストが無い等）場合は `commands: {}` と書き、その旨を伝える（dev は検証をスキップして、そのことを記録する）。
   - 新たにラッパー（Makefile 等）は作らない。既存のコマンドをそのまま書く。
7. **commit 規約**（`docs/context/commit.md`）：dev の commit はこのファイルに従う。
   - **既にある場合**：尋ねずに使う。ただし `Source:` にパスがあれば、下の 3 点を確かめ直す（再実行のたびに）。満たさなければ示して、選び直すか本文に書くかを尋ねる。
   - **無い場合**：「既存の規約ファイルがある」「無いので作る」を尋ねる。先に `CONTRIBUTING.md`・`commitlint.config.*`・`.gitmessage`・`.github/` 配下などを見て、候補があれば選択肢の説明に含める。
     - **ある** → パスを確定する。**そのパスが ① 存在する ② リポジトリの中にある ③ git で追跡されている（`git ls-files --error-unmatch <パス>`。無視・未追跡のファイルは他のメンバーの手元に無い）**ことを確かめてから、リポジトリのルートからの相対パスで `Source:` に書く。本文はコピーしない（元のファイルとずれるため）。本文欄には、tixforge 固有の補足（あれば）だけを書く。
     - **無い** → `Source:` は空欄にし、同じファイルの本文に規約を書く。直近の `git log` の書式を読んで下書きを提案し、合意したものだけを書く（履歴が無ければ、件名の形式・言語・本文の書き方の最低限を対話で決める）。
   - どちらの場合も、commit メッセージの言語を `Language:` に書く（既存の規約に書かれていればそれに合わせる）。

   テンプレート（見出しと本文はドキュメント言語、`Source:`・`Language:` は英語の固定キー）：

   ```markdown
   # commit 規約

   Source: <既存の規約ファイルのパス。無ければ空欄>
   Language: <commit メッセージの言語>

   <!-- Source が空欄なら、ここに規約本文を書く。
        Source があれば、ここには tixforge 固有の補足だけを書く（Source と矛盾したら Source を優先する）。 -->
   ```
8. **チケット管理**（`ticket.tracker`）：create が作るチケットの種類。`host: none` なら尋ねずに `local`。`github` なら尋ねる（複数人なら GitHub を推奨：id が衝突せず、他の人が状況と担当者を見られるため）。
   - **GitHub issue と連携する**（`tracker: github`）— create で issue を作り、id は `GT-<issue 番号>`。issue が正本で、チケットの全文・状態（ラベル）・担当者を載せる。手元の `.tixforge/<id>/ticket.md` は issue から作る作業用のコピー（git 管理外）。public リポジトリでは、背景や未決事項も公開されることをここで一度伝える。
   - **ローカルのみ**（`tracker: local`）— id はローカルの連番（`LT-`）。チケットは `.tixforge/<id>/ticket.md` に置き、git で管理しない。作成者の手元にしか無く、他の人と共有できない（1 人・1 台で使う前提）。GitHub に PR を出す場合、受け入れ条件は PR 本文に転記される。public リポジトリで「コードは公開、計画は手元」にしたいときにも使える。

   `host: github` なら（`tracker` に関係なく、再実行のたびに）次を行う：
   - **事前チェック**：`bash <scripts>/github-preflight.sh`。`ok:` 以外なら出力を示し、済ませてもらってから確かめ直す。どうしても済ませられなければ、`host: none` にするか尋ねる。

   `tracker: github` なら、さらに：
   - **ラベルを作る**：`references/github/labels.md` を Read し、tixforge のラベルのうち無いものを意味と一緒に示して確認を得てから、`bash <scripts>/issue-label.sh setup` で作る。
   - **issue フォーム**（任意）：tixforge を使わない人（PM など）も GitHub の画面から issue を作るなら、チケットと同じ見出しの issue フォームを入れるか尋ねる。入れるなら `<plugin>/templates/github/ISSUE_TEMPLATE/tixforge-ticket.yml` を `.github/ISSUE_TEMPLATE/` にコピーする（ドキュメント言語が日本語以外なら、ラベル・見出し・説明をその言語に訳す。見出しはチケットの見出しと同じにする）。フォームで作られた issue は `/tixforge:ticket create #<番号>` で取り込める。
9. **レビューの要否**（`review.required`。`host: none` なら PR が無いので書かない）：「開発の人数」の答えから決める（尋ね直さない）。
   - **1 人** — `required: false`。GitHub では自分の PR を Approve できないため、`true` のままだと PR が完了にならない。CI 成功・コンフリクトなしで dev はマージ待ちにし、マージはユーザーが行う。
   - **複数人** — `required: true`（Approve 済み・CI 成功・コンフリクトなしでマージ待ち）。
   - 人数が変わったら `/tixforge:project update` で変えられることを伝える。
10. **ゲート**（`gates`）：`gates: [approach, plan, pr]` を書く（尋ねない）。書いたゲートでは必ず止まり、書いていないフェーズは、止まる条件（未解決の疑問・レビュー指摘など）が無ければ自動で通過すること、`pr` は書かなくても必ず止まることを伝える。全フェーズで止めたければ `[research, approach, plan, implement, review, pr]` にできる。
11. **作るもの**：一覧で提示してから作る（既にあるものは作らない・上書きしない）：
    - `.tixforge/config.yml` — ここまでで決めた値を書く（既にあれば、足りないキーだけを追記する）。**全てのキーを書く**（無いキーを後で推測の既定値で補わないため）。
    - `.tixforge/.gitignore` — 内容は `*`・`!.gitignore`・`!config.yml` の 3 行。`.tixforge/` の中で git 管理するのは設定だけにする。プロジェクトの `.gitignore` は触らない。
    - `docs/context/`（中身は「context」）、`docs/context/commit.md`（「commit 規約」）
    - `LICENSE`（「リポジトリ」で選んだ場合）
12. **context**：`docs/context/` に（`commit.md` 以外の）ファイルが既にある場合は、作り方を尋ねずに既存の内容を読み、足りない点を提案するにとどめる（上書きしない）。無い場合は、作り方を選んでもらう：
    - **対話で作る** — 下記「対話で作る場合」の手順で、各項目の内容をユーザーと一緒に決めて `docs/context/overview.md` を書く。
    - **自分で作る** — 下記テンプレートの見出しと記入ガイドだけを入れた `docs/context/overview.md` を作り、中身はユーザーが書く。こちらからは内容を埋めない。

    **対話で作る場合：**
    - 先にコードベース（README、パッケージ定義、ディレクトリ構成、主要なエントリポイントなど）を読み、各項目についてコードから読み取れる事実を集めておく。質問を具体的にし、答えの候補を示すためであり、読み取った内容をそのまま書くためではない。
    - テンプレートの項目を**1 つずつ**進める。項目ごとに、コードから読み取れた事実（出典のファイルを示す）と、分からない点・コードからは判断できない点を示し、ユーザーに質問する。特に「サービスの目的」と「主要なドメイン概念」はコードからは決めきれないので、ユーザーの言葉で決めてもらう。
    - その項目の文面を提示し、ユーザーが合意してから次の項目へ進む。**合意していない内容は書かない。** コードからの推測をユーザーの確認なしに事実として書かない。
    - その場で決まらない点は削らず「未決事項」に残す。ユーザーが「推測のままでよい」とした記述には `（推測）` を付ける。
    - 全項目が決まったら全体を提示し、最終確認を得てからファイルに書く。

    `docs/context/overview.md` のテンプレート（日本語版。ドキュメント言語が日本語以外なら、見出しとコメントをその言語に訳して使う）：

    ```markdown
    # プロジェクト概要

    ## サービスの目的
    <!-- 何のためのサービスか。誰のどんな課題を解決するか。 -->

    ## 主要なドメイン概念
    <!-- このサービス固有の用語・概念と、その意味や関係。 -->

    ## アーキテクチャ／ディレクトリ構成
    <!-- 全体の構成と、主要なディレクトリ・モジュールの役割。 -->

    ## 技術スタック
    <!-- 言語、フレームワーク、主要なライブラリ、インフラ。 -->

    ## 開発・テストの実行方法
    <!-- セットアップ、起動、テスト、lint のコマンド。 -->

    ## 未決事項
    <!-- まだ決まっていないこと・分からないこと。 -->
    ```

    対話で作った場合、完成したファイルには記入ガイドのコメントを残さない。自分で作る場合はコメントを残す（書くときのガイドになるため）。
13. **CLAUDE.md**：tixforge を起動していないセッションでも context を読めるように、`CLAUDE.md` から context を取り込む。
    - **先に `docs/context/overview.md` があるか確かめる。** 無ければ（既存の context が別の名前のファイルだけなど）、`@docs/context/overview.md` は書かない。`docs/context/` のどのファイルを取り込むか尋ねる（取り込まない、も選べる）。
    - 取り込むファイルが決まったら、リポジトリのルートに `CLAUDE.md` があるか、既にその `@<パス>` を含むかを確かめる。含んでいれば何もしない。
    - 「取り込む（推奨）」「取り込まない」を尋ねる。
    - **取り込む・`CLAUDE.md` が無い** — 見出し（ドキュメント言語。例「# プロジェクトの context」）と `@<パス>` の行だけで新しく作る。
    - **取り込む・`CLAUDE.md` がある** — 既存の内容は一切変えず、**末尾に**見出しと `@<パス>` の行を追記する。追記する差分を示し、確認を得てから書く（上書きはしない）。
    - **取り込まない** — 何もしない。
14. **PR テンプレート**（`host: github` のときだけ）：dev の PR フェーズは、既定の PR テンプレートがあればその見出しに沿って本文を書く。
    - 既定のテンプレート（`.github/pull_request_template.md`・`.github/PULL_REQUEST_TEMPLATE.md`・`docs/pull_request_template.md`・ルートの `pull_request_template.md`）があるか確かめる。`.github/PULL_REQUEST_TEMPLATE/`（ディレクトリ）の中のテンプレートは GitHub が自動では使わないので、既定のテンプレートとして扱わない。ディレクトリしか無ければ、そのことを伝える。
    - tixforge 用の項目を入れるか尋ねる（「入れる（推奨）」「入れない」）。項目は `<plugin>/templates/pull_request_template.md`（概要・方針・受け入れ条件・検証・関連。見出しとコメントはドキュメント言語に訳す）。
    - **入れる・既定のテンプレートが無い** — `.github/pull_request_template.md` として新しく作る。
    - **入れる・ある** — 既存の内容は一切変えず、既存のテンプレートに**無い見出しだけ**を末尾に追記する。追記する差分を示し、確認を得てから書く。
    - **入れない** — 何もしない。
15. **GitHub Actions**（`tracker: github` のときだけ）：`references/github/actions.md` を Read し、サーバー側の workflow を入れるか尋ねる（複数選択。既に `.github/workflows/` にあるものは除く）。`close_issues: merge` で `base_branch` が default branch と違うなら、`tixforge-issue-sync` は「強く推奨」と添える。選ばれたものを `<plugin>/templates/github/` から `.github/workflows/` にそのままコピーする（内容は変えない）。`tixforge-issue-guard` か `tixforge-pr-link` なら `<scripts>/messages.yml` を、`tixforge-issue-guard` なら `<scripts>/ticket-hash.sh` も `.github/tixforge/` にコピーする。作るファイルを一覧で示し、確認を得てから作る。plugin を更新しても、コピーした workflow は自動では更新されない（`/tixforge:project update` で更新できる）ことを伝える。
16. **CI**（`host: github` で `commands` が `{}` でないときだけ）：`.github/workflows/` に、検証コマンドを実行している workflow が無ければ、作るか尋ねる。CI と dev の検証を同じ内容に揃えるため。
    - 作るなら `<plugin>/templates/github/tixforge-ci.yml` を下敷きにして、ユーザーと一緒に埋める：`__BRANCHES__` は `base_branch`（GitHub の default branch と違えば両方。main + develop なら `main, develop`）、`__COMMANDS__` は `commands` を書いた順に 1 ステップずつ、`__SETUP__`（言語のセットアップ・依存のインストール）はプロジェクトのファイル（`package.json` のロックファイル・`.nvmrc`・`pyproject.toml`・`go.mod` など）から候補を作って確認する。**確認していないセットアップ手順を推測で書かない。**
    - 全文を示し、確認を得てから `.github/workflows/tixforge-ci.yml` に書く。
17. **まとめ**：作ったものを要約する。対話で作った場合は未決事項を示す。自分で作る場合は、`docs/context/overview.md` を埋めてから `/tixforge:ticket create` に進むよう促す。
18. **commit**：init で作ったもの・変えたもの（`.tixforge/.gitignore`・`.tixforge/config.yml`・`docs/context/**`・`LICENSE`・`CLAUDE.md`・PR テンプレート・`.github/ISSUE_TEMPLATE/tixforge-ticket.yml`・`.github/workflows/tixforge-*.yml`・`.github/tixforge/*`）をまとめて commit する。対象ファイルと commit メッセージ（`docs/context/commit.md` の規約に従う）を提示し、確認を得てから commit する。init が作ったもの以外の変更は含めない。
    - **commit が 1 つも無いリポジトリ**では、必ずこの時点で commit する（後回しにする選択肢を出さない）。commit が無いと、dev が `base_branch` からブランチを切れないため。context が雛形のままでもよい。
    - **既存のリポジトリで remote がある**なら、「ブランチを切って PR にする（ブランチ保護や PR 必須の運用向け）」「`base_branch` に直接 commit する」を尋ねる。PR にするなら、ブランチを切って commit し、push と PR 作成はコマンドを示して確認を得てから行う。
    - 新しく作ったリポジトリで context を自分で書く場合も、上のとおり今 commit する（書き終えた後の変更は、ユーザーが別に commit する）。
    - **main + develop を選んだ場合**：commit の後に `git branch develop`（init のファイルを両方に含めるため）。
    - 「リポジトリを作る場合」で「push する」を選んだ場合だけ、commit の後に push する（main + develop なら `git push -u origin main develop`、それ以外は `git push -u origin <base_branch>`。実行前にコマンドを示して確認を得る）。それ以外では push しない。
20. 次の一手として `/tixforge:ticket create` を案内する。
