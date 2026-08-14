#!/usr/bin/env bash
set -euo pipefail

if [[ ${CODESPACES:-} == true ]] && git remote get-url origin >/dev/null 2>&1; then
  git remote remove origin
fi
