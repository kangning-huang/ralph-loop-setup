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

The Ralph Loop Setup skill supports multiple AI coding platforms that implement the Agent Skills open standard.

### Supported Platforms

| Platform | Installation Location | Status |
|----------|----------------------|--------|
| Claude Code | `~/.claude/plugins/local/ralph-loop-setup/` | Supported |
| Gemini CLI | `~/.gemini/skills/ralph-loop-setup/` | Supported |
| Cursor | Agent Skills (auto-discovery) | Compatible |
| Codex/OpenCode | Agent Skills standard | Compatible |

### Quick Install (Auto-detect)

```bash
curl -sL https://raw.githubusercontent.com/kangning-huang/ralph-loop-setup/main/install.sh | bash
```

This auto-detects installed platforms and installs the skill for all of them.

### Platform-Specific Install

**Claude Code only:**
```bash
curl -sL https://raw.githubusercontent.com/kangning-huang/ralph-loop-setup/main/install.sh | bash -s -- --claude
```

**Gemini CLI only:**
```bash
curl -sL https://raw.githubusercontent.com/kangning-huang/ralph-loop-setup/main/install.sh | bash -s -- --gemini
```

**All platforms (regardless of detection):**
```bash
curl -sL https://raw.githubusercontent.com/kangning-huang/ralph-loop-setup/main/install.sh | bash -s -- --all
```

### What Gets Installed

**Claude Code** (plugin structure):
```
~/.claude/plugins/local/ralph-loop-setup/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   └── ralph-loop-setup.md
└── resources/
    ├── ralph_wiggum_loop.sh
    ├── todolist-template.json
    └── progress-template.txt
```

The installer also registers the plugin in `~/.claude/settings.json`:
```json
{
  "enabledPlugins": {
    "ralph-loop-setup": true
  }
}
```

**Gemini CLI** (skills structure):
```
~/.gemini/skills/ralph-loop-setup/
├── SKILL.md
└── resources/
    ├── ralph_wiggum_loop.sh
    ├── todolist-template.json
    └── progress-template.txt
```

### Prerequisites

- **AI Coding CLI** - One of:
  - Claude Code CLI from [claude.ai/code](https://claude.ai/code)
  - Gemini CLI from Google
- **jq** (optional but recommended) - JSON processor for settings.json updates (`brew install jq` on macOS)

---

## Usage

### Step 1: Run the Setup Skill

In Claude Code, type:

```
/ralph-loop-setup
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
| `install.sh` | Multi-platform installer script |
| `skill/.claude-plugin/plugin.json` | Claude Code plugin manifest |
| `skill/commands/ralph-loop-setup.md` | Claude Code command definition |
| `skill/SKILL.md` | Gemini CLI skill file |
| `skill/ralph-loop-setup/resources/ralph_wiggum_loop.sh` | Main automation script |
| `skill/ralph-loop-setup/resources/todolist-template.json` | Template todo list |
| `skill/ralph-loop-setup/resources/progress-template.txt` | Template progress log |
| `examples/` | Example todo lists |

---

## License

MIT
