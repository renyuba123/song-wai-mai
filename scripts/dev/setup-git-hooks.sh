#!/usr/bin/env sh
set -eu

cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push 2>/dev/null || true
echo "Git hooks enabled: core.hooksPath=.githooks"
