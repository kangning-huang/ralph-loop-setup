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

---

## Why Use Ralph Loop?

### The Problem with One Giant Session

When you ask Claude to complete a large project in a single session, you run into problems:

- **Context window fills up**: As the conversation grows, Claude's context window gets cluttered with old messages, failed attempts, and irrelevant information
- **Degraded performance**: Claude becomes less focused and effective as context bloats
- **No recovery from failures**: If Claude gets stuck or makes mistakes, the entire session is compromised
- **Lost progress on crashes**: If the session crashes, you lose everything

### The Solution: Fresh Context + External Memory

Ralph Loop solves this by running **each task in a fresh Claude Code session**:

**Fresh Context Window**: Each task gets a brand new Claude instance with a clean context. Claude starts fresh, focused only on the current task with clear instructions. No accumulated confusion from previous work.

**External Memory System**: Two files persist information between sessions:

| File | Purpose |
|------|---------|
| `todolist.json` | **Task State Memory** - Tracks which tasks are pending, passed, or failed. Stores dependencies, priorities, and notes. Claude updates this after each task. |
| `progress.txt` | **Learning Memory** - Logs what happened in each session: what worked, what failed, and lessons learned. Future sessions can learn from past mistakes. |

**Orchestration Script**: `ralph_wiggum_loop.sh` ties it together - it reads the external memory, launches focused Claude sessions, and ensures continuity across the entire project.

### Benefits

- **Consistent quality**: Each task gets Claude's full attention with clean context
- **Automatic recovery**: Failed tasks are retried with lessons from previous attempts
- **Progress persistence**: Work is saved after each task, not lost on crashes
- **Scalable**: Can handle projects with dozens or hundreds of tasks
- **Hands-off**: Run overnight and wake up to a completed project

---

## Installation

### Option 1: Quick Install (Download Skill File)

The simplest way to use Ralph Loop is to download the self-contained `.skill` file to your project:

```bash
curl -O https://raw.githubusercontent.com/kangning-huang/ralph-loop-setup/main/ralph-loop-setup.skill
```

Then in Claude Code, invoke it using the `@` syntax:

```
@ralph-loop-setup.skill set up Ralph Loop for my project
```

Claude will read the skill instructions and guide you through creating all three required files interactively.

### Option 2: Plugin Marketplace (Claude Code)

Install through Claude Code in two steps:

**Step 1: Add the marketplace**
```
/plugin marketplace add kangning-huang/ralph-loop-setup
```

**Step 2: Install the plugin**
```
/plugin install ralph-loop-setup@ralph-loop-setup
```

### Prerequisites

- **Claude Code CLI** from [claude.ai/code](https://claude.ai/code)
- **jq** - JSON processor (`brew install jq` on macOS)

---

## Installation on Other Platforms

### OpenAI Codex CLI

**Option 1: Using skill-installer (Recommended)**

In Codex CLI, ask it to install from this GitHub repo:
```
Install the ralph-loop-setup skill from kangning-huang/ralph_wiggum_loop
```

**Option 2: Manual Installation**

1. Clone this repository
2. Copy the skill folder to your Codex skills directory:
   ```bash
   cp -r ralph-loop-setup ~/.codex/skills/
   ```
3. Restart Codex CLI

Usage: Type `$ralph-loop-setup` or describe your task and Codex will invoke it automatically.

### Windsurf

**Option 1: Manual Installation (Global)**

1. Clone this repository
2. Copy the skill folder:
   ```bash
   mkdir -p ~/.codeium/windsurf/skills
   cp -r ralph-loop-setup ~/.codeium/windsurf/skills/
   ```
3. Restart Windsurf

**Option 2: Project-level Installation**

1. Create the skills directory in your project:
   ```bash
   mkdir -p .windsurf/skills
   ```
2. Copy the skill folder:
   ```bash
   cp -r /path/to/ralph-loop-setup .windsurf/skills/
   ```

Usage: Type `@ralph-loop-setup` in Cascade or describe your task.

---

## Usage

### Step 1: Run the Setup Skill

**If you installed via Option 1 (skill file download):**
```
@ralph-loop-setup.skill set up Ralph Loop for my project
```

**If you installed via Option 2 (plugin marketplace):**
```
/ralph-loop-setup
```

The skill will guide you through creating a todo list:

- **Option A**: Convert existing todo files (markdown, text, etc.) into a structured todo list
- **Option B**: Create a todo list from scratch by answering questions about your project

### Step 2: Run the Loop

After setup, run the automation script from the project directory:

```bash
./ralph_wiggum_loop.sh
```

The script automatically finds `todolist.json` in the same directory.

### Script Options

```bash
./ralph_wiggum_loop.sh [OPTIONS] [todo-file]
```

| Option | Description |
|--------|-------------|
| `[todo-file]` | Path to todo list JSON (default: ./todolist.json) |
| `-m N` | Maximum number of iterations (default: unlimited) |
| `-w DIR` | Working directory for Claude (default: todo file directory) |
| `-t SEC` | Timeout per task in seconds (default: 1800) |
| `-h` | Show help |

Examples:

```bash
./ralph_wiggum_loop.sh                            # Run with ./todolist.json
./ralph_wiggum_loop.sh -m 10                      # Run at most 10 tasks
./ralph_wiggum_loop.sh -t 3600                    # 1 hour timeout per task
./ralph_wiggum_loop.sh ./other-todolist.json      # Use a different todo file
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

## Repository Structure

```
.claude-plugin/
└── marketplace.json          # Plugin manifest for Claude Code
ralph-loop-setup/
├── SKILL.md                  # Skill definition
└── resources/
    ├── ralph_wiggum_loop.sh      # Main automation script
    ├── todolist-template.json    # Template todo list
    └── progress-template.txt     # Template progress log
examples/
└── web-app-todolist.json     # Example todo list
```

---

## License

MIT
