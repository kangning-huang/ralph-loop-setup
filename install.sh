#!/bin/bash

# Ralph Loop Setup Plugin Installer
# Multi-platform installer for Claude Code, Gemini CLI, and other Agent Skills-compatible platforms

set -e

REPO_BASE="https://raw.githubusercontent.com/kangning-huang/ralph-loop-setup/main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Platform configurations
# Claude Code requires plugins to be in plugins/local/ directory
CLAUDE_PLUGIN_DIR="$HOME/.claude/plugins/local/ralph-loop-setup"
GEMINI_SKILL_DIR="$HOME/.gemini/skills"

# Flags
INSTALL_CLAUDE=false
INSTALL_GEMINI=false
INSTALL_ALL=false
AUTO_DETECT=true

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Install Ralph Loop Setup plugin for AI coding platforms."
    echo ""
    echo "Options:"
    echo "  --claude    Install for Claude Code only"
    echo "  --gemini    Install for Gemini CLI only"
    echo "  --all       Install for all supported platforms"
    echo "  --help      Show this help message"
    echo ""
    echo "If no options specified, auto-detects available platforms and installs for all."
    echo ""
    echo "Examples:"
    echo "  curl -sL .../install.sh | bash                    # Auto-detect platforms"
    echo "  curl -sL .../install.sh | bash -s -- --claude     # Claude Code only"
    echo "  curl -sL .../install.sh | bash -s -- --gemini     # Gemini CLI only"
    echo "  curl -sL .../install.sh | bash -s -- --all        # All platforms"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --claude)
            INSTALL_CLAUDE=true
            AUTO_DETECT=false
            shift
            ;;
        --gemini)
            INSTALL_GEMINI=true
            AUTO_DETECT=false
            shift
            ;;
        --all)
            INSTALL_ALL=true
            AUTO_DETECT=false
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Auto-detect platforms if no specific flags given
detect_platforms() {
    local detected=0

    # Check for Claude Code
    if [ -d "$HOME/.claude" ] || command -v claude &> /dev/null; then
        INSTALL_CLAUDE=true
        detected=$((detected + 1))
    fi

    # Check for Gemini CLI
    if [ -d "$HOME/.gemini" ] || command -v gemini &> /dev/null; then
        INSTALL_GEMINI=true
        detected=$((detected + 1))
    fi

    if [ $detected -eq 0 ]; then
        echo -e "${YELLOW}No platforms auto-detected. Installing for Claude Code by default.${NC}"
        INSTALL_CLAUDE=true
    fi
}

# Register plugin in Claude Code settings.json
register_claude_plugin() {
    local settings_file="$HOME/.claude/settings.json"
    local plugin_name="ralph-loop-setup"

    # Ensure .claude directory exists
    mkdir -p "$HOME/.claude"

    # Check if jq is available
    if command -v jq &> /dev/null; then
        if [ -f "$settings_file" ]; then
            # File exists - add plugin to enabledPlugins
            local tmp_file=$(mktemp)
            jq --arg plugin "$plugin_name" '.enabledPlugins[$plugin] = true' "$settings_file" > "$tmp_file" && mv "$tmp_file" "$settings_file"
        else
            # File doesn't exist - create it
            echo "{\"enabledPlugins\":{\"$plugin_name\":true}}" | jq '.' > "$settings_file"
        fi
        echo "  Registered plugin in: $settings_file"
    else
        # Fallback without jq - simple file creation/update
        if [ ! -f "$settings_file" ]; then
            # Create new settings file
            cat > "$settings_file" << 'SETTINGS_EOF'
{
  "enabledPlugins": {
    "ralph-loop-setup": true
  }
}
SETTINGS_EOF
            echo "  Created settings file: $settings_file"
        elif grep -q '"enabledPlugins"' "$settings_file"; then
            # enabledPlugins exists - check if plugin already registered
            if ! grep -q '"ralph-loop-setup"' "$settings_file"; then
                # Add plugin to existing enabledPlugins (simple sed approach)
                sed -i.bak 's/"enabledPlugins"[[:space:]]*:[[:space:]]*{/"enabledPlugins": { "ralph-loop-setup": true,/' "$settings_file"
                rm -f "$settings_file.bak"
                echo "  Added plugin to: $settings_file"
            else
                echo "  Plugin already registered in: $settings_file"
            fi
        else
            echo -e "${YELLOW}  Warning: Could not auto-register plugin. Please install jq or manually add to settings.json${NC}"
            echo "  Add this to ~/.claude/settings.json:"
            echo '  {"enabledPlugins": {"ralph-loop-setup": true}}'
        fi
    fi
}

# Install for Claude Code
install_claude() {
    echo -e "${GREEN}Installing for Claude Code...${NC}"

    local plugin_dir="$CLAUDE_PLUGIN_DIR"

    # Create plugin directory structure
    # ~/.claude/plugins/local/ralph-loop-setup/
    # ├── .claude-plugin/
    # │   └── plugin.json
    # ├── commands/
    # │   └── ralph-loop-setup.md
    # └── resources/
    #     ├── ralph_wiggum_loop.sh
    #     ├── todolist-template.json
    #     └── progress-template.txt

    mkdir -p "$plugin_dir/.claude-plugin"
    mkdir -p "$plugin_dir/commands"
    mkdir -p "$plugin_dir/resources"

    # Download plugin.json
    curl -sL "$REPO_BASE/skill/.claude-plugin/plugin.json" -o "$plugin_dir/.claude-plugin/plugin.json"

    # Download command file (the skill definition)
    curl -sL "$REPO_BASE/skill/commands/ralph-loop-setup.md" -o "$plugin_dir/commands/ralph-loop-setup.md"

    # Download resources
    curl -sL "$REPO_BASE/skill/ralph-loop-setup/resources/ralph_wiggum_loop.sh" -o "$plugin_dir/resources/ralph_wiggum_loop.sh"
    curl -sL "$REPO_BASE/skill/ralph-loop-setup/resources/todolist-template.json" -o "$plugin_dir/resources/todolist-template.json"
    curl -sL "$REPO_BASE/skill/ralph-loop-setup/resources/progress-template.txt" -o "$plugin_dir/resources/progress-template.txt"

    # Make script executable
    chmod +x "$plugin_dir/resources/ralph_wiggum_loop.sh"

    # Register the plugin in settings.json
    register_claude_plugin

    echo "  Plugin installed at: $plugin_dir"
    echo "  Command: /ralph-loop-setup"
}

# Install for Gemini CLI
install_gemini() {
    echo -e "${GREEN}Installing for Gemini CLI...${NC}"

    local skill_dir="$GEMINI_SKILL_DIR"
    local ralph_dir="$skill_dir/ralph-loop-setup"

    # Create directories
    mkdir -p "$ralph_dir/resources"

    # Download skill file (SKILL.md format for Gemini)
    curl -sL "$REPO_BASE/skill/SKILL.md" -o "$ralph_dir/SKILL.md"

    # Download resources
    curl -sL "$REPO_BASE/skill/ralph-loop-setup/resources/ralph_wiggum_loop.sh" -o "$ralph_dir/resources/ralph_wiggum_loop.sh"
    curl -sL "$REPO_BASE/skill/ralph-loop-setup/resources/todolist-template.json" -o "$ralph_dir/resources/todolist-template.json"
    curl -sL "$REPO_BASE/skill/ralph-loop-setup/resources/progress-template.txt" -o "$ralph_dir/resources/progress-template.txt"

    # Make script executable
    chmod +x "$ralph_dir/resources/ralph_wiggum_loop.sh"

    echo "  Installed: $ralph_dir/SKILL.md"
    echo "  Resources: $ralph_dir/resources/"
}

# Main installation logic
main() {
    echo "Ralph Loop Setup Plugin Installer"
    echo "=================================="
    echo ""

    # Handle --all flag
    if [ "$INSTALL_ALL" = true ]; then
        INSTALL_CLAUDE=true
        INSTALL_GEMINI=true
    fi

    # Auto-detect if no specific platforms requested
    if [ "$AUTO_DETECT" = true ]; then
        echo "Auto-detecting platforms..."
        detect_platforms
        echo ""
    fi

    local installed=0

    # Install for each selected platform
    if [ "$INSTALL_CLAUDE" = true ]; then
        install_claude
        installed=$((installed + 1))
        echo ""
    fi

    if [ "$INSTALL_GEMINI" = true ]; then
        install_gemini
        installed=$((installed + 1))
        echo ""
    fi

    # Summary
    if [ $installed -gt 0 ]; then
        echo -e "${GREEN}Installation complete!${NC}"
        echo ""
        echo "Usage:"
        if [ "$INSTALL_CLAUDE" = true ]; then
            echo "  Claude Code: Type /ralph-loop-setup to set up a new project"
        fi
        if [ "$INSTALL_GEMINI" = true ]; then
            echo "  Gemini CLI:  Type /ralph-loop-setup to set up a new project"
        fi
    else
        echo -e "${RED}No platforms installed.${NC}"
        exit 1
    fi
}

main
