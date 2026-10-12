#!/usr/bin/env bash
set -euo pipefail

task_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$task_root"

if [[ -z "${DEEPSEEK_API_KEY:-}" && -f .local/deepseek.env ]]; then
  set -a
  source .local/deepseek.env
  set +a
fi

if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
  printf '%s\n' '请通过环境变量或 .local/deepseek.env 配置 DEEPSEEK_API_KEY。' >&2
  exit 64
fi

export DEEPSEEK_API_KEY
export NOVEL_DATA_DIR="${NOVEL_DATA_DIR:-.local/deepseek-data}"
exec dart run agent/bin/prototype_agent.dart
