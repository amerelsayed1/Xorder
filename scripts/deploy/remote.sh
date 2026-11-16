#!/usr/bin/env bash
# Run one command on the production VPS over SSH, using SSH_HOST / SSH_USER /
# SSH_KEY (and optional SSH_PORT) from the environment. Meant to be started by
# `doppler run -- scripts/deploy/remote.sh "<remote command>"`; the Makefile does this.
# The key is written to a private temp file and removed on exit. It is never printed.
set -euo pipefail

: "${SSH_HOST:?SSH_HOST is not set (run through: doppler run -- ...)}"
: "${SSH_USER:?SSH_USER is not set}"
: "${SSH_KEY:?SSH_KEY is not set or empty}"
[ $# -ge 1 ] || { echo "usage: remote.sh '<remote command>'" >&2; exit 2; }

KEY_FILE="$(mktemp)"
trap 'rm -f "$KEY_FILE"' EXIT
chmod 600 "$KEY_FILE"
printf '%s\n' "$SSH_KEY" > "$KEY_FILE"

ssh -i "$KEY_FILE" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
    -p "${SSH_PORT:-22}" "$SSH_USER@$SSH_HOST" "$1"
