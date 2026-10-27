#!/usr/bin/env sh
set -eu

cd "$(git rev-parse --show-toplevel)"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Working tree is not clean. Commit or stash changes first." >&2
    exit 1
fi

git fetch origin --prune
git switch main
git pull --ff-only origin main

git branch --merged main | sed 's/^[* ]*//' | while read -r branch; do
    case "$branch" in
        ""|main) continue ;;
    esac
    git branch -d "$branch"
done

echo "Local merged branches cleaned. Remote branches must be deleted explicitly after their PRs are merged."
