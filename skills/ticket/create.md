# /tixforge:ticket create — チケット作成

目的：チケットを、ユーザーとの対話で作る。**中身を書くのはユーザー**で、Claude は質問で引き出して形を整える。id は自分で決めず、共通規約のとおり自動で決める（`tracker: github` なら issue 番号から `GT-`、`local` なら連番の `LT-`）。

1. `.tixforge/config.yml` が無い（init 未実行の）場合は、その旨を伝えて `/tixforge:project init` を案内し、止まる（設定なしでは進めない）。
2. `.tixforge/config.yml` の `language`（無ければ日本語）と `ticket.tracker` を使う（SKILL.md の「現在の状態」にある）。`tracker: github` なら `references/github/create.md` を Read し、その「事前チェック」を行う。
3. **既存のチケットを指していないか**を確かめる：引数を `bash <scripts>/ticket-id.sh detect "<引数>"` に渡す（自分で解釈しない）。
   - `invalid: <語>` なら、正しい id の形（`LT-000123`・`GT-000123`・`#123`）を示して尋ねる。
   - `id: <id>` で `rest:` も空でない（説明の中に id がある）なら、先に「既存のチケット `<id>` を指しているか、説明の中で触れているだけか」を尋ねる。触れているだけなら、引数全体を説明として新しく作る（手順 4 へ）。
   - `id: <id>` なら `bash <scripts>/ticket-id.sh exists <id>` で確かめる（終了コード 3 なら、出力を示して止まる）：
     - `none` → そのチケットは無いことを伝え、`rest:` を説明として新しく作るか尋ねる。
     - `pull-request` → その番号は PR であることを伝えて止まる。
     - `issue` で、tixforge の目印の無い issue（`bash <scripts>/issue-sync.sh check <番号>` の 1 行目が `no-markers`）→ `references/github/create.md` を Read し（まだなら）、その「GitHub 上で作られた issue を取り込む」に進む。
     - それ以外（既存のチケット）→ 状態を確かめる（`LT-`：チケットの `Status: canceled` と `state.md` の `Status`、`GT-`：`bash <scripts>/issue-sync.sh check <番号>` の `closed_as`）。
       - **キャンセル済み・完了済み・手で閉じられた（`closed_as: unexpected`）** → その旨を伝え、「このチケットを参考にして新しく作るか」を尋ねる。作るなら、元のチケットを読んで示し、下の対話を元の内容から始める（そのまま写さず、変えたい点をユーザーに尋ねる）。元のチケットには触らない。
       - **それ以外** → 新規作成ではない。何もせずに、編集なら `/tixforge:ticket edit <id>`、実装なら `/tixforge:dev <id>` を案内する。**既存のチケットを黙って上書きしない。**
4. `id: none` なら、`rest:` を作りたいものの説明として扱う（空なら尋ねる）。
5. **対話で埋める**：何を作りたいか・なぜ必要かを尋ね、下記テンプレートの各項目を埋める。テンプレート内の HTML コメント（記入ガイド）は完成したチケットには残さない。
   - **中身はユーザーが書く。** Claude は項目ごとに質問し、答えを項目の形に整える。要件・受け入れ条件などの案を Claude から出すのは、ユーザーが「考えて」「案を出して」と頼んだときだけ。そのときも案は案として示し、合意したものだけ書く。
   - 抜けている観点（エラーのとき・権限・空のとき・境界の値など）は、答えを書かずに「〜のときはどうしますか？」と**質問として**指摘してよい。
   - **要件を捏造しない。** ユーザーが言っていないことは書かない。決まらない点は削らず「未決事項」に残す。
   - 受け入れ条件は「できた／できていない」を判定できる形までにする。何で確かめるか（テスト・ブラウザなど）は dev の Plan で決めるので、ここでは書かない。
   - **大きさ**：明らかに独立した機能が複数入っている（1 つの PR に収まりそうにない）なら、複数のチケットに分けて作ることを提案する。止めはしない（分けるかはユーザーが決める）。
   - **似たチケット**：タイトルが決まったら、似たものが既に無いか探して示す。`tracker: github` なら開いている issue（`gh issue list --state open --search "<タイトルの語> in:title" --json number,title`）、あれば手元の `LT-` のタイトル（`.tixforge/LT-*/ticket.md` の 1 行目）。似たものがあれば、そのチケットを edit するか、このまま新しく作るかを尋ねる。
   - 必要なら `docs/context/**` やコードを読んで、質問を具体的にする。
6. **下書きを示して合意を得る**（id はまだ決まっていないので `<ticket-id>` のまま）。一緒に「Base：<`repository.base_branch`>（既定）」を 1 行添える。hotfix などで別のブランチから作るなら、ユーザーがここで直す（質問は増やさない）。既定と違う Base になったときだけ、テンプレートの `## Base` の節を入れる。`github` なら、`references/github/create.md`「作成」の確認一覧も示し、「この内容で issue を作成する」ことへの確認を得る。
7. **id を決めて書く**：
   - `github` — `references/github/create.md`「作成」のとおり、`bash <scripts>/issue-sync.sh create` で issue と手元のコピーを作る（id もこのスクリプトが決める）。
   - `local` — `bash <scripts>/ticket-id.sh next` で id を決め、下書きの `<ticket-id>` を置き換えて `.tixforge/<ticket-id>/ticket.md` に書く。決まった id のファイルが既に存在したら、書かずに停止して尋ねる。`.tixforge/.gitignore` が無ければ先に作る（`*`・`!.gitignore`・`!config.yml` の 3 行。init が config.yml と一緒に作るので、普段は既にある）。
8. **次の一手**：作った id（`github` なら issue の URL も）を伝え、AskUserQuestion で尋ねる（単一選択）：
   - **このチケットの開発を始める** — dev は明示起動のスキルなので、呼び出さずに `<plugin>/skills/dev/SKILL.md` と `<plugin>/skills/dev/run.md` を Read し、`bash <scripts>/project-status.sh` を実行してから、その手順で `<ticket-id>` を進める。説明に「長い作業になるので、新しいセッションで `/tixforge:dev <ticket-id>` から始めると文脈を節約できる」と添える。
   - **別のチケットを作る** — このセッションのまま、手順 3 からもう一度行う（まとめて何枚も作るとき）。
   - **ここで終わる** — `/tixforge:dev <ticket-id>` で始められることを伝えて終わる。

   状態ファイル（`.tixforge/<ticket-id>/state.md`）は create では作らない（dev の役目）。
9. **commit はしない。** チケットは `LT-`・`GT-` どちらも git で管理しない（`LT-` は手元のファイル、`GT-` は issue が正本）。

チケットのテンプレート（日本語版。ドキュメント言語が日本語以外なら、見出しとコメントをその言語に訳して使う。`## Base` の見出しは英語の固定キー。該当しない項目も削らず「なし」と書く）：

```markdown
# <ticket-id>: <タイトル>

<!-- この下に入る `Status: canceled` と `Reason:` の行は /tixforge:ticket cancel だけが書く。create では書かない。
     GT- のチケットでは、最初の ## から下が全て issue の本文にそのまま載る。 -->

## 背景
<!-- なぜ必要か。解決したい問題や動機、誰が影響を受けるか。 -->

## 要件
<!-- 何をするか。1 項目 1 行の箇条書きで、実装方法ではなく振る舞いを書く。 -->

## 受け入れ条件
<!-- 何を満たせば完了か。各項目を「- [ ]」で、できた／できていないで判定できる形で書く。確かめ方は書かない（dev の Plan で決める）。 -->

## 対象外
<!-- このチケットでは扱わないこと。 -->

## 未決事項
<!-- まだ決まっていないこと。/tixforge:dev の Research で 1 項目ずつ片付ける。 -->

## Base
<!-- 既定（repository.base_branch）と違うブランチから作るときだけ、この節を入れてブランチ名を 1 行で書く（例：main）。既定なら節ごと書かない。 -->
```
