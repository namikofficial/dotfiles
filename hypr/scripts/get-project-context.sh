#!/usr/bin/env bash
# get-project-context.sh
# Extracts current project context (file, git status, directory) for AI prompt injection
# Output: JSON object with keys: file, git_branch, git_status, directory, cwd_project

set -euo pipefail

# Get focused window or default to PWD
get_focused_dir() {
  local focused_dir
  
  # Try to get from Kitty if in Kitty window
  if [ -n "${KITTY_WINDOW_ID:-}" ]; then
    # Kitty env available; use it
    focused_dir="${PWD}"
  else
    # Fallback: use current directory
    focused_dir="${PWD}"
  fi
  
  echo "$focused_dir"
}

get_git_info() {
  local dir="$1"
  local git_root git_branch git_status
  
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    # Not in git repo
    printf '{"branch":"","status":"","root":""}\n'
    return 0
  fi
  
  git_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "")
  git_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  git_status=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l || echo "0")
  
  jq -n \
    --arg branch "$git_branch" \
    --arg status "$git_status" \
    --arg root "$git_root" \
    '{branch: $branch, uncommitted_files: ($status | tonumber), root: $root}'
}

get_focused_file() {
  local focused_dir="$1"
  local file
  
  # Try to get focused file from Hyprland
  if command -v hyprctl >/dev/null 2>&1; then
    file=$(hyprctl activewindow -j 2>/dev/null | \
      jq -r '.initialTitle // .title // ""' 2>/dev/null || true)
    
    # Extract filename if title contains path
    if [[ "$file" =~ ^(.*)/([^/]+)$ ]]; then
      file="${BASH_REMATCH[2]}"
    fi

    if [ -n "$file" ] && [ ! -e "$focused_dir/$file" ] && [ ! -e "$file" ] \
      && [[ "$file" != *.* ]] && [[ "$file" != */* ]]; then
      file=""
    fi
  fi
  
  # Fallback: prefer modified git files when available.
  if [ -z "$file" ]; then
    if git -C "$focused_dir" rev-parse --git-dir >/dev/null 2>&1; then
      file=$(git -C "$focused_dir" diff --name-only 2>/dev/null | head -1 || echo "")
      [ -z "$file" ] && file=$(git -C "$focused_dir" ls-files -m -o --exclude-standard 2>/dev/null | head -1 || echo "")
    fi
  fi

  # Final fallback: most recently modified file in the current tree.
  if [ -z "$file" ]; then
    file=$(find "$focused_dir" -path "$focused_dir/.git" -prune -o -type f -printf '%T@ %P\n' 2>/dev/null \
      | sort -nr \
      | head -1 \
      | cut -d' ' -f2- || echo "")
  fi
  
  echo "$file"
}

get_project_summary() {
  local dir="$1"

  # Check for common config files to determine project type
  local project_type="unknown"
  if [ -f "$dir/package.json" ]; then project_type="node"
  elif [ -f "$dir/pyproject.toml" ] || [ -f "$dir/requirements.txt" ]; then project_type="python"
  elif [ -f "$dir/Cargo.toml" ]; then project_type="rust"
  elif [ -f "$dir/go.mod" ]; then project_type="go"
  elif [ -f "$dir/.dotfiles" ] || [ -f "$dir/README.md" ]; then project_type="dotfiles"
  fi
  
  printf '%s\n' "$project_type"
}

# Main
main() {
  local focused_dir git_info focused_file project_type
  
  focused_dir=$(get_focused_dir)
  git_info=$(get_git_info "$focused_dir")
  focused_file=$(get_focused_file "$focused_dir")
  project_type=$(get_project_summary "$focused_dir")
  
  jq -n \
    --arg dir "$focused_dir" \
    --arg file "$focused_file" \
    --arg project_type "$project_type" \
    --argjson git "$git_info" \
    '{
       directory: $dir,
       file: $file,
       project_type: $project_type,
       git: $git
     }'
}

main "$@"
