# tixforge の開発

Claude Code の plugin。構成と開発の手順は README の「tixforge 自体を開発する」を読む。

## 確かめ方

- 変更したら `make check` を通す（lint・4 つのテスト・macOS の bash 3.2 でのテスト・`claude plugin validate`）。CI も同じものを回す。
- スクリプトは `make fmt` で整形する。手で整えない。

## スクリプト

- macOS の bash 3.2 と BWK awk、Linux の gawk・mawk のどれでも動かす。連想配列・`mapfile`・`${var,,}`、gawk だけの関数は使わない。
- guard（hook）は jq に頼らない。`lib.sh` の `json_get` で読む。
- `$var` の直後に全角文字を続けない（`${var}` と書く）。
- 結果が 1 つに決まる処理は `scripts/` に置き、`tests/` で確かめる。gh はスタブに置き換える。

## 手順ファイルとテンプレート

- `skills/`・`references/`・`agents/` でファイルの名前を変えたら、参照している側も直す（`tests/plugin.test.sh` が検出する）。
- `templates/github/` を変えたら、先頭のコメントの版数を上げる。

## commit と PR

- 1 ブランチ 1 PR、squash でマージする。`main` に直接 push しない。
- **PR のタイトル**が main の commit になり、release-please が次の version と CHANGELOG を決める。Conventional Commits の形で英語で書く（CI が検査する）：`<type>[(scope)][!]: <命令形の 1 文>`。
  - `feat`：利用者に届く機能の追加（スキル・サブコマンド・設定項目・hook・スクリプトの機能）→ マイナー
  - `fix`：利用者に届く不具合の修正・手順書の改善 → パッチ
  - `feat!` / `fix!`：`config.yml` のキーや `.tixforge/` の構造が変わり、移行が要る → メジャー
  - `docs`（README だけ）・`test`・`ci`・`build`・`chore`・`refactor`：リリースにならない
  - **`skills/`・`references/`・`agents/`・`templates/` の md や yml の変更は `docs` にしない。** 手順書は tixforge の振る舞いそのものなので `feat` か `fix` にする。`docs` にすると利用者に届かない。
- PR の中の commit は英語。件名は命令形の 1 文、本文に「なぜ」を書く（squash の本文に並ぶ）。
- 整形だけの変更は単独の PR にし、マージ後の commit を `.git-blame-ignore-revs` に足す。
- version は手で上げない。release-please のリリース PR（`chore(main): release tixforge x.y.z`）をマージすると、version・CHANGELOG・タグ・GitHub Release・Discord 通知が揃う。

## `.local/`（git の外）

- 検証で見つけた問題は、頼まれない限りコードを直さず `.local/idea/` に書く。消すときはユーザーの承認を得る。
