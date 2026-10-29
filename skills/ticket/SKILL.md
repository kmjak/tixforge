---
name: ticket
description: tixforge のチケット操作。create（チケットを対話で作る。GitHub 連携時は issue を作り、issue 番号から id を決める）、edit（チケットを編集し、進行中の run はフェーズを戻す）、cancel（チケットをキャンセル済みにする）。/tixforge:ticket で明示起動する。
argument-hint: "[create [作りたいもの] | edit <ticket-id> | cancel <ticket-id> | 作りたいもの]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/project-status.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/common-rules.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/github-preflight.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/ticket-id.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-state.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/issue-sync.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/issue-label.sh *)
---

# /tixforge:ticket — チケット

引数：`$ARGUMENTS`

## 現在の状態（起動時に自動で取得）

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/project-status.sh`

## 置き場所

- plugin：`${CLAUDE_PLUGIN_ROOT}`（手順では `<plugin>` と書く）
- スクリプト：`${CLAUDE_PLUGIN_ROOT}/scripts/`（手順では `<scripts>` と書く）

## サブコマンド

| 起動 | 内容 | 手順ファイル |
|------|------|--------------|
| `/tixforge:ticket create [作りたいもの]` | チケットを対話で作る。id は自動で決まる（共通規約） | `${CLAUDE_SKILL_DIR}/create.md` |
| `/tixforge:ticket edit <ticket-id>` | 既存のチケットを対話で書き換える。進行中の run があれば、影響に応じてフェーズを戻す | `${CLAUDE_SKILL_DIR}/edit.md` |
| `/tixforge:ticket cancel <ticket-id>` | チケットを `canceled` として残し、以後どのサブコマンドからも操作しない | `${CLAUDE_SKILL_DIR}/cancel.md` |
| `/tixforge:ticket <作りたいもの>` | create と同じ。引数全体を作りたいものの説明として扱う | `${CLAUDE_SKILL_DIR}/create.md` |
| `/tixforge:ticket` | 選択肢を出す（下記） | — |

**引数の解釈：** 先頭の語が `create` / `edit` / `cancel` ならそのサブコマンド。残りは、edit・cancel ではチケット id、create では作りたいものの説明（省略可）として扱う。先頭の語がサブコマンド名でなければ、引数全体を create の説明として扱う。

### 引数が無い場合（`/tixforge:ticket`）

AskUserQuestion で、create・edit・cancel から 1 つを選んでもらう（単一選択）。edit・cancel を選んだら、対象のチケット id を尋ねる。推測で決めない。

## 手順ファイルと参照ファイル（必須）

サブコマンドが決まったら、**作業を始める前に必ずその手順ファイルを Read する**。読まずに記憶や推測で進めない。**他のサブコマンドの手順ファイルは読まない。** 参照ファイルは、手順が読むよう指示したときだけ読む。

| 参照ファイル | 読むとき |
|--------------|----------|
| `${CLAUDE_PLUGIN_ROOT}/references/github/<名前>.md` | 手順が指示したファイルだけ（`GT-` のチケットを扱うとき） |
| `${CLAUDE_PLUGIN_ROOT}/skills/dev/rewind.md` | チケットが変わり、進行中の run のフェーズを戻すか決めるとき（edit が指示する。「チケットが変わったとき」の節） |

以下の共通規約は、このスキルのすべてに適用する。

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/common-rules.sh`
