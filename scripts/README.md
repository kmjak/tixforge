# scripts

tixforge のスクリプトの一覧（人向け。Claude は読まない）。使い方・出力・終了コードは、各ファイルの冒頭のコメントにある。ここには書かない（2 か所に書くと片方だけ直してずれるため）。

| スクリプト | 何をするか | 呼ぶもの | 触るもの |
|---|---|---|---|
| `guard.sh` | push・PR 作成・危ない git 操作と、Plan の承認前のコード編集に確認を出す／止める | hook（PreToolUse） | なし（判定だけ） |
| `session-start.sh` | 会話の要約・再開の後に、読み直すファイルを伝える | hook（SessionStart） | なし |
| `statusline.sh` | 画面の下に今の run と Status を出す | 利用者の statusline の設定（README） | なし |
| `common-rules.sh` | 共通規約（`references/common.md`）をスキルに差し込む | 3 つの SKILL.md | なし |
| `project-status.sh` | 設定・進行中の run・v2 から移すもの（`lt`）を出す | 3 つの SKILL.md・ticket の create・project の update | なし |
| `ticket-id.sh` | チケット id の取り出し・正規化・実在の確認・issue 番号への変換 | ticket・dev の手順 | なし（GitHub は読むだけ） |
| `run-state.sh` | state.md の作成・ヘッダの読み書き・巻き戻し・前の形式からの更新 | dev の手順・ticket の cancel・project の update | `.tixforge/<id>/` |
| `verify.sh` | 検証コマンドを実行し、結果を 1 行で出す | dev の手順 | `.git/tixforge/verify/`（ログ） |
| `review-input.sh` | Review の agent が読む入力（差分・チケット）を書き出す | dev の Review | `.git/tixforge/review/` |
| `pr-status.sh` | PR の状況（レビュー・CI・コンフリクト）を判定する | dev の PR | なし（GitHub は読むだけ） |
| `github-preflight.sh` | gh が使えるか（インストール・ログイン・リポジトリ）を確かめる | GitHub を使う手順 | なし |
| `issue-sync.sh` | issue の作成・状態の判定と、手元のコピー（`snapshot.md`・`editing.md`）との同期 | ticket・dev の手順・project の update | `.tixforge/<id>/`・GitHub issue |
| `issue-label.sh` | issue の状態ラベルと担当者を変える・ラベルを作る | ticket・dev の手順・project の init と update | GitHub issue |
| `ticket-hash.sh` | issue の本文のハッシュを計算する（Actions と共通） | `issue-sync.sh`・Actions | なし |
| `lib.sh` | 共通の関数（設定・state.md の読み取り、run の一覧など） | 多くのスクリプト | `.tixforge/.gitignore`（無いときに作る） |

Actions がコピーして使う文言（`messages.yml`）は、コピー先に合わせて `templates/github/tixforge/` にある。
