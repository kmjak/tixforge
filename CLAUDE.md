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

- commit メッセージは英語。件名は命令形の 1 文（接頭辞なし）、本文に「なぜ」を書く。
- 整形だけの commit は単独にし、`.git-blame-ignore-revs` に足す。
- 1 ブランチ 1 PR、merge commit でマージする。`main` に直接 push しない。
- version を上げるときは `.claude-plugin/plugin.json` だけを変える `Version x.y.z` の commit にする。

## `.local/`（git の外）

- `.local/idea/`：方針を決めていない案。`.local/v2/`：今すぐ直すもの。`.local/v3/`：次の大きな版で入れるもの。
- 検証で見つけた問題は、頼まれない限りコードを直さず `.local/idea/` に書く。消すときはユーザーの承認を得る。
