# tixforge の開発

Claude Code の plugin。利用者向けの説明は README にある。

## 準備と確かめ方

```sh
brew install shellcheck shfmt actionlint zizmor editorconfig-checker jq   # 初回だけ
git config blame.ignoreRevsFile .git-blame-ignore-revs   # 初回だけ。整形だけの commit を blame から外す
claude --plugin-dir .                     # 作業ツリーをそのまま読み込む
make check                                # PR の前に。lint・4 つのテスト・macOS の bash 3.2 でのテスト・claude plugin validate
make fmt                                  # shfmt で整形（設定は .editorconfig）
```

- CI（`.github/workflows/test.yml`）は、lint と 4 つのテストを回し、テストは gawk・mawk・macOS（bash 3.2 と BWK awk）のそれぞれで動かす。ブランチルールで必須にするのは `result` だけ。
- `scripts.test.sh` には jq が要る。`json-get.test.sh` は jq があれば、`json_get` を jq の結果とも突き合わせる。

## 構成

- `skills/<名前>/SKILL.md` が起動時に読まれ、共通規約（`references/common.md`）を `scripts/common-rules.sh` で差し込む。
- 手順は `skills/<名前>/*.md` と `references/github/*.md` に分け、使う場面で読む。

## ルール

ルールを足すときは、機械的に確かめられるものはテストにして「テストで守るもの」に、判断を要するものは理由と一緒に「判断を要するもの」に書く。

### 判断を要するもの

- 結果が 1 つに決まる処理と、一字も変えずに写すべき処理は `scripts/` に置き、`tests/` で確かめる。gh はスタブに置き換える。手順ファイルの文章は、守られるとは限らないため。
- 手順ファイルは使う場面で Read させ、SKILL.md と共通規約は短く保つ。毎回読まれるため。
- `templates/github/` を変えたら、先頭のコメントの版数（`(v3)` など）を上げる。`/tixforge:project update` は版数で更新の有無を判断する。
- state.md の形を変えたら、`run-state.sh` の `STATE_FORMAT` を上げ、`migrate` に前の形式から移す段を足す。plugin を更新しても、利用者の手元の state.md は書き換わらないため。

### テストで守るもの

| ルール | 守るもの |
|---|---|
| macOS の bash 3.2 と BWK awk、Linux の gawk・mawk のどれでも動かす。連想配列・`mapfile`・`${var,,}`、gawk だけの関数は使わない | `make test-bash32`・CI の gawk・mawk・macOS の行列 |
| guard（hook）は jq に頼らない。`lib.sh` の `json_get` で読む | `tests/guard.test.sh`（jq の無い PATH で動かす）・`tests/json-get.test.sh` |
| スクリプトの中で、`$var` の直後に全角文字を続けない（`${var}` と書く） | `tests/scripts.test.sh` の「all scripts」 |
| `skills/`・`references/`・`agents/` でファイルの名前を変えたら、参照している側も直す | `tests/plugin.test.sh` |
| スクリプトは `make fmt` で整形する。手で整えない | `make lint` の `shfmt -d` |
| PR のタイトルは Conventional Commits の形にする（下の「commit と PR」） | CI の `pr-title` |
| v2 が残した state.md を `migrate` で移せる（テストの中の v2 の state.md は直さない）。v2 が英語のコメントで閉じた issue を読める。v2 の `LT-`・`tracker: local`・`host: none` は「移行が要る」と示し、`LT-` の id は移行を案内するエラーにする | `tests/scripts.test.sh` の「v2 data」・issue-sync.sh・project-status.sh・ticket-id.sh の節 |

## commit と PR

- 1 ブランチ 1 PR、squash でマージする。`main` に直接 push しない。
- **PR のタイトル**が main の commit になり、release-please が次の version と CHANGELOG を決める。Conventional Commits の形で英語で書く：`<type>[(scope)][!]: <命令形の 1 文>`。
  - `feat`：利用者に届く機能の追加（スキル・サブコマンド・設定項目・hook・スクリプトの機能）→ マイナー
  - `fix`：利用者に届く不具合の修正・手順書の改善 → パッチ
  - `feat!` / `fix!`：`config.yml` のキーや `.tixforge/` の構造が変わり、移行が要る → メジャー
  - `docs`（README だけ）・`test`・`ci`・`build`・`chore`・`refactor`：リリースにならない
  - **`skills/`・`references/`・`agents/`・`templates/` の md や yml の変更は `docs` にしない。** 手順書は tixforge の振る舞いそのものなので `feat` か `fix` にする。`docs` にすると利用者に届かない。
- PR の中の commit は英語。件名は命令形の 1 文、本文に「なぜ」を書く（squash の本文に並ぶ）。
- 整形だけの変更は単独の PR にし、マージ後の commit を `.git-blame-ignore-revs` に足す。
- **リリース**：利用者に届くのは、`.claude-plugin/plugin.json` の `version` を上げたものだけ。version は手で上げない。main に入るたびに release-please（`.github/workflows/release-please.yml`）がリリース PR（`chore(main): release tixforge x.y.z`）を更新し、それをマージすると version・CHANGELOG・`tixforge--v<version>` のタグ・GitHub Release・Discord 通知が揃う。

## `.local/`（git の外）

- 検証で見つけた問題は、頼まれない限りコードを直さず `.local/idea/` に書く。消すときはユーザーの承認を得る。
