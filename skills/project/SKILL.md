---
name: project
description: tixforge のプロジェクト設定。init でこのプロジェクトを tixforge で使える状態にする（設定・検証コマンド・commit 規約・ブランチ運用・チケット管理（ローカル or GitHub issue）・GitHub Actions・context）。update で設定の値を変える・チケット管理を切り替える・テンプレートを最新にする。/tixforge:project で明示起動する。
argument-hint: "[init | update]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/project-status.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/common-rules.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/github-preflight.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-state.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/issue-label.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/issue-sync.sh *)
---

# /tixforge:project — プロジェクトの設定

引数：`$ARGUMENTS`

## 現在の状態（起動時に自動で取得）

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/project-status.sh`

## 置き場所

- plugin：`${CLAUDE_PLUGIN_ROOT}`（手順では `<plugin>` と書く）
- スクリプト：`${CLAUDE_PLUGIN_ROOT}/scripts/`（手順では `<scripts>` と書く）

## サブコマンド

| 起動 | 内容 | 手順ファイル |
|------|------|--------------|
| `/tixforge:project init` | プロジェクトを初期化する。足りない設定を足すだけで、既にある値は変えない（再実行しても安全） | `${CLAUDE_SKILL_DIR}/init.md` |
| `/tixforge:project update` | 設定の値を変える・チケット管理を切り替える・テンプレートと Actions を最新にする | `${CLAUDE_SKILL_DIR}/update.md` |
| `/tixforge:project` | `.tixforge/config.yml` が無ければ init。あれば init・update のどちらかを選択肢で尋ねる（単一選択） | — |

それ以外の引数が渡されたら実行せず、使えるサブコマンドを示して止まる。

## 手順ファイルと参照ファイル（必須）

サブコマンドが決まったら、**作業を始める前に必ずその手順ファイルを Read する**。読まずに記憶や推測で進めない。参照ファイルは、手順が読むよう指示したときだけ読む。

| 参照ファイル | 読むとき |
|--------------|----------|
| `${CLAUDE_PLUGIN_ROOT}/references/github/<名前>.md` | 手順が指示したファイルだけ（`labels`・`actions`・`create`） |

以下の共通規約は、このスキルのすべてに適用する。

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/common-rules.sh`
