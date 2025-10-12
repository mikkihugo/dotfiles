#!/bin/bash
# AI Development Tools - One-time installation on login with version display
# Skip automated AI tool checks inside VS Code unless explicitly re-enabled
if [[ "${TERM_PROGRAM:-}" == "vscode" && -z "${AI_TOOLS_ENABLE_VSCODE:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi


# Ensure local bin directory exists
mkdir -p "$HOME/.local/bin"

# Guarantee ~/.local/bin is in PATH before checking for installed tools
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Function to get tool version
get_tool_version() {
  local binary="$1"
  local version_flag="${2:---version}"

  if command -v "$binary" >/dev/null 2>&1; then
    local version
    version=$($binary $version_flag 2>/dev/null | head -1)
    echo "${version:-unknown}"
  else
    echo "not installed"
  fi
}

# Function to install CLI tool if missing
install_ai_tool() {
  local binary="$1"
  local package="$2"
  local version_flag="${3:---version}"
  local marker_file="$HOME/.local/share/ai-tools/${binary}.installed"

  if [[ -f "$marker_file" ]]; then
    local version
    version=$(get_tool_version "$binary" "$version_flag")
    if [[ "$version" == "not installed" ]]; then
      echo "⚠️  $binary marker present but command not found. Ensure $HOME/.local/bin is on PATH." >&2
    else
      echo "✅ $binary: $version"
    fi
    return 0
  fi

  if command -v "$binary" >/dev/null 2>&1; then
    mkdir -p "$(dirname "$marker_file")"
    touch "$marker_file"
    local version
    version=$(get_tool_version "$binary" "$version_flag")
    echo "✅ $binary: $version"
    return 0
  fi

  echo "🛠 Installing $binary CLI..."
  mkdir -p "$(dirname "$marker_file")"

  if npm install -g --prefix ~/.local "$package"; then
    touch "$marker_file"
    hash -r
    local version
    version=$(get_tool_version "$binary" "$version_flag")
    echo "✅ $binary CLI installed: $version"
  else
    echo "⚠️  Failed to install $binary CLI ($package)." >&2
    return 1
  fi
}

# Function to install cursor-agent specifically
install_cursor_agent() {
  local marker_file="$HOME/.local/share/ai-tools/cursor-agent.installed"

  if [[ -f "$marker_file" ]]; then
    local version
    version=$(get_tool_version "cursor-agent" "--version")
    if [[ "$version" == "not installed" ]]; then
      echo "⚠️  cursor-agent marker present but command not found. Ensure $HOME/.local/bin is on PATH." >&2
    else
      echo "✅ cursor-agent: $version"
    fi
    return 0
  fi

  if command -v cursor-agent >/dev/null 2>&1; then
    mkdir -p "$(dirname "$marker_file")"
    touch "$marker_file"
    local version
    version=$(get_tool_version "cursor-agent" "--version")
    echo "✅ cursor-agent: $version"
    return 0
  fi

  echo "🛠 Installing cursor-agent CLI..."
  mkdir -p "$(dirname "$marker_file")"

  if command -v curl >/dev/null 2>&1 && curl -fsSL https://cursor.com/install | bash -s -- --yes; then
    touch "$marker_file"
    hash -r
    local version
    version=$(get_tool_version "cursor-agent" "--version")
    echo "✅ cursor-agent CLI installed: $version"
  else
    echo "⚠️  Failed to install cursor-agent CLI." >&2
    return 1
  fi
}

# Function to force update all AI tools
update_ai_tools() {
  echo "🔄 Updating AI tools..."
  rm -f ~/.local/share/ai-tools/*.installed
  install_ai_tool "claude" "@anthropic-ai/claude-code@latest" "--version"
  install_ai_tool "codex" "@openai/codex@latest" "--version"
  install_ai_tool "gemini" "@google/gemini-cli@latest" "--version"
  install_ai_tool "copilot" "@github/copilot@latest" "--version"
  install_cursor_agent
}

# Install AI tools once per session with version display
install_ai_tool "claude" "@anthropic-ai/claude-code@latest" "--version"
install_ai_tool "codex" "@openai/codex@latest" "--version"
install_ai_tool "gemini" "@google/gemini-cli@latest" "--version"
install_ai_tool "copilot" "@github/copilot@latest" "--version"
install_cursor_agent
