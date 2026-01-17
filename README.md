# Ralph Wiggum Loop

> "I'm helping!" - Ralph Wiggum

An automated task implementation system that uses Claude Code CLI to work through a project todo list, one task at a time.

## What It Does

The Ralph Wiggum Loop reads tasks from a JSON todo list and iteratively runs Claude Code to implement each one. For each task, it:

1. Selects the highest-priority pending task (respecting dependencies)
2. Generates a detailed prompt with task requirements
3. Runs Claude Code to implement the task
4. Tracks progress and learns from failures
5. Retries failed tasks (up to 5 times) before moving on

## Installation

Copy the skill file to your Claude Code skills folder:

```bash
cp skill/ralph-loop.md ~/.claude/skills/
```

That's it! The `/ralph-loop` command is now available in Claude Code.

### Prerequisites

- **Claude Code CLI** - Install from [claude.ai/code](https://claude.ai/code)
- **jq** - JSON processor (`brew install jq` on macOS)

---

## Usage

### Step 1: Run the Setup Skill

In Claude Code, type:

```
/ralph-loop
```

The skill will guide you through creating a todo list:

- **Option A**: Convert existing todo files (markdown, text, etc.) into a structured todo list
- **Option B**: Create a todo list from scratch by answering questions about your project

### Step 2: Run the Loop

After setup, run the automation script:

```bash
./ralph_wiggum_loop.sh ./todolist.json
```

### Script Options

```bash
./ralph_wiggum_loop.sh [OPTIONS] <todo-file>
```

| Option | Description |
|--------|-------------|
| `-m N` | Maximum number of iterations (default: unlimited) |
| `-w DIR` | Working directory for Claude (default: todo file directory) |
| `-t SEC` | Timeout per task in seconds (default: 1800) |
| `-h` | Show help |

Examples:

```bash
./ralph_wiggum_loop.sh -m 10 ./todolist.json      # Run at most 10 tasks
./ralph_wiggum_loop.sh -t 3600 ./todolist.json    # 1 hour timeout per task
```

---

## Todo List Format

```json
{
  "metadata": {
    "project": "MyProject",
    "description": "Project description",
    "build_command": "npm run build",
    "test_command": "npm test"
  },
  "tasks": [
    {
      "id": "TASK-001",
      "name": "Task name",
      "description": "What to implement",
      "priority": 1,
      "status": "pending",
      "failure_count": 0,
      "dependencies": [],
      "acceptance_criteria": ["Criterion 1", "Criterion 2"],
      "files_likely_affected": ["src/file.js"]
    }
  ]
}
```

See `examples/web-app-todolist.json` for a complete example.

---

## How It Works

```
┌─────────────────────────────────────────┐
│  Select highest-priority pending task   │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Run Claude Code to implement task      │
└─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   ┌─────────┐             ┌─────────┐
   │ Success │             │ Failure │
   └─────────┘             └─────────┘
        │                       │
        ▼                       ▼
   Mark passed             Retry (up to 5x)
   Git commit              Log lessons learned
        │                       │
        └───────────┬───────────┘
                    ▼
            ┌──────────────┐
            │ Next task... │
            └──────────────┘
```

---

## Files

| File | Description |
|------|-------------|
| `skill/ralph-loop.md` | Claude Code skill (copy to `~/.claude/skills/`) |
| `ralph_wiggum_loop.sh` | Main automation script |
| `todolist.json` | Template todo list |
| `examples/` | Example todo lists |

---

## License

MIT
