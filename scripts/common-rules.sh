#!/usr/bin/env bash
# Print references/common.md, the rules shared by the project, ticket and
# dev skills. Each SKILL.md injects it with !`...` when the skill starts
# (a plain `cat` of a file outside the working directory is refused there).
# Always exits 0: a failing injected command would abort the skill.
here=$(cd "$(dirname "$0")" && pwd)
cat "$here/../references/common.md" 2> /dev/null || echo "（共通規約を読めませんでした: $here/../references/common.md）"
exit 0
