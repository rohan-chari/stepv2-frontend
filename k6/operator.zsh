#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
exec node "$script_dir/internal/operator.mjs" "$@"
