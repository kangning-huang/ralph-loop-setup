# CLAUDE.md - Project Instructions for Claude

## Important Reminders

### Keep Skill File in Sync

**CRITICAL**: Whenever you modify `ralph_wiggum_loop.sh`, you MUST also update `ralph-loop-setup.skill` to reflect the same changes.

The skill file contains a template version of the script that gets generated when users set up new projects. If these files get out of sync, new projects will have outdated/different behavior than the main script.

Files to keep in sync:
- `ralph_wiggum_loop.sh` - The main orchestration script
- `ralph-loop-setup.skill` - The skill template (contains embedded script)

### What to Update in the Skill File

When modifying the main script, update the corresponding sections in the skill file:
1. The embedded bash script template (inside the ```bash code block)
2. The description/documentation if behavior changes
3. The "Verify and Provide Instructions" section if new options are added

## Project Overview

Ralph Wiggum Loop is an automated task implementation system that uses Claude Code to work through a project todo list.

**Key Feature**: AI-driven task selection - Claude analyzes the full todo list and intelligently selects the best task based on strategic value, dependencies, likelihood of success, and logical ordering (rather than strictly following priority numbers).
