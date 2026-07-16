#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Security check skipped: source archive has no Git metadata."
    exit 0
fi

forbidden_files="$(git ls-files -- \
    '.env' \
    '.env.*' \
    '.vscode/*' \
    '.build/*' \
    'releases/*' \
    'Packaging/AppIcon/*' \
    '*.jsonl' \
    '*.sqlite' \
    '*.sqlite3' \
    '*.log')"

if [[ -n "$forbidden_files" ]]; then
    echo "Security check failed: local or generated files are tracked:"
    printf '%s\n' "$forbidden_files"
    exit 1
fi

secret_pattern='(sk-or-v1-[A-Za-z0-9_-]{32,}|sk-(proj-|svcacct-)?[A-Za-z0-9_-]{32,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----)'
secret_files="$(git grep -IlE "$secret_pattern" -- . || true)"

if [[ -n "$secret_files" ]]; then
    echo "Security check failed: secret-like values found in tracked files:"
    printf '%s\n' "$secret_files"
    exit 1
fi

history_matches="$(git log --all -G"$secret_pattern" --format='%h' -- . | sort -u)"
if [[ -n "$history_matches" ]]; then
    echo "Security check failed: secret-like values found in Git history."
    echo "Review these commits locally without printing credential values:"
    printf '%s\n' "$history_matches"
    exit 1
fi

personal_path_files="$(git grep -IlE '(/Users/[^/]+/|/home/[^/]+/)' -- . ':!scripts/security-check.sh' || true)"
if [[ -n "$personal_path_files" ]]; then
    echo "Security check failed: machine-specific absolute paths found:"
    printf '%s\n' "$personal_path_files"
    exit 1
fi

personal_email_pattern='[A-Za-z0-9._%+-]+@(gmail|googlemail|outlook|hotmail|icloud|qq|163)\.[A-Za-z]{2,}'
personal_email_files="$(git grep -IlE "$personal_email_pattern" -- . ':!scripts/security-check.sh' || true)"
if [[ -n "$personal_email_files" ]]; then
    echo "Security check failed: a personal email address is present:"
    printf '%s\n' "$personal_email_files"
    exit 1
fi

conflict_files="$(git grep -IlE '^(<<<<<<<|=======|>>>>>>>)' -- . || true)"
if [[ -n "$conflict_files" ]]; then
    echo "Security check failed: unresolved conflict markers found:"
    printf '%s\n' "$conflict_files"
    exit 1
fi

echo "Repository security checks passed."
