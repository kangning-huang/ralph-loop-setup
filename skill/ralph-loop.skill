# Ralph Wiggum Loop Setup Skill

You are helping the user set up a Ralph Wiggum Loop - an automated task implementation system that uses Claude Code to work through a project todo list.

## Overview

The Ralph Wiggum Loop will:
1. Read tasks from a JSON todo list
2. Implement each task one at a time using Claude Code
3. Track progress and learn from failures
4. Retry failed tasks before moving on

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

### Step 3: Generate the Todo List

Based on the gathered information, generate a `todolist.json` file with this structure:

```json
{
  "metadata": {
    "project": "ProjectName",
    "version": "1.0.0",
    "created": "YYYY-MM-DD",
    "last_updated": "YYYY-MM-DD",
    "description": "Project description",
    "build_command": "npm run build",
    "test_command": "npm test",
    "extra_instructions": "Any special instructions"
  },
  "priority_guidelines": {
    "description": "How priorities are determined",
    "scale": "1-10 where 1 is highest priority"
  },
  "tasks": [
    {
      "id": "CATEGORY-001",
      "name": "Task name",
      "description": "Detailed description",
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
    "total_tasks": 0,
    "pending": 0,
    "in_progress": 0,
    "passed": 0,
    "failed": 0
  }
}
```

### Task ID Conventions

Use meaningful prefixes for task IDs:
- `SETUP-XXX` - Setup/infrastructure tasks
- `CORE-XXX` - Core functionality
- `FEAT-XXX` - Features
- `BUG-XXX` - Bug fixes
- `UI-XXX` - User interface
- `API-XXX` - API-related
- `TEST-XXX` - Testing
- `DOC-XXX` - Documentation
- `REFACTOR-XXX` - Refactoring

### Step 4: Set Up the Working Directory

1. Ask where the user wants to save the todo list (default: current project directory)
2. Write the `todolist.json` file to the specified location
3. Create an empty `progress.txt` file with the header template
4. Inform the user about the ralph_wiggum_loop.sh script location

### Step 5: Provide Usage Instructions

After setup, provide clear instructions:

```
Setup Complete!

Your todo list has been created at: [path/to/todolist.json]

To run the Ralph Wiggum Loop:

1. Make sure the script is executable:
   chmod +x /path/to/ralph_wiggum_loop.sh

2. Run the loop:
   /path/to/ralph_wiggum_loop.sh [path/to/todolist.json]

Options:
   -m N    Maximum iterations (default: unlimited)
   -t SEC  Timeout per task in seconds (default: 1800)
   -w DIR  Working directory (default: todolist directory)

Example:
   /path/to/ralph_wiggum_loop.sh -m 5 ./todolist.json
```

## Best Practices to Share with Users

When creating tasks, advise users to:

1. **Be Specific**: Each task should have a clear, measurable outcome
2. **Keep Tasks Small**: Tasks should be completable in under 30 minutes
3. **Define Dependencies**: Ensure foundation tasks come before dependent ones
4. **Write Clear Acceptance Criteria**: How will Claude know when it's done?
5. **Hint at Files**: The `files_likely_affected` field helps Claude focus

## Example Questions to Ask

When interviewing users, use questions like:

- "What would success look like for this task?"
- "What files do you expect to be modified?"
- "Does this task depend on any other task being done first?"
- "How would you test that this task is complete?"
- "On a scale of 1-10, how urgent is this task?"

## Important Notes

- Always confirm the generated todo list with the user before writing files
- Offer to adjust priorities or add/remove tasks
- Make sure dependencies form a valid DAG (no circular dependencies)
- Statistics should accurately reflect the task counts
- Use today's date for created/last_updated fields
