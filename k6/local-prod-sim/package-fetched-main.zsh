#!/bin/zsh
set -euo pipefail

repo=""
output=""
while (( $# )); do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) print -u2 -- "unknown argument"; exit 2 ;;
  esac
done
[[ -n "$repo" && -n "$output" ]] || { print -u2 -- "missing --repo or --output"; exit 2; }
git -C "$repo" rev-parse --git-dir >/dev/null

# FETCH_HEAD is resolved once. Every later read is from this immutable object;
# neither origin/main nor the worktree is an input after this point.
git -C "$repo" fetch origin main >/dev/null
pinned_sha="$(git -C "$repo" rev-parse 'FETCH_HEAD^{commit}')"
commit_time="$(git -C "$repo" show -s --format=%cI "$pinned_sha")"
temporary="${output}.tmp.$$"
trap 'rm -f -- "$temporary"' EXIT INT TERM
git -C "$repo" archive --format=tar --output="$temporary" "$pinned_sha" -- \
  package.json package-lock.json prisma.config.ts src prisma
chmod 600 "$temporary"
mv -f -- "$temporary" "$output"
trap - EXIT INT TERM
node -e 'process.stdout.write(JSON.stringify({schemaVersion:"daily-k6-source-v1",sha:process.argv[1],commitTime:process.argv[2]})+"\n")' \
  "$pinned_sha" "$commit_time"
