#!/usr/bin/env bash
#
# Install agents into an AI coding tool's agents directory.
#
# Usage:
#   ./scripts/install.sh --tool claude-code [--scope user|project] [--dest PATH] [--force]
#
# Supported tools:
#   claude-code   Install to Claude Code agents directory (default scope: user)
#
# Scopes:
#   user          ~/.claude/agents/        (available in every project)
#   project       ./.claude/agents/        (available in current project only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_SRC="$REPO_ROOT/agents"

TOOL=""
SCOPE="user"
DEST=""
FORCE=0

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)   TOOL="${2:-}"; shift 2 ;;
    --scope)  SCOPE="${2:-}"; shift 2 ;;
    --dest)   DEST="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "$TOOL" ]]; then
  echo "Error: --tool is required" >&2
  usage 1
fi

if [[ ! -d "$AGENTS_SRC" ]]; then
  echo "Error: agents directory not found at $AGENTS_SRC" >&2
  exit 1
fi

resolve_dest() {
  if [[ -n "$DEST" ]]; then
    echo "$DEST"
    return
  fi
  case "$TOOL" in
    claude-code)
      case "$SCOPE" in
        user)    echo "$HOME/.claude/agents" ;;
        project) echo "$PWD/.claude/agents" ;;
        *) echo "Error: unknown --scope '$SCOPE' (expected: user, project)" >&2; exit 1 ;;
      esac
      ;;
    *)
      echo "Error: unsupported --tool '$TOOL'" >&2
      echo "Supported tools: claude-code" >&2
      exit 1
      ;;
  esac
}

TARGET="$(resolve_dest)"
mkdir -p "$TARGET"

shopt -s nullglob
agent_files=("$AGENTS_SRC"/*.md)
shopt -u nullglob

if [[ ${#agent_files[@]} -eq 0 ]]; then
  echo "No agent files found in $AGENTS_SRC" >&2
  exit 1
fi

echo "Installing ${#agent_files[@]} agent(s) to: $TARGET"

installed=0
skipped=0
for src in "${agent_files[@]}"; do
  name="$(basename "$src")"
  dst="$TARGET/$name"
  if [[ -e "$dst" && $FORCE -eq 0 ]]; then
    if cmp -s "$src" "$dst"; then
      echo "  = $name (unchanged)"
    else
      echo "  ! $name exists and differs — skipping (use --force to overwrite)"
      skipped=$((skipped + 1))
    fi
    continue
  fi
  cp "$src" "$dst"
  echo "  + $name"
  installed=$((installed + 1))
done

echo
echo "Done. Installed: $installed, Skipped: $skipped."
if [[ $skipped -gt 0 ]]; then
  echo "Re-run with --force to overwrite skipped files."
fi
