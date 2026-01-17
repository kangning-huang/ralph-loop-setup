---
name: ralph-loop-setup
description: Set up automated task implementation system with Ralph Wiggum Loop. Use when the user wants to create todolist.json, progress.txt, and ralph_wiggum_loop.sh files for automated task-based development.
---

# Ralph Loop Setup Skill

You are helping the user set up the 3 files needed to run a Ralph Wiggum Loop - an automated task implementation system that uses Claude Code to work through a project todo list.

**Important**: This skill sets up the files. It does not run the loop itself. After setup, the user runs the loop separately.

## What You Will Create

The Ralph Wiggum Loop requires 3 files in the user's project:

1. **todolist.json** - Task State Memory: tracks tasks, priorities, dependencies, and status
2. **progress.txt** - Learning Memory: logs what happened in each session for future reference
3. **ralph_wiggum_loop.sh** - Orchestration script: runs the loop, launching fresh Claude sessions

## Setup Flow

### Step 1: Understand the User's Situation

First, ask the user which scenario applies to them:

**Option A**: They have existing todo list file(s) (markdown, text, notion export, etc.) that they want to convert into a structured todo list.

**Option B**: They don't have a todo list yet and want help breaking down their project into tasks.

Use the AskUserQuestion tool to present these options clearly.

### Step 2A: If User Has Existing Files

If the user has existing todo list files:

1. Ask them to provide the file path(s) or paste the content
2. Read and parse the files to understand the tasks
3. For each task/item found, extract:
   - Task name
   - Description (if available)
   - Any dependencies mentioned
   - Priority hints
4. Ask clarifying questions about:
   - Project name and description
   - Build command (e.g., `npm run build`, `go build`, `cargo build`)
   - Test command (e.g., `npm test`, `pytest`, `go test`)
   - Any special instructions for Claude
5. Ask about task categorization and priorities if not clear from the source

### Step 2B: If User Wants to Create from Scratch

If the user doesn't have existing files, conduct a discovery interview:

1. **Project Understanding**:
   - "What is the name of your project?"
   - "Can you describe what this project does in 1-2 sentences?"
   - "What technology stack are you using?" (language, framework, etc.)

2. **Goal Identification**:
   - "What is the main goal or feature you want to implement?"
   - "Are there multiple major features? If so, list them."

3. **Task Breakdown**:
   For each major goal/feature, help break it down:
   - "What are the logical steps to implement [feature]?"
   - "What needs to be done first before other tasks?"
   - "Are there any infrastructure/setup tasks needed?"

4. **Technical Details**:
   - "What command builds your project?"
   - "What command runs your tests?"
   - "Any specific coding patterns or conventions Claude should follow?"

5. **Priority and Dependencies**:
   - Help establish which tasks depend on others
   - Assign priorities (1 = highest)

### Step 3: Ask Where to Save Files

Ask the user where they want to set up the Ralph Loop files. Default to the current working directory.

### Step 4: Create All 3 Files

#### File 1: Create ralph_wiggum_loop.sh

Create the orchestration script. You can find the full script content in the reference directory, or create it with these key features:
- Reads tasks from todolist.json
- Runs Claude Code for each task
- Updates progress.txt after each task
- Handles timeouts and retries

#### File 2: Create todolist.json

Create a customized version with the user's tasks:

```json
{
  "metadata": {
    "project": "PROJECT_NAME",
    "version": "1.0.0",
    "created": "YYYY-MM-DD",
    "last_updated": "YYYY-MM-DD",
    "description": "PROJECT_DESCRIPTION",
    "build_command": "BUILD_COMMAND_OR_EMPTY",
    "test_command": "TEST_COMMAND_OR_EMPTY",
    "extra_instructions": "ANY_SPECIAL_INSTRUCTIONS"
  },
  "priority_guidelines": {
    "description": "Priority is determined by: 1) Setup tasks first, 2) Core functionality before enhancements, 3) Foundation tasks before dependent tasks",
    "scale": "1-10 where 1 is highest priority"
  },
  "tasks": [
    {
      "id": "CATEGORY-001",
      "name": "Task name",
      "description": "Detailed description of what to implement",
      "category": "category",
      "priority": 1,
      "status": "pending",
      "failure_count": 0,
      "dependencies": [],
      "acceptance_criteria": [
        "Criterion 1",
        "Criterion 2"
      ],
      "files_likely_affected": [
        "src/file.js"
      ],
      "notes": ""
    }
  ],
  "statistics": {
    "total_tasks": N,
    "pending": N,
    "in_progress": 0,
    "passed": 0,
    "failed": 0
  }
}
```

**Task ID Conventions** - Use meaningful prefixes:
- `SETUP-XXX` - Setup/infrastructure tasks
- `CORE-XXX` - Core functionality
- `FEAT-XXX` - Features
- `BUG-XXX` - Bug fixes
- `UI-XXX` - User interface
- `API-XXX` - API-related
- `TEST-XXX` - Testing
- `DOC-XXX` - Documentation

#### File 3: Create progress.txt

Create the progress log file:

```
# PROJECT_NAME - Task Implementation Progress Log
# ==========================================
# This file tracks the progress of automated task implementation.
# Each entry contains: timestamp, task ID, status, summary, and lessons learned.
#
# Generated by Ralph Wiggum Loop
# Created: YYYY-MM-DD

================================================================================
```

### Step 5: Verify Setup and Provide Instructions

After creating all files, verify they exist and provide usage instructions:

```
Setup Complete! Created 3 files:

1. todolist.json - Your task list with X tasks
2. progress.txt - Progress log (empty, will be filled as tasks complete)
3. ralph_wiggum_loop.sh - The automation script

To run the Ralph Wiggum Loop:

   ./ralph_wiggum_loop.sh ./todolist.json

Options:
   -m N    Maximum iterations (default: unlimited)
   -t SEC  Timeout per task in seconds (default: 1800)

Example - run 5 tasks then stop:
   ./ralph_wiggum_loop.sh -m 5 ./todolist.json

The loop will:
- Pick the highest-priority pending task
- Run a fresh Claude session to implement it
- Update todolist.json and progress.txt
- Move to the next task
- Retry failed tasks up to 5 times
```

## Best Practices to Share with Users

When creating tasks, advise users to:

1. **Be Specific**: Each task should have a clear, measurable outcome
2. **Keep Tasks Small**: Tasks should be completable in under 30 minutes
3. **Define Dependencies**: Ensure foundation tasks come before dependent ones
4. **Write Clear Acceptance Criteria**: How will Claude know when it's done?
5. **Hint at Files**: The `files_likely_affected` field helps Claude focus

## Important Notes

- Always confirm the generated todo list with the user before writing files
- Offer to adjust priorities or add/remove tasks
- Make sure dependencies form a valid DAG (no circular dependencies)
- Statistics should accurately reflect the task counts
- Use today's date for created/last_updated fields
