# CLAUDE.md - Project Instructions for Claude

## Important Reminders

### Keep Skill Files in Sync

**CRITICAL**: Whenever you modify `ralph_wiggum_loop.sh`, you MUST also update ALL skill files to reflect the same changes.

The skill files contain template versions of the script that get generated when users set up new projects. If these files get out of sync, new projects will have outdated/different behavior than the main script.

**Files to keep in sync:**
- `ralph_wiggum_loop.sh` - The main orchestration script (SOURCE OF TRUTH)
- `ralph-loop-setup.skill` - Root-level skill template (contains embedded script)
- `ralph-loop-setup/resources/ralph_wiggum_loop.sh` - Marketplace plugin script template
- `ralph-loop-setup/SKILL.md` - Marketplace plugin skill definition

### What to Update

When modifying the main script:
1. Copy `ralph_wiggum_loop.sh` to `ralph-loop-setup/resources/ralph_wiggum_loop.sh`
2. Update the embedded bash script in `ralph-loop-setup.skill`
3. Update descriptions in `ralph-loop-setup/SKILL.md` if behavior changes
4. Update the "Verify and Provide Instructions" sections if new options are added

## Project Overview

Ralph Wiggum Loop is an automated task implementation system that uses Claude Code to work through a project todo list.

**Key Feature**: AI-driven task selection - Claude analyzes the full todo list and intelligently selects the best task based on strategic value, dependencies, likelihood of success, and logical ordering (rather than strictly following priority numbers).
