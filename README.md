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

### Option 1: Clone the Repository

```bash
git clone https://github.com/kangning-huang/ralph-loop-setup.git
cd ralph-loop-setup
chmod +x ralph_wiggum_loop.sh
```

### Option 2: Download Files Directly

Download these files to your preferred location:
- `ralph_wiggum_loop.sh` - The main script
- `todolist.json` - Template for your todo list

## Prerequisites

- **Claude Code CLI** - Install from [claude.ai/code](https://claude.ai/code)
- **jq** - JSON processor (`brew install jq` on macOS)
- **Optional**: `timeout` or `gtimeout` for better timeout handling (`brew install coreutils`)

---

## Quick Start with Claude Skill (Recommended)

The easiest way to get started is using the built-in Claude Code skill.

### 1. Install the Skill

Copy the `CLAUDE.md` file to your project root, or add this to your existing `CLAUDE.md`:

```markdown
## Skills

### /ralph-loop

Sets up a Ralph Wiggum Loop for automated task implementation.
Read instructions from: /path/to/ralph-wiggum-loop/skill/ralph-loop.md
```

### 2. Run the Skill

In Claude Code, type:

```
/ralph-loop
```

The skill will guide you through:
- **Option A**: Converting existing todo files into a structured todo list
- **Option B**: Creating a todo list from scratch by interviewing you about your project

### 3. Run the Loop

After setup, run:

```bash
./ralph_wiggum_loop.sh ./todolist.json
```

---

## Manual Quick Start

If you prefer to set things up manually:

1. **Copy the template to your project:**
   ```bash
   cp todolist.json /path/to/your/project/
   ```

2. **Edit the todo list** with your project info and tasks:
   ```bash
   vim /path/to/your/project/todolist.json
   ```

3. **Run the loop:**
   ```bash
   ./ralph_wiggum_loop.sh /path/to/your/project/todolist.json
   ```

---

## Usage

```bash
./ralph_wiggum_loop.sh [OPTIONS] <todo-file>
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<todo-file>` | Path to the todo list JSON file (required) |

### Options

| Option | Description |
|--------|-------------|
| `-m, --max-iterations N` | Maximum number of iterations (default: unlimited) |
| `-w, --working-dir DIR` | Working directory for Claude (default: todo file directory) |
| `-t, --timeout SECONDS` | Timeout per task in seconds (default: 1800 / 30 min) |
| `-h, --help` | Show help message |

### Examples

```bash
# Run until all tasks complete or exhaust retries
./ralph_wiggum_loop.sh ./todolist.json

# Run at most 10 iterations
./ralph_wiggum_loop.sh -m 10 ./todolist.json

# Run with custom working directory and timeout
./ralph_wiggum_loop.sh -w /path/to/project -t 3600 ./todolist.json
```

---

## Todo List JSON Structure

```json
{
  "metadata": {
    "project": "MyProject",
    "version": "1.0.0",
    "description": "Description of your project",
    "build_command": "npm run build",
    "test_command": "npm test",
    "extra_instructions": "Any project-specific instructions for Claude"
  },
  "tasks": [
    {
      "id": "TASK-001",
      "name": "Implement user login",
      "description": "Add login functionality with email/password",
      "category": "auth",
      "priority": 1,
      "status": "pending",
      "failure_count": 0,
      "dependencies": [],
      "acceptance_criteria": [
        "Login form accepts email and password",
        "Invalid credentials show error message",
        "Successful login redirects to dashboard",
        "Tests pass"
      ],
      "files_likely_affected": [
        "src/auth/login.js",
        "src/components/LoginForm.jsx"
      ],
      "notes": ""
    }
  ],
  "statistics": {
    "total_tasks": 1,
    "pending": 1,
    "in_progress": 0,
    "passed": 0,
    "failed": 0
  }
}
```

### Metadata Fields

| Field | Required | Description |
|-------|----------|-------------|
| `project` | Yes | Project name (shown in prompts) |
| `description` | No | Project description |
| `build_command` | No | Command to verify build (e.g., `npm run build`, `go build`) |
| `test_command` | No | Command to run tests (e.g., `npm test`, `pytest`) |
| `extra_instructions` | No | Additional instructions for Claude |

### Task Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier (e.g., `TASK-001`, `BUG-002`) |
| `name` | Yes | Short task name |
| `description` | Yes | Detailed description of what to implement |
| `category` | No | Category for organization (e.g., `auth`, `ui`, `api`) |
| `priority` | Yes | Priority level (1 = highest) |
| `status` | Yes | Current status: `pending`, `in_progress`, `passed`, `failed` |
| `failure_count` | Yes | Number of failed attempts (starts at 0) |
| `dependencies` | No | Array of task IDs that must pass first |
| `acceptance_criteria` | Yes | List of criteria for task completion |
| `files_likely_affected` | No | Hints for Claude about which files to look at |
| `notes` | No | Notes added during implementation |

### Task ID Conventions

Use meaningful prefixes for task IDs:

| Prefix | Use Case |
|--------|----------|
| `SETUP-XXX` | Setup/infrastructure tasks |
| `CORE-XXX` | Core functionality |
| `FEAT-XXX` | Features |
| `BUG-XXX` | Bug fixes |
| `UI-XXX` | User interface |
| `API-XXX` | API-related |
| `TEST-XXX` | Testing |
| `DOC-XXX` | Documentation |
| `REFACTOR-XXX` | Refactoring |

---

## How It Works

### Task Selection

Tasks are selected based on:
1. **Status**: Only `pending` tasks are considered
2. **Dependencies**: All dependencies must have `passed` status
3. **Failure count**: Must be less than 5 (configurable via `MAX_FAILURES`)
4. **Priority**: Lower number = higher priority

### Execution Flow

```
┌─────────────────────────────────────────┐
│  Select highest-priority pending task   │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Generate prompt with task details      │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Run Claude Code with timeout           │
└─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   ┌─────────┐             ┌─────────┐
   │ Success │             │ Failure │
   └─────────┘             └─────────┘
        │                       │
        ▼                       ▼
┌──────────────┐       ┌──────────────────┐
│ Mark passed  │       │ Increment fails  │
│ Git commit   │       │ Log lessons      │
└──────────────┘       └──────────────────┘
                    │
                    ▼
            ┌──────────────┐
            │ Next task... │
            └──────────────┘
```

### Progress Tracking

- **todolist.json**: Updated with task status and notes
- **progress.txt**: Detailed log of each attempt with:
  - Timestamp
  - Task ID and status
  - Summary of changes
  - Error messages (if failed)
  - Lessons learned

---

## Tips for Writing Good Tasks

### Be Specific
```json
// Good
"description": "Add email validation to the signup form that checks for valid format and shows inline error"

// Too vague
"description": "Fix signup form"
```

### Include Clear Acceptance Criteria
```json
"acceptance_criteria": [
  "Email field validates format on blur",
  "Invalid email shows red border and error message",
  "Valid email shows green checkmark",
  "Form cannot submit with invalid email",
  "Unit tests cover validation logic"
]
```

### Use Dependencies for Order
```json
{
  "id": "AUTH-001",
  "name": "Set up authentication context",
  "dependencies": []
},
{
  "id": "AUTH-002",
  "name": "Implement login form",
  "dependencies": ["AUTH-001"]
},
{
  "id": "AUTH-003",
  "name": "Add protected routes",
  "dependencies": ["AUTH-001", "AUTH-002"]
}
```

### Break Down Complex Tasks
Instead of one large task, create smaller focused tasks:
- `API-001`: Create database schema for users
- `API-002`: Implement user CRUD endpoints
- `API-003`: Add authentication middleware
- `API-004`: Add input validation

---

## Troubleshooting

### Task keeps failing
- Check `progress.txt` for error messages and lessons learned
- Make the task more specific or break it into smaller tasks
- Add more context in `files_likely_affected`
- Add hints in `extra_instructions`

### Claude not finding files
- Ensure `working-dir` points to your project root
- Add specific file paths in `files_likely_affected`

### Timeout issues
- Increase timeout with `-t` flag
- Break complex tasks into smaller ones
- Add `build_command` so Claude can verify incrementally

---

## Project Structure

```
ralph-wiggum-loop/
├── README.md                 # This file
├── CLAUDE.md                 # Claude Code configuration
├── ralph_wiggum_loop.sh      # Main automation script
├── todolist.json             # Template todo list
├── progress.txt              # Progress log template
├── skill/
│   └── ralph-loop.md         # Claude skill for setup wizard
└── examples/
    └── web-app-todolist.json # Example: Web application todo list
```

---

## Examples

See the `examples/` directory for sample todo lists:

- **web-app-todolist.json**: Building a web application with authentication, API, and frontend

---

## Contributing

Contributions welcome! Please feel free to submit issues and pull requests.

## License

MIT
