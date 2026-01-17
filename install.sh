#!/bin/bash

# Ralph Loop Setup Skill Installer
# Installs the skill and all resources to ~/.claude/skills/

set -e

SKILL_DIR="$HOME/.claude/skills"
RALPH_DIR="$SKILL_DIR/ralph-loop-setup"
REPO_BASE="https://raw.githubusercontent.com/kangning-huang/ralph-loop-setup/main"

echo "Installing Ralph Loop Setup skill..."

# Create directories
mkdir -p "$RALPH_DIR/resources"

# Download skill file
curl -sL "$REPO_BASE/skill/ralph-loop-setup.skill" -o "$SKILL_DIR/ralph-loop-setup.skill"

# Download resources
curl -sL "$REPO_BASE/skill/ralph-loop-setup/resources/ralph_wiggum_loop.sh" -o "$RALPH_DIR/resources/ralph_wiggum_loop.sh"
curl -sL "$REPO_BASE/skill/ralph-loop-setup/resources/todolist-template.json" -o "$RALPH_DIR/resources/todolist-template.json"
curl -sL "$REPO_BASE/skill/ralph-loop-setup/resources/progress-template.txt" -o "$RALPH_DIR/resources/progress-template.txt"

# Make script executable
chmod +x "$RALPH_DIR/resources/ralph_wiggum_loop.sh"

echo ""
echo "Installed successfully!"
echo ""
echo "Files installed:"
echo "  $SKILL_DIR/ralph-loop-setup.skill"
echo "  $RALPH_DIR/resources/ralph_wiggum_loop.sh"
echo "  $RALPH_DIR/resources/todolist-template.json"
echo "  $RALPH_DIR/resources/progress-template.txt"
echo ""
echo "Usage: Type /ralph-loop-setup in Claude Code to set up a new project."
