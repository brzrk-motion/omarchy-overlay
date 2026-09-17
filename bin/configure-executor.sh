#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

export PATH="/usr/bin:$HOME/.local/bin:$PATH"
command -v node >/dev/null 2>&1 || die "Node.js is required for Executor."
command -v npm >/dev/null 2>&1 || die "npm is required for Executor."
node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
(( node_major >= 20 )) || die "Executor requires Node.js 20 or newer."

if ! command -v executor >/dev/null 2>&1; then
  log "Installing Executor"
  npm_prefix="$HOME/.local"
  npm install --prefix="$npm_prefix" --global executor
  ensure_state
  grep -qxF executor "$MANIFEST_DIR/npm-added.txt" 2>/dev/null ||
    printf '%s\n' executor >> "$MANIFEST_DIR/npm-added.txt"
  printf '%s\n' "$npm_prefix" > "$MANIFEST_DIR/npm-prefix"
fi

executor install

add_remote() {
  local slug="$1" name="$2" endpoint="$3"
  local output
  if ! output=$(executor call executor mcp addServer \
    "{\"transport\":\"remote\",\"name\":\"$name\",\"endpoint\":\"$endpoint\",\"slug\":\"$slug\"}" 2>&1); then
    grep -qi 'already_exists\|already exists' <<<"$output" || {
      printf '%s\n' "$output" >&2
      return 1
    }
  fi
}

add_stdio() {
  local slug="$1" name="$2" args_json="$3"
  local output
  if ! output=$(executor call executor mcp addServer \
    "{\"transport\":\"stdio\",\"name\":\"$name\",\"command\":\"npx\",\"args\":$args_json,\"slug\":\"$slug\"}" 2>&1); then
    grep -qi 'already_exists\|already exists' <<<"$output" || {
      printf '%s\n' "$output" >&2
      return 1
    }
  fi
}

log "Reconciling Executor MCP integrations"
add_remote context7 Context7 https://mcp.context7.com/mcp
add_stdio chrome-devtools "Chrome DevTools" '["-y","chrome-devtools-mcp@latest"]'
add_stdio shadcn shadcn '["-y","shadcn@latest","mcp"]'

executor tools integrations
