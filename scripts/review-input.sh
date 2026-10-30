#!/usr/bin/env bash
# Write what the Review agents read: the change of this run, as files, so
# the agents need no Bash (they stay read-only) and the diff does not pass
# through the implementing session's context.
#
#   review-input.sh <id> <base> [--since <commit>]
#
# The change is measured from the fork point of HEAD and the base. When
# origin/<base> exists and forks later than the local <base> (the local one
# is behind), origin/<base> is used, so commits other people pushed to the
# base are not counted as part of this run. A local <base> that is ahead of
# origin (unpushed merges, host: none) is used as is.
#
# Files go under <git dir>/tixforge/review/<id>/ (outside .tixforge/, which the
# reviewers must not read) and are replaced on every call:
#   diff.patch   git diff <fork point>..HEAD
#   log.txt      git log --stat <fork point>..HEAD
#   files.txt    git diff --name-status <fork point>..HEAD
#   delta.patch  git diff <commit>..HEAD (only with --since: the change since
#                the previous review round; removed otherwise)
# Prints the paths, one per line, in that order.
set -euo pipefail

usage() {
  echo "usage: review-input.sh <id> <base> [--since <commit>]" >&2
  exit 2
}
[ $# -eq 2 ] || [ $# -eq 4 ] || usage
id=$1 base=$2 since=""
if [ $# -eq 4 ]; then
  [ "$3" = --since ] || usage
  since=$4
  git rev-parse --verify -q "$since^{commit}" > /dev/null || {
    echo "unknown commit: $since" >&2
    exit 2
  }
fi

git rev-parse --verify -q "$base" > /dev/null || {
  echo "unknown base: $base" >&2
  exit 2
}
fork=$(git merge-base "$base" HEAD)
remote="refs/remotes/origin/${base#origin/}"
if git rev-parse --verify -q "$remote" > /dev/null; then
  rfork=$(git merge-base "$remote" HEAD)
  # The later of the two fork points: the other one is its ancestor.
  if [ "$rfork" != "$fork" ] && git merge-base --is-ancestor "$fork" "$rfork"; then
    fork=$rfork
  fi
fi

dir="$(git rev-parse --absolute-git-dir)/tixforge/review/$id"
mkdir -p "$dir"
git diff "$fork"..HEAD > "$dir/diff.patch"
git log --stat "$fork"..HEAD > "$dir/log.txt"
git diff --name-status "$fork"..HEAD > "$dir/files.txt"
printf '%s\n' "$dir/diff.patch" "$dir/log.txt" "$dir/files.txt"
if [ -n "$since" ]; then
  git diff "$since"..HEAD > "$dir/delta.patch"
  printf '%s\n' "$dir/delta.patch"
else
  rm -f "$dir/delta.patch"
fi
