#!/bin/bash

# Ralph Wiggum Loop - Automated Feature Implementation Script
# "I'm helping!" - Ralph Wiggum
#
# This script iteratively runs Claude Code CLI to implement tasks from a todo list JSON file.
# Each iteration works on ONE task, updates progress, and commits changes.
# Works with any project - reads project info from the todo list metadata.

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECONDS=1800  # 30 minutes
MAX_FAILURES=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
MAX_ITERATIONS=999999  # Default to effectively unlimited
TODO_FILE=""
WORKING_DIR=""

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS] [todo-file]"
    echo ""
    echo "Arguments:"
    echo "  [todo-file]           Path to the todo list JSON file (default: ./todolist.json)"
    echo ""
    echo "Options:"
    echo "  --max-iterations N    Maximum number of iterations (default: unlimited)"
    echo "  -m N                  Short form of --max-iterations"
    echo "  --working-dir DIR     Working directory for Claude (default: todo file directory)"
    echo "  -w DIR                Short form of --working-dir"
    echo "  --timeout SECONDS     Timeout per iteration in seconds (default: 1800)"
    echo "  -t SECONDS            Short form of --timeout"
    echo "  --help, -h            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Run with ./todolist.json"
    echo "  $0 ./my-project/todolist.json               # Run with specific todo list file"
    echo "  $0 --max-iterations 10                      # Run at most 10 iterations"
    echo "  $0 -m 5 -w /path/to/project ./todolist.json # Run 5 iterations in specific dir"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --max-iterations|-m)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --max-iterations requires a numeric value${NC}"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Error: --max-iterations must be a positive integer${NC}"
                exit 1
            fi
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        --working-dir|-w)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --working-dir requires a directory path${NC}"
                exit 1
            fi
            WORKING_DIR="$2"
            shift 2
            ;;
        --timeout|-t)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --timeout requires a numeric value${NC}"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Error: --timeout must be a positive integer${NC}"
                exit 1
            fi
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        -*)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Positional argument - todo file
            if [[ -z "$TODO_FILE" ]]; then
                TODO_FILE="$1"
            else
                echo -e "${RED}Error: Multiple todo files specified${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# Default to todolist.json in script directory if not specified
if [[ -z "$TODO_FILE" ]]; then
    TODO_FILE="${SCRIPT_DIR}/todolist.json"
    echo -e "${YELLOW}No todo file specified, using: $TODO_FILE${NC}"
fi

# Convert todo file to absolute path
if [[ ! "$TODO_FILE" = /* ]]; then
    TODO_FILE="$(cd "$(dirname "$TODO_FILE")" && pwd)/$(basename "$TODO_FILE")"
fi

# Set working directory (default to todo file directory)
if [[ -z "$WORKING_DIR" ]]; then
    WORKING_DIR="$(dirname "$TODO_FILE")"
fi

# Convert working directory to absolute path
if [[ ! "$WORKING_DIR" = /* ]]; then
    WORKING_DIR="$(cd "$WORKING_DIR" && pwd)"
fi

# Set derived paths
PROGRESS_FILE="$(dirname "$TODO_FILE")/progress.txt"
PROMPT_FILE="$(dirname "$TODO_FILE")/.claude_prompt.md"

# Read project info from todo list
PROJECT_NAME=$(jq -r '.metadata.project // "Project"' "$TODO_FILE" 2>/dev/null || echo "Project")
PROJECT_DESC=$(jq -r '.metadata.description // ""' "$TODO_FILE" 2>/dev/null || echo "")

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Ralph Wiggum Loop - Feature Automation               ║${NC}"
echo -e "${BLUE}║                     \"I'm helping!\" - Ralph                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Project: ${PROJECT_NAME}${NC}"
if [[ -n "$PROJECT_DESC" ]]; then
    echo -e "${GREEN}Description: ${PROJECT_DESC}${NC}"
fi
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Max iterations: $MAX_ITERATIONS"
echo "  Timeout per iteration: $((TIMEOUT_SECONDS / 60)) minutes"
echo "  Todo list: $TODO_FILE"
echo "  Working directory: $WORKING_DIR"
echo "  Progress file: $PROGRESS_FILE"
echo ""

# Check dependencies
if ! command -v claude &> /dev/null; then
    echo -e "${RED}Error: 'claude' CLI not found. Please install Claude Code CLI.${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: 'jq' not found. Please install jq (brew install jq).${NC}"
    exit 1
fi

if [ ! -f "$TODO_FILE" ]; then
    echo -e "${RED}Error: Todo list file not found at $TODO_FILE${NC}"
    exit 1
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
    cat > "$PROGRESS_FILE" << EOF
# ${PROJECT_NAME} - Task Implementation Progress Log
# ==========================================
# This file tracks the progress of automated task implementation.
# Each entry contains: timestamp, task ID, status, summary, and lessons learned.
#
# Generated by Ralph Wiggum Loop
# Todo list: ${TODO_FILE}
# Created: $(date '+%Y-%m-%d')

================================================================================
EOF
fi

# Function to get the next task to work on
get_next_task() {
    # Find the highest priority pending task that:
    # 1. Has failure_count < MAX_FAILURES
    # 2. Has all dependencies satisfied (status = "passed")

    jq -r --argjson max_failures "$MAX_FAILURES" '
        # First, get list of passed task IDs
        [.tasks[] | select(.status == "passed") | .id] as $passed |

        # Find eligible tasks
        [.tasks[] | select(
            .status == "pending" and
            .failure_count < $max_failures and
            (
                (.dependencies | length == 0) or
                (.dependencies | all(. as $dep | $passed | contains([$dep])))
            )
        )] |

        # Sort by priority (ascending, lower number = higher priority)
        sort_by(.priority) |

        # Return the first one (highest priority)
        first |

        # Return empty string if no task found
        if . == null then "" else .id end
    ' "$TODO_FILE"
}

# Function to check if all remaining tasks have failed too many times
all_tasks_exhausted() {
    local remaining=$(jq -r --argjson max_failures "$MAX_FAILURES" '
        [.tasks[] | select(
            .status == "pending" and
            .failure_count < $max_failures
        )] | length
    ' "$TODO_FILE")

    [ "$remaining" -eq 0 ]
}

# Function to get task details
get_task_details() {
    local task_id="$1"
    jq -r --arg id "$task_id" '.tasks[] | select(.id == $id)' "$TODO_FILE"
}

# Function to update task status in todo list
update_task_status() {
    local task_id="$1"
    local new_status="$2"
    local notes="$3"

    local tmp_file=$(mktemp)
    jq --arg id "$task_id" --arg status "$new_status" --arg notes "$notes" '
        .tasks = [.tasks[] |
            if .id == $id then
                .status = $status |
                .notes = (if .notes == null or .notes == "" then $notes else .notes + "\n" + $notes end)
            else . end
        ] |
        .statistics.pending = ([.tasks[] | select(.status == "pending")] | length) |
        .statistics.in_progress = ([.tasks[] | select(.status == "in_progress")] | length) |
        .statistics.passed = ([.tasks[] | select(.status == "passed")] | length) |
        .statistics.failed = ([.tasks[] | select(.status == "failed")] | length) |
        .statistics.skipped = ([.tasks[] | select(.status == "skipped")] | length) |
        .metadata.last_updated = (now | strftime("%Y-%m-%d"))
    ' "$TODO_FILE" > "$tmp_file" && mv "$tmp_file" "$TODO_FILE"
}

# Function to increment failure count
increment_failure_count() {
    local task_id="$1"

    local tmp_file=$(mktemp)
    jq --arg id "$task_id" '
        .tasks = [.tasks[] |
            if .id == $id then
                .failure_count = (.failure_count + 1)
            else . end
        ]
    ' "$TODO_FILE" > "$tmp_file" && mv "$tmp_file" "$TODO_FILE"
}

# Function to log progress
log_progress() {
    local task_id="$1"
    local status="$2"
    local summary="$3"
    local error_msg="$4"
    local lessons="$5"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat >> "$PROGRESS_FILE" << EOF

--------------------------------------------------------------------------------
Timestamp: $timestamp
Task ID: $task_id
Status: $status
Summary: $summary
EOF

    if [ -n "$error_msg" ]; then
        cat >> "$PROGRESS_FILE" << EOF
Error: $error_msg
EOF
    fi

    if [ -n "$lessons" ]; then
        cat >> "$PROGRESS_FILE" << EOF
Lessons Learned: $lessons
EOF
    fi

    echo "--------------------------------------------------------------------------------" >> "$PROGRESS_FILE"
}

# Function to create the Claude prompt
create_claude_prompt() {
    local task_id="$1"
    local task_json=$(get_task_details "$task_id")

    local name=$(echo "$task_json" | jq -r '.name')
    local description=$(echo "$task_json" | jq -r '.description')
    local category=$(echo "$task_json" | jq -r '.category')
    local priority=$(echo "$task_json" | jq -r '.priority')
    local acceptance_criteria=$(echo "$task_json" | jq -r '.acceptance_criteria | join("\n  - ")')
    local files_affected=$(echo "$task_json" | jq -r '.files_likely_affected | join(", ")')
    local dependencies=$(echo "$task_json" | jq -r '.dependencies | join(", ")')
    local notes=$(echo "$task_json" | jq -r '.notes // ""')
    local failure_count=$(echo "$task_json" | jq -r '.failure_count')

    # Get build/test commands from todo list metadata (optional)
    local build_command=$(jq -r '.metadata.build_command // ""' "$TODO_FILE")
    local test_command=$(jq -r '.metadata.test_command // ""' "$TODO_FILE")
    local extra_instructions=$(jq -r '.metadata.extra_instructions // ""' "$TODO_FILE")

    # Get previous lessons from progress.txt for this task
    local prev_lessons=""
    if [ -f "$PROGRESS_FILE" ] && [ "$failure_count" -gt 0 ]; then
        prev_lessons=$(grep -A 20 "Task ID: $task_id" "$PROGRESS_FILE" | grep -A 1 "Lessons Learned:" | tail -n 1 || echo "")
    fi

    cat > "$PROMPT_FILE" << EOF
# ${PROJECT_NAME} - Task Implementation

You are implementing a single task for ${PROJECT_NAME}.
${PROJECT_DESC:+
**Project Description**: $PROJECT_DESC
}
## Your Task

Implement the following task and ONLY this task. Do not work on any other tasks.

### Task Details

- **ID**: $task_id
- **Name**: $name
- **Category**: $category
- **Priority**: $priority (1 = highest)
- **Description**: $description

### Acceptance Criteria

  - $acceptance_criteria

### Files Likely Affected

$files_affected

### Dependencies (already completed)

${dependencies:-None}

### Previous Notes

${notes:-None}

### Previous Failure Count: $failure_count / $MAX_FAILURES

${prev_lessons:+**Lessons from previous attempts:**
$prev_lessons}

## Instructions

1. **Read the relevant source files first** to understand the current implementation
2. **Plan your implementation** before writing code
3. **Implement the task** following the existing code patterns and architecture
${build_command:+4. **Verify the build compiles** by running: \`$build_command\`}
${test_command:+5. **Run tests** if applicable: \`$test_command\`}
${extra_instructions:+
### Project-Specific Instructions

$extra_instructions
}
## After Implementation

You MUST update the following files before finishing:

### 1. Update the todo list

Update the task status in the todo list file ($TODO_FILE):
- Set \`status\` to \`"passed"\` if implementation succeeded
- Set \`status\` to \`"failed"\` if implementation failed
- Add any relevant notes to the \`notes\` field
- If failed, the \`failure_count\` will be incremented automatically

Use this exact jq command pattern to update:
\`\`\`bash
# For success:
jq '.tasks = [.tasks[] | if .id == "$task_id" then .status = "passed" | .notes = "YOUR_NOTES_HERE" else . end]' "$TODO_FILE" > tmp.json && mv tmp.json "$TODO_FILE"

# For failure:
jq '.tasks = [.tasks[] | if .id == "$task_id" then .status = "failed" | .notes = "YOUR_NOTES_HERE" else . end]' "$TODO_FILE" > tmp.json && mv tmp.json "$TODO_FILE"
\`\`\`

### 2. Append to progress.txt

Add an entry to the progress file ($PROGRESS_FILE) with:
- Timestamp
- Task ID and name
- Status (passed/failed)
- Summary of changes made (files modified, key implementation details)
- If failed: error messages and what went wrong
- Lessons learned that will help future iterations

### 3. Git Commit (only if passed)

If the implementation succeeded, create a git commit:
- For new features: \`feat($task_id): $name\`
- For bug fixes: \`fix($task_id): $name\`

Include in the commit message:
- Brief description of implementation
- Files changed

## Important Rules

1. **Work on ONLY this task** - do not implement other tasks
2. **Do not break existing functionality** - be careful with changes
3. **Follow existing code patterns** - maintain consistency
4. **Keep changes minimal** - only change what's necessary
5. **Update the todo list and progress.txt** before finishing - this is CRITICAL
${build_command:+6. **Build must compile** - verify with \`$build_command\`}

## Reference Files

- Todo list: $TODO_FILE
- Progress: $PROGRESS_FILE
- Working Directory: $WORKING_DIR

Good luck! Remember to update the todo list and progress.txt before you finish.
EOF

    echo "$PROMPT_FILE"
}

# Function to run Claude with timeout
run_claude_with_timeout() {
    local prompt_file="$1"
    local task_id="$2"

    echo -e "${BLUE}Running Claude CLI...${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

    # Use timeout command (gtimeout on macOS if coreutils installed, otherwise use perl)
    local timeout_cmd=""
    if command -v gtimeout &> /dev/null; then
        timeout_cmd="gtimeout"
    elif command -v timeout &> /dev/null; then
        timeout_cmd="timeout"
    fi

    local exit_code=0

    # Change to working directory for Claude execution
    pushd "$WORKING_DIR" > /dev/null

    if [ -n "$timeout_cmd" ]; then
        # Use timeout command with unbuffered output
        # Using stdbuf if available for line-buffered output
        if command -v stdbuf &> /dev/null; then
            stdbuf -oL -eL $timeout_cmd $TIMEOUT_SECONDS claude --dangerously-skip-permissions -p "$(cat "$prompt_file")" 2>&1 || exit_code=$?
        else
            # Run directly - output should stream in real-time
            $timeout_cmd $TIMEOUT_SECONDS claude --dangerously-skip-permissions -p "$(cat "$prompt_file")" 2>&1 || exit_code=$?
        fi
    else
        # Fallback: use background process with manual timeout
        # Create a named pipe for capturing output while displaying it
        local fifo_path="/tmp/claude_output_$$"
        mkfifo "$fifo_path" 2>/dev/null || true

        # Start tee to display output in real-time
        cat "$fifo_path" &
        local cat_pid=$!

        claude --dangerously-skip-permissions -p "$(cat "$prompt_file")" > "$fifo_path" 2>&1 &
        local claude_pid=$!

        local elapsed=0
        while kill -0 $claude_pid 2>/dev/null; do
            sleep 5
            elapsed=$((elapsed + 5))
            if [ $elapsed -ge $TIMEOUT_SECONDS ]; then
                echo -e "${YELLOW}Timeout reached. Terminating Claude...${NC}"
                kill -TERM $claude_pid 2>/dev/null || true
                sleep 2
                kill -KILL $claude_pid 2>/dev/null || true
                exit_code=124  # Timeout exit code
                break
            fi
        done

        if [ $exit_code -eq 0 ]; then
            wait $claude_pid || exit_code=$?
        fi

        # Cleanup
        kill $cat_pid 2>/dev/null || true
        rm -f "$fifo_path"
    fi

    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

    # Return to original directory
    popd > /dev/null

    return $exit_code
}

# Function to handle timeout - ensure todo list and progress.txt are updated
handle_timeout() {
    local task_id="$1"

    echo -e "${YELLOW}Handling timeout for task $task_id...${NC}"

    # Update todo list to mark as failed
    update_task_status "$task_id" "pending" "Timed out after $((TIMEOUT_SECONDS / 60)) minutes"
    increment_failure_count "$task_id"

    # Log progress
    log_progress "$task_id" "TIMEOUT" \
        "Implementation timed out after $((TIMEOUT_SECONDS / 60)) minutes" \
        "Exceeded maximum allowed time" \
        "Task may be too complex for single iteration. Consider breaking into smaller sub-tasks."

    echo -e "${YELLOW}Timeout handled. Progress updated.${NC}"
}

# Main loop
echo -e "${GREEN}Starting implementation loop...${NC}"
echo ""

iteration=0

while [ $iteration -lt $MAX_ITERATIONS ]; do
    iteration=$((iteration + 1))

    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    Iteration $iteration of $MAX_ITERATIONS${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Check if all tasks are exhausted
    if all_tasks_exhausted; then
        echo -e "${YELLOW}All remaining tasks have either passed or failed $MAX_FAILURES times.${NC}"
        echo -e "${YELLOW}Exiting loop.${NC}"
        break
    fi

    # Get next task to work on
    task_id=$(get_next_task)

    if [ -z "$task_id" ]; then
        echo -e "${YELLOW}No eligible tasks found. All tasks may be completed or blocked.${NC}"
        break
    fi

    # Get task details for display
    task_json=$(get_task_details "$task_id")
    task_name=$(echo "$task_json" | jq -r '.name')
    task_priority=$(echo "$task_json" | jq -r '.priority')
    task_category=$(echo "$task_json" | jq -r '.category')
    failure_count=$(echo "$task_json" | jq -r '.failure_count')

    echo -e "${GREEN}Selected Task:${NC}"
    echo "  ID: $task_id"
    echo "  Name: $task_name"
    echo "  Category: $task_category"
    echo "  Priority: $task_priority"
    echo "  Previous failures: $failure_count"
    echo ""

    # Mark task as in_progress
    update_task_status "$task_id" "in_progress" ""

    # Create the prompt file
    prompt_file=$(create_claude_prompt "$task_id")

    echo -e "${BLUE}Created prompt file: $prompt_file${NC}"
    echo ""

    # Run Claude
    start_time=$(date +%s)

    if run_claude_with_timeout "$prompt_file" "$task_id"; then
        echo -e "${GREEN}Claude completed successfully.${NC}"
    else
        exit_code=$?
        if [ $exit_code -eq 124 ]; then
            # Timeout
            handle_timeout "$task_id"
        else
            echo -e "${RED}Claude exited with code $exit_code${NC}"
            # Check if Claude updated the files, if not, mark as failed
            current_status=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")
            if [ "$current_status" = "in_progress" ]; then
                # Claude didn't update status, mark as failed
                update_task_status "$task_id" "pending" "Claude exited unexpectedly with code $exit_code"
                increment_failure_count "$task_id"
                log_progress "$task_id" "FAILED" \
                    "Claude exited unexpectedly" \
                    "Exit code: $exit_code" \
                    "Check if there are environmental issues or if the task is too complex."
            fi
        fi
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    echo ""
    echo -e "${BLUE}Iteration $iteration completed in $((duration / 60))m $((duration % 60))s${NC}"
    echo ""

    # Show current statistics
    stats=$(jq '.statistics' "$TODO_FILE")
    echo -e "${YELLOW}Current Statistics:${NC}"
    echo "$stats" | jq -r '"  Pending: \(.pending) | Passed: \(.passed) | Failed: \(.failed)"'
    echo ""

    # Small delay between iterations
    sleep 2
done

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Loop Completed                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Final statistics
echo -e "${GREEN}Final Statistics:${NC}"
jq '.statistics' "$TODO_FILE"

echo ""
echo -e "${YELLOW}Check progress.txt for detailed implementation log.${NC}"
echo -e "${YELLOW}Check the todo list for task status details.${NC}"
