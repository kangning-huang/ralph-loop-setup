#!/bin/bash

# Ralph Wiggum Loop - Automated Feature Implementation Script
# "I'm helping!" - Ralph Wiggum
#
# This script iteratively runs Claude Code CLI to implement tasks from a todo list JSON file.
# Each iteration works on ONE task, updates progress, and commits changes.
# Works with any project - reads project info from the todo list metadata.

# Issue #25: Removed `set -e` to prevent premature exit after task completion.
# Keep `set -u` for undefined variable protection, but allow commands to fail
# without terminating the entire script. Error handling is done explicitly.
set -u

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECONDS=1800  # 30 minutes
MAX_FAILURES=5
MAX_RETRIES=3  # Number of retry attempts per task before moving on
RETRY_DELAY=5  # Seconds to wait between retry attempts
EXPONENTIAL_BACKOFF=false  # If true, use exponential backoff (5s, 10s, 15s, etc.)
LOCK_FILE=""  # Will be set after TODO_FILE is determined

# Health Check Configuration (Issue #22)
HEALTH_CHECK_INTERVAL=30  # Check log file activity every 30 seconds
HEALTH_CHECK_INACTIVITY_TIMEOUT=300  # 5 minutes of inactivity before killing hung process
HEALTH_CHECK_ENABLED=true  # Enable/disable health check monitoring

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
    echo "  --max-retries N       Maximum retry attempts per task (default: 3)"
    echo "  -r N                  Short form of --max-retries"
    echo "  --retry-delay SECS    Delay between retry attempts in seconds (default: 5)"
    echo "  --exponential-backoff Use exponential backoff for retries (5s, 10s, 15s, etc.)"
    echo "  --health-check-interval SECS"
    echo "                        Health check interval in seconds (default: 30)"
    echo "  --health-check-timeout SECS"
    echo "                        Inactivity timeout before killing hung process (default: 300)"
    echo "  --no-health-check     Disable health check monitoring"
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
        --max-retries|-r)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --max-retries requires a numeric value${NC}"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Error: --max-retries must be a positive integer${NC}"
                exit 1
            fi
            MAX_RETRIES="$2"
            shift 2
            ;;
        --retry-delay)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --retry-delay requires a numeric value${NC}"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Error: --retry-delay must be a positive integer${NC}"
                exit 1
            fi
            RETRY_DELAY="$2"
            shift 2
            ;;
        --exponential-backoff)
            EXPONENTIAL_BACKOFF=true
            shift
            ;;
        --health-check-interval)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --health-check-interval requires a numeric value${NC}"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Error: --health-check-interval must be a positive integer${NC}"
                exit 1
            fi
            HEALTH_CHECK_INTERVAL="$2"
            shift 2
            ;;
        --health-check-timeout)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: --health-check-timeout requires a numeric value${NC}"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Error: --health-check-timeout must be a positive integer${NC}"
                exit 1
            fi
            HEALTH_CHECK_INACTIVITY_TIMEOUT="$2"
            shift 2
            ;;
        --no-health-check)
            HEALTH_CHECK_ENABLED=false
            shift
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
LOCK_FILE="$(dirname "$TODO_FILE")/.ralph_loop.lock"
LOG_DIR="$(dirname "$TODO_FILE")/logs/claude_outputs"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

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
echo "  Max retries per task: $MAX_RETRIES"
echo "  Retry delay: ${RETRY_DELAY}s$([ "$EXPONENTIAL_BACKOFF" = true ] && echo " (exponential backoff enabled)")"
if [ "$HEALTH_CHECK_ENABLED" = true ]; then
    echo "  Health check: enabled (check every ${HEALTH_CHECK_INTERVAL}s, timeout after ${HEALTH_CHECK_INACTIVITY_TIMEOUT}s of inactivity)"
else
    echo "  Health check: disabled"
fi
echo "  Todo list: $TODO_FILE"
echo "  Working directory: $WORKING_DIR"
echo "  Progress file: $PROGRESS_FILE"
echo "  Log directory: $LOG_DIR"
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

# ============================================================================
# Lock File Management & Stuck Task Recovery
# ============================================================================

# Function to check if a process is still running
is_process_running() {
    local pid="$1"
    if [ -z "$pid" ]; then
        return 1
    fi
    kill -0 "$pid" 2>/dev/null
}

# Function to create lock file
create_lock_file() {
    echo $$ > "$LOCK_FILE"
    echo -e "${BLUE}Created lock file: $LOCK_FILE (PID: $$)${NC}"
}

# Function to remove lock file
cleanup_lock_file() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        # Only remove if we own the lock
        if [ "$lock_pid" = "$$" ]; then
            rm -f "$LOCK_FILE"
            echo -e "${BLUE}Removed lock file${NC}"
        fi
    fi
}

# Function to check for concurrent loops
check_concurrent_loop() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$lock_pid" ] && is_process_running "$lock_pid"; then
            echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║                   CONCURRENT LOOP DETECTED                     ║${NC}"
            echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo -e "${RED}Another Ralph Wiggum Loop is already running!${NC}"
            echo -e "${YELLOW}  Lock file: $LOCK_FILE${NC}"
            echo -e "${YELLOW}  Running PID: $lock_pid${NC}"
            echo ""
            echo -e "${YELLOW}If you believe this is an error (e.g., stale lock from a crash),${NC}"
            echo -e "${YELLOW}you can remove the lock file manually:${NC}"
            echo -e "${BLUE}  rm \"$LOCK_FILE\"${NC}"
            echo ""
            exit 1
        else
            # Stale lock file - process is not running
            echo -e "${YELLOW}Found stale lock file (PID $lock_pid is not running). Removing...${NC}"
            rm -f "$LOCK_FILE"
        fi
    fi
}

# Function to detect stuck tasks (tasks with in_progress status)
detect_stuck_tasks() {
    jq -r '[.tasks[] | select(.status == "in_progress")] | length' "$TODO_FILE" 2>/dev/null || echo "0"
}

# Function to get stuck task IDs and names
get_stuck_tasks_info() {
    jq -r '.tasks[] | select(.status == "in_progress") | "\(.id): \(.name)"' "$TODO_FILE" 2>/dev/null || true
}

# Function to reset stuck tasks to pending
reset_stuck_tasks() {
    local tmp_file=$(mktemp)
    if jq '
        .tasks = [.tasks[] |
            if .status == "in_progress" then
                .status = "pending" |
                .notes = (if .notes == null or .notes == "" then "Auto-recovered from stuck in_progress state" else .notes + "\nAuto-recovered from stuck in_progress state" end) |
                .failure_count = (.failure_count + 1)
            else . end
        ] |
        .statistics.pending = ([.tasks[] | select(.status == "pending")] | length) |
        .statistics.in_progress = ([.tasks[] | select(.status == "in_progress")] | length) |
        .statistics.passed = ([.tasks[] | select(.status == "passed")] | length) |
        .statistics.failed = ([.tasks[] | select(.status == "failed")] | length) |
        .statistics.skipped = ([.tasks[] | select(.status == "skipped")] | length) |
        .metadata.last_updated = (now | strftime("%Y-%m-%d"))
    ' "$TODO_FILE" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$TODO_FILE"
    else
        echo -e "${YELLOW}Warning: Failed to reset stuck tasks (JSON operation failed)${NC}"
        rm -f "$tmp_file"
    fi
}

# Function to check for and handle stuck tasks
handle_stuck_tasks() {
    local stuck_count=$(detect_stuck_tasks)

    if [ "$stuck_count" -gt 0 ]; then
        echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║                   STUCK TASKS DETECTED                         ║${NC}"
        echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Found $stuck_count task(s) with 'in_progress' status:${NC}"
        echo ""
        get_stuck_tasks_info | while read -r line; do
            echo -e "  ${BLUE}• $line${NC}"
        done
        echo ""
        echo -e "${YELLOW}This usually happens when a previous loop was interrupted.${NC}"
        echo -e "${YELLOW}These tasks cannot proceed until they are reset to 'pending'.${NC}"
        echo ""

        # Ask user for confirmation
        read -p "Reset stuck tasks to 'pending' status? (y/N): " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Resetting stuck tasks...${NC}"
            reset_stuck_tasks

            # Log the recovery
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            cat >> "$PROGRESS_FILE" << EOF

--------------------------------------------------------------------------------
Timestamp: $timestamp
Event: AUTO-RECOVERY
Summary: Reset $stuck_count stuck task(s) from 'in_progress' to 'pending' status
Reason: Previous loop was interrupted, leaving tasks in stuck state
--------------------------------------------------------------------------------
EOF
            echo -e "${GREEN}Successfully reset $stuck_count task(s) to pending status.${NC}"
            echo ""
        else
            echo -e "${RED}Cannot proceed with stuck tasks. Exiting.${NC}"
            echo -e "${YELLOW}To manually fix, edit $TODO_FILE and change 'in_progress' to 'pending'.${NC}"
            exit 1
        fi
    fi
}

# Set up trap to clean up lock file on exit
trap cleanup_lock_file EXIT INT TERM

# Check for concurrent loop before proceeding
check_concurrent_loop

# Check for and handle stuck tasks
handle_stuck_tasks

# Create lock file for this session
create_lock_file

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
    ' "$TODO_FILE" 2>/dev/null || echo ""
}

# Function to check if all remaining tasks have failed too many times
all_tasks_exhausted() {
    local remaining=$(jq -r --argjson max_failures "$MAX_FAILURES" '
        [.tasks[] | select(
            .status == "pending" and
            .failure_count < $max_failures
        )] | length
    ' "$TODO_FILE" 2>/dev/null || echo "0")

    [ "$remaining" -eq 0 ]
}

# Function to get task details
get_task_details() {
    local task_id="$1"
    jq -r --arg id "$task_id" '.tasks[] | select(.id == $id)' "$TODO_FILE" 2>/dev/null || echo "{}"
}

# Function to update task status in todo list
update_task_status() {
    local task_id="$1"
    local new_status="$2"
    local notes="$3"

    local tmp_file=$(mktemp)
    if jq --arg id "$task_id" --arg status "$new_status" --arg notes "$notes" '
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
    ' "$TODO_FILE" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$TODO_FILE"
    else
        echo -e "${YELLOW}Warning: Failed to update task status (JSON operation failed)${NC}"
        rm -f "$tmp_file"
    fi
}

# Function to increment failure count
increment_failure_count() {
    local task_id="$1"

    local tmp_file=$(mktemp)
    if jq --arg id "$task_id" '
        .tasks = [.tasks[] |
            if .id == $id then
                .failure_count = (.failure_count + 1)
            else . end
        ]
    ' "$TODO_FILE" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$TODO_FILE"
    else
        echo -e "${YELLOW}Warning: Failed to increment failure count (JSON operation failed)${NC}"
        rm -f "$tmp_file"
    fi
}

# ============================================================================
# Acceptance Criteria Validation (Issue #18)
# ============================================================================

# Function to validate task completion by checking acceptance criteria
# Returns 0 if validation passes, 1 if it fails
validate_task_completion() {
    local task_id="$1"
    local task_json=$(get_task_details "$task_id")

    local validation_passed=true
    local validation_notes=""

    echo -e "${BLUE}Validating task completion for $task_id...${NC}"

    # 1. Check if expected files exist (from files_likely_affected)
    local files_affected=$(echo "$task_json" | jq -r '.files_likely_affected // []')
    local files_count=$(echo "$files_affected" | jq -r 'length')

    if [ "$files_count" -gt 0 ]; then
        echo -e "${BLUE}  Checking expected files...${NC}"
        local files_exist_count=0
        local files_modified_count=0

        for file in $(echo "$files_affected" | jq -r '.[]'); do
            # Resolve relative paths
            local full_path="$file"
            if [[ ! "$file" = /* ]]; then
                full_path="$WORKING_DIR/$file"
            fi

            if [ -f "$full_path" ]; then
                files_exist_count=$((files_exist_count + 1))
                echo -e "${GREEN}    ✓ File exists: $file${NC}"

                # Check if file was recently modified (within last hour)
                if [ "$(find "$full_path" -mmin -60 2>/dev/null)" ]; then
                    files_modified_count=$((files_modified_count + 1))
                    echo -e "${GREEN}    ✓ File recently modified: $file${NC}"
                fi
            else
                echo -e "${YELLOW}    ○ File not found: $file${NC}"
            fi
        done

        validation_notes="Files: $files_exist_count/$files_count exist"
        if [ "$files_modified_count" -gt 0 ]; then
            validation_notes="$validation_notes, $files_modified_count recently modified"
        fi
    fi

    # 2. Check git status for changes
    echo -e "${BLUE}  Checking git status...${NC}"
    pushd "$WORKING_DIR" > /dev/null 2>&1 || true

    if command -v git &> /dev/null && [ -d ".git" ] || git rev-parse --git-dir > /dev/null 2>&1; then
        local git_status=$(git status --porcelain 2>/dev/null || echo "")
        local staged_changes=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
        local unstaged_changes=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
        local untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
        local recent_commits=$(git log --oneline --since="1 hour ago" 2>/dev/null | wc -l | tr -d ' ')

        echo -e "${BLUE}    Git status: staged=$staged_changes, unstaged=$unstaged_changes, untracked=$untracked_files, recent_commits=$recent_commits${NC}"

        if [ "$recent_commits" -gt 0 ]; then
            echo -e "${GREEN}    ✓ Recent commits found${NC}"
            validation_notes="$validation_notes; $recent_commits recent commit(s)"
        fi

        if [ "$staged_changes" -gt 0 ] || [ "$unstaged_changes" -gt 0 ]; then
            echo -e "${GREEN}    ✓ File changes detected${NC}"
            local total_changes=$((staged_changes + unstaged_changes))
            validation_notes="$validation_notes; $total_changes file change(s)"
        fi
    else
        echo -e "${YELLOW}    ○ Not a git repository or git not available${NC}"
    fi

    popd > /dev/null 2>&1 || true

    # 3. Basic acceptance criteria checks (check for file patterns mentioned in criteria)
    local acceptance_criteria=$(echo "$task_json" | jq -r '.acceptance_criteria // []')
    local criteria_count=$(echo "$acceptance_criteria" | jq -r 'length')

    if [ "$criteria_count" -gt 0 ]; then
        echo -e "${BLUE}  Checking acceptance criteria patterns...${NC}"
        local criteria_hints_found=0

        pushd "$WORKING_DIR" > /dev/null 2>&1 || true

        for criteria in $(echo "$acceptance_criteria" | jq -r '.[]' | tr ' ' '_'); do
            # Restore spaces
            criteria=$(echo "$criteria" | tr '_' ' ')

            # Look for file patterns mentioned in criteria (e.g., "*.test.ts", "src/", etc.)
            # Extract potential file extensions or patterns
            if echo "$criteria" | grep -qE '\.(ts|js|py|sh|json|md|yml|yaml|tsx|jsx)'; then
                local ext=$(echo "$criteria" | grep -oE '\.(ts|js|py|sh|json|md|yml|yaml|tsx|jsx)' | head -1)
                local pattern_files=$(find . -name "*$ext" -mmin -60 2>/dev/null | head -5)
                if [ -n "$pattern_files" ]; then
                    criteria_hints_found=$((criteria_hints_found + 1))
                    echo -e "${GREEN}    ✓ Found recently modified $ext files${NC}"
                fi
            fi

            # Look for keywords like "create", "add", "implement" and associated file patterns
            if echo "$criteria" | grep -qiE '(create|add|implement|write).*file'; then
                local new_files=$(git ls-files --others --exclude-standard 2>/dev/null | head -5)
                if [ -n "$new_files" ]; then
                    criteria_hints_found=$((criteria_hints_found + 1))
                    echo -e "${GREEN}    ✓ New files detected (matching 'create/add file' criteria)${NC}"
                fi
            fi
        done

        popd > /dev/null 2>&1 || true

        if [ "$criteria_hints_found" -gt 0 ]; then
            validation_notes="$validation_notes; $criteria_hints_found criteria hints matched"
        fi
    fi

    echo -e "${BLUE}  Validation summary: $validation_notes${NC}"

    # Store validation notes for later use
    VALIDATION_NOTES="$validation_notes"

    # Return success - we use this for informational purposes, not as a hard gate
    return 0
}

# Function to check if task appears to have completed successfully based on artifacts
# This provides a secondary validation when exit code is non-zero
check_task_artifacts() {
    local task_id="$1"
    local task_json=$(get_task_details "$task_id")

    local artifact_score=0
    local max_score=0

    pushd "$WORKING_DIR" > /dev/null 2>&1 || true

    # Check 1: Recent git commits mentioning the task ID (weight: 3)
    max_score=$((max_score + 3))
    if command -v git &> /dev/null; then
        local task_commits=$(git log --oneline --since="1 hour ago" --grep="$task_id" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$task_commits" -gt 0 ]; then
            artifact_score=$((artifact_score + 3))
            echo -e "${GREEN}    ✓ Found $task_commits commit(s) mentioning task ID${NC}"
        fi
    fi

    # Check 2: Files in files_likely_affected were modified (weight: 2)
    max_score=$((max_score + 2))
    local files_affected=$(echo "$task_json" | jq -r '.files_likely_affected // [] | .[]' 2>/dev/null)
    local modified_count=0

    for file in $files_affected; do
        local full_path="$file"
        if [[ ! "$file" = /* ]]; then
            full_path="$WORKING_DIR/$file"
        fi

        if [ -f "$full_path" ] && [ "$(find "$full_path" -mmin -60 2>/dev/null)" ]; then
            modified_count=$((modified_count + 1))
        fi
    done

    if [ "$modified_count" -gt 0 ]; then
        artifact_score=$((artifact_score + 2))
        echo -e "${GREEN}    ✓ $modified_count expected file(s) were recently modified${NC}"
    fi

    # Check 3: Todo list status was updated to passed (weight: 5 - definitive)
    max_score=$((max_score + 5))
    local current_status=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE" 2>/dev/null || echo "unknown")
    if [ "$current_status" = "passed" ]; then
        artifact_score=$((artifact_score + 5))
        echo -e "${GREEN}    ✓ Task status was updated to 'passed'${NC}"
    fi

    # Check 4: Progress file was updated with this task (weight: 2)
    max_score=$((max_score + 2))
    if [ -f "$PROGRESS_FILE" ]; then
        local recent_progress=$(tail -50 "$PROGRESS_FILE" | grep -c "$task_id" || echo "0")
        if [ "$recent_progress" -gt 0 ]; then
            artifact_score=$((artifact_score + 2))
            echo -e "${GREEN}    ✓ Progress file was updated with task info${NC}"
        fi
    fi

    popd > /dev/null 2>&1 || true

    # Calculate percentage
    local percentage=0
    if [ "$max_score" -gt 0 ]; then
        percentage=$((artifact_score * 100 / max_score))
    fi

    echo -e "${BLUE}    Artifact validation score: $artifact_score/$max_score ($percentage%)${NC}"

    # Store the score for decision making
    ARTIFACT_SCORE=$artifact_score
    ARTIFACT_MAX_SCORE=$max_score
    ARTIFACT_PERCENTAGE=$percentage

    # Consider task successful if score is >= 50% or status is passed
    if [ "$percentage" -ge 50 ] || [ "$current_status" = "passed" ]; then
        return 0
    else
        return 1
    fi
}

# Function to log progress
log_progress() {
    local task_id="$1"
    local status="$2"
    local summary="$3"
    local error_msg="$4"
    local lessons="$5"
    local log_file="${6:-$CURRENT_LOG_FILE}"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat >> "$PROGRESS_FILE" << EOF

--------------------------------------------------------------------------------
Timestamp: $timestamp
Task ID: $task_id
Status: $status
Summary: $summary
EOF

    if [ -n "$log_file" ] && [ -f "$log_file" ]; then
        cat >> "$PROGRESS_FILE" << EOF
Log File: $log_file
EOF
    fi

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
    local build_command=$(jq -r '.metadata.build_command // ""' "$TODO_FILE" 2>/dev/null || echo "")
    local test_command=$(jq -r '.metadata.test_command // ""' "$TODO_FILE" 2>/dev/null || echo "")
    local extra_instructions=$(jq -r '.metadata.extra_instructions // ""' "$TODO_FILE" 2>/dev/null || echo "")

    # Get previous lessons from progress.txt for this task
    # Uses awk to find the most recent entry for this task and extract its lessons
    local prev_lessons=""
    if [ -f "$PROGRESS_FILE" ] && [ "$failure_count" -gt 0 ]; then
        prev_lessons=$(awk -v taskid="$task_id" '
            /^Task ID:/ && index($0, taskid) { in_task=1; lesson="" }
            in_task && /^Lessons Learned:/ { sub(/^Lessons Learned: */, ""); lesson=$0 }
            in_task && /^----------------/ { in_task=0 }
            END { print lesson }
        ' "$PROGRESS_FILE" 2>/dev/null || echo "")
    fi

    cat > "$PROMPT_FILE" << EOF
# ${PROJECT_NAME} - Task Implementation

**IMPORTANT: This is an automated run. Complete the task fully and exit without asking any follow-up questions. Do not ask "Would you like me to proceed?" or similar interactive prompts. Execute all required steps autonomously and terminate when done.**

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
6. **NO FOLLOW-UP QUESTIONS** - This is automated. Do not ask "Would you like me to..." or similar. Complete the task and exit.
${build_command:+7. **Build must compile** - verify with \`$build_command\`}

## Reference Files

- Todo list: $TODO_FILE
- Progress: $PROGRESS_FILE
- Working Directory: $WORKING_DIR

Good luck! Remember to update the todo list and progress.txt before you finish.
EOF

    echo "$PROMPT_FILE"
}

# Global variable to store current log file path
CURRENT_LOG_FILE=""

# ============================================================================
# Health Check Monitoring (Issue #22)
# ============================================================================

# Global variable to track health check monitor PID
HEALTH_CHECK_PID=""

# Function to start health check monitor as a background process
# Monitors log file size and kills the process if no activity for too long
start_health_check_monitor() {
    local log_file="$1"
    local claude_pid="$2"
    local check_interval="${HEALTH_CHECK_INTERVAL:-30}"
    local inactivity_timeout="${HEALTH_CHECK_INACTIVITY_TIMEOUT:-300}"

    if [ "$HEALTH_CHECK_ENABLED" != true ]; then
        return 0
    fi

    # Start background monitor
    (
        local last_size=0
        local last_activity_time=$(date +%s)
        local status_file="${log_file}.health_status"

        echo "RUNNING" > "$status_file"

        while true; do
            sleep "$check_interval"

            # Check if Claude process is still running
            if ! kill -0 "$claude_pid" 2>/dev/null; then
                rm -f "$status_file"
                exit 0
            fi

            # Check log file size
            local current_size=0
            if [ -f "$log_file" ]; then
                current_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo "0")
            fi

            local current_time=$(date +%s)

            # Check if there's activity (file size changed)
            if [ "$current_size" -gt "$last_size" ]; then
                last_size=$current_size
                last_activity_time=$current_time
            else
                # No activity - check if we've exceeded inactivity timeout
                local inactive_duration=$((current_time - last_activity_time))

                if [ "$inactive_duration" -ge "$inactivity_timeout" ]; then
                    echo "HUNG" > "$status_file"
                    # Process appears hung - kill it
                    echo -e "\n${RED}[Health Check] Process hung detected! No log activity for ${inactive_duration}s (timeout: ${inactivity_timeout}s)${NC}" >&2
                    echo -e "${YELLOW}[Health Check] Terminating hung Claude process (PID: $claude_pid)...${NC}" >&2

                    # Add a marker to the log file
                    echo "" >> "$log_file"
                    echo "=================================================================================" >> "$log_file"
                    echo "[HEALTH CHECK] Process terminated due to inactivity (no output for ${inactive_duration}s)" >> "$log_file"
                    echo "[HEALTH CHECK] Timeout threshold: ${inactivity_timeout}s" >> "$log_file"
                    echo "[HEALTH CHECK] Termination time: $(date '+%Y-%m-%d %H:%M:%S')" >> "$log_file"
                    echo "=================================================================================" >> "$log_file"

                    # Graceful termination first
                    kill -TERM "$claude_pid" 2>/dev/null || true
                    sleep 3
                    # Force kill if still running
                    kill -KILL "$claude_pid" 2>/dev/null || true

                    rm -f "$status_file"
                    exit 0
                fi
            fi
        done
    ) &

    HEALTH_CHECK_PID=$!
}

# Function to stop health check monitor
stop_health_check_monitor() {
    local log_file="${1:-}"

    if [ -n "${HEALTH_CHECK_PID:-}" ]; then
        kill "$HEALTH_CHECK_PID" 2>/dev/null || true
        wait "$HEALTH_CHECK_PID" 2>/dev/null || true
        HEALTH_CHECK_PID=""
    fi

    # Clean up status file
    if [ -n "$log_file" ]; then
        rm -f "${log_file}.health_status" 2>/dev/null || true
    fi
}

# Function to check if process was terminated by health check
was_killed_by_health_check() {
    local log_file="$1"

    # Check status file
    local status_file="${log_file}.health_status"
    if [ -f "$status_file" ] && [ "$(cat "$status_file" 2>/dev/null)" = "HUNG" ]; then
        rm -f "$status_file"
        return 0
    fi

    # Also check log file for health check marker
    if [ -f "$log_file" ] && grep -q "\[HEALTH CHECK\] Process terminated due to inactivity" "$log_file" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Function to detect API errors in logs (Issue #22)
# Returns 0 if API error detected, 1 otherwise
detect_api_errors() {
    local log_file="$1"
    local stderr_log="$2"

    local api_error_patterns=(
        "No messages returned"
        "API error"
        "rate limit"
        "overloaded"
        "connection refused"
        "connection reset"
        "timeout"
        "ECONNRESET"
        "ETIMEDOUT"
        "socket hang up"
        "network error"
        "503 Service"
        "502 Bad Gateway"
        "500 Internal Server"
        "429 Too Many"
    )

    local error_found=""

    for pattern in "${api_error_patterns[@]}"; do
        if [ -f "$log_file" ] && grep -qi "$pattern" "$log_file" 2>/dev/null; then
            error_found="$pattern (in log file)"
            break
        fi
        if [ -f "$stderr_log" ] && grep -qi "$pattern" "$stderr_log" 2>/dev/null; then
            error_found="$pattern (in stderr)"
            break
        fi
    done

    if [ -n "$error_found" ]; then
        echo "$error_found"
        return 0
    fi

    return 1
}

# Function to check for empty log output (Issue #22)
# Returns 0 if log is empty/nearly empty, 1 otherwise
check_empty_log() {
    local log_file="$1"
    local min_content_size=100  # Minimum bytes of actual content expected

    if [ ! -f "$log_file" ]; then
        return 0  # No log file = empty
    fi

    local file_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo "0")

    # Account for the header we add (approximately 400 bytes)
    local header_size=400
    local content_size=$((file_size - header_size))

    if [ "$content_size" -lt "$min_content_size" ]; then
        return 0  # Log is effectively empty
    fi

    # Additional check: look for actual Claude output content
    # The log should contain more than just our headers and footers
    local meaningful_lines=$(grep -v "^===\|^Ralph Wiggum\|^Task ID:\|^Attempt:\|^Timestamp:\|^Timeout:\|^Working Directory:\|^Execution completed\|^Exit code:\|^$" "$log_file" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$meaningful_lines" -lt 5 ]; then
        return 0  # Not enough meaningful content
    fi

    return 1  # Log has content
}

# Function to run Claude with timeout
run_claude_with_timeout() {
    local prompt_file="$1"
    local task_id="$2"
    local attempt_num="${3:-1}"

    # Generate log file path with timestamp and attempt number
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local log_file="${LOG_DIR}/${task_id}_${timestamp}_attempt${attempt_num}.log"
    local stderr_log="${LOG_DIR}/${task_id}_${timestamp}_attempt${attempt_num}_stderr.log"
    CURRENT_LOG_FILE="$log_file"
    CURRENT_STDERR_LOG="$stderr_log"

    echo -e "${BLUE}Running Claude CLI...${NC}"
    echo -e "${BLUE}Log file: $log_file${NC}"
    if [ "$HEALTH_CHECK_ENABLED" = true ]; then
        echo -e "${BLUE}Health check: enabled (interval: ${HEALTH_CHECK_INTERVAL}s, inactivity timeout: ${HEALTH_CHECK_INACTIVITY_TIMEOUT}s)${NC}"
    fi
    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

    # Write log header
    cat > "$log_file" << EOF
================================================================================
Ralph Wiggum Loop - Claude Execution Log
================================================================================
Task ID: $task_id
Attempt: $attempt_num
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Timeout: ${TIMEOUT_SECONDS}s
Health Check: $([ "$HEALTH_CHECK_ENABLED" = true ] && echo "enabled (${HEALTH_CHECK_INTERVAL}s interval, ${HEALTH_CHECK_INACTIVITY_TIMEOUT}s inactivity timeout)" || echo "disabled")
Working Directory: $WORKING_DIR
================================================================================

EOF

    # Use timeout command (gtimeout on macOS if coreutils installed, otherwise use perl)
    local timeout_cmd=""
    if command -v gtimeout &> /dev/null; then
        timeout_cmd="gtimeout"
    elif command -v timeout &> /dev/null; then
        timeout_cmd="timeout"
    fi

    local exit_code=0
    local was_hung=false
    local api_error=""

    # Change to working directory for Claude execution
    pushd "$WORKING_DIR" > /dev/null 2>&1 || true

    if [ -n "$timeout_cmd" ]; then
        # Use timeout command with tee to capture output while displaying
        # For health check with timeout command, we need to run in background to get PID
        if [ "$HEALTH_CHECK_ENABLED" = true ]; then
            # Run with health check monitoring
            if command -v stdbuf &> /dev/null; then
                stdbuf -oL -eL $timeout_cmd $TIMEOUT_SECONDS claude --dangerously-skip-permissions --print --no-session-persistence "$(cat "$prompt_file")" 2> >(tee -a "$stderr_log" >&2) | tee -a "$log_file" &
            else
                $timeout_cmd $TIMEOUT_SECONDS claude --dangerously-skip-permissions --print --no-session-persistence "$(cat "$prompt_file")" 2> >(tee -a "$stderr_log" >&2) | tee -a "$log_file" &
            fi
            local claude_pid=$!

            # Start health check monitor
            start_health_check_monitor "$log_file" "$claude_pid"

            # Wait for completion
            wait $claude_pid || exit_code=$?

            # Stop health check monitor
            stop_health_check_monitor "$log_file"

            # Check if killed by health check
            if was_killed_by_health_check "$log_file"; then
                was_hung=true
                exit_code=125  # Custom exit code for health check termination
            fi
        else
            # Run without health check (original behavior)
            if command -v stdbuf &> /dev/null; then
                stdbuf -oL -eL $timeout_cmd $TIMEOUT_SECONDS claude --dangerously-skip-permissions --print --no-session-persistence "$(cat "$prompt_file")" 2> >(tee -a "$stderr_log" >&2) | tee -a "$log_file" || exit_code=$?
            else
                $timeout_cmd $TIMEOUT_SECONDS claude --dangerously-skip-permissions --print --no-session-persistence "$(cat "$prompt_file")" 2> >(tee -a "$stderr_log" >&2) | tee -a "$log_file" || exit_code=$?
            fi
        fi
    else
        # Fallback: use background process with manual timeout
        # Use log file directly instead of /tmp
        claude --dangerously-skip-permissions --print --no-session-persistence "$(cat "$prompt_file")" 2> >(tee -a "$stderr_log" >&2) | tee -a "$log_file" &
        local claude_pid=$!

        # Start health check monitor
        start_health_check_monitor "$log_file" "$claude_pid"

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

            # Check if health check killed the process
            if was_killed_by_health_check "$log_file"; then
                was_hung=true
                exit_code=125  # Custom exit code for health check termination
                break
            fi
        done

        if [ $exit_code -eq 0 ] && [ "$was_hung" != true ]; then
            wait $claude_pid || exit_code=$?
        fi

        # Stop health check monitor
        stop_health_check_monitor "$log_file"
    fi

    # Post-execution checks (Issue #22)

    # Check for empty log (process exited with 0 but no output)
    if [ $exit_code -eq 0 ] && check_empty_log "$log_file"; then
        echo -e "${RED}[Issue #22] Empty log detected! Process exited successfully but produced no output.${NC}"
        echo "" >> "$log_file"
        echo "=================================================================================" >> "$log_file"
        echo "[EMPTY LOG DETECTION] Process exited with code 0 but produced no meaningful output" >> "$log_file"
        echo "[EMPTY LOG DETECTION] This is treated as a failure - triggering retry logic" >> "$log_file"
        echo "=================================================================================" >> "$log_file"
        exit_code=126  # Custom exit code for empty log
    fi

    # Check for API errors in logs
    api_error=$(detect_api_errors "$log_file" "$stderr_log" || echo "")
    if [ -n "$api_error" ]; then
        echo -e "${RED}[Issue #22] API error detected: $api_error${NC}"
        echo "" >> "$log_file"
        echo "=================================================================================" >> "$log_file"
        echo "[API ERROR DETECTION] API error detected: $api_error" >> "$log_file"
        echo "[API ERROR DETECTION] This is treated as a failure - triggering retry logic" >> "$log_file"
        echo "=================================================================================" >> "$log_file"
        # Force failure status even if exit code was 0
        if [ $exit_code -eq 0 ]; then
            exit_code=127  # Custom exit code for API error
        fi
    fi

    # Append footer to log file
    local status_msg="Exit code: $exit_code"
    if [ "$was_hung" = true ]; then
        status_msg="$status_msg (HUNG - killed by health check)"
    elif [ $exit_code -eq 124 ]; then
        status_msg="$status_msg (TIMEOUT)"
    elif [ $exit_code -eq 126 ]; then
        status_msg="$status_msg (EMPTY LOG)"
    elif [ $exit_code -eq 127 ] || [ -n "$api_error" ]; then
        status_msg="$status_msg (API ERROR: $api_error)"
    fi

    cat >> "$log_file" << EOF

================================================================================
Execution completed at: $(date '+%Y-%m-%d %H:%M:%S')
$status_msg
================================================================================
EOF

    # Remove empty stderr log if no errors
    if [ ! -s "$stderr_log" ]; then
        rm -f "$stderr_log"
    fi

    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}Log saved to: $log_file${NC}"

    # Return to original directory
    popd > /dev/null 2>&1 || true

    return $exit_code
}

# Global variable for stderr log path
CURRENT_STDERR_LOG=""

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

# Function to handle hung process (Issue #22)
handle_hung_process() {
    local task_id="$1"

    echo -e "${RED}Handling hung process for task $task_id...${NC}"

    # Update todo list to mark as pending (will retry)
    update_task_status "$task_id" "pending" "Process hung - no log activity for ${HEALTH_CHECK_INACTIVITY_TIMEOUT}s (Issue #22)"
    increment_failure_count "$task_id"

    # Log progress
    log_progress "$task_id" "HUNG" \
        "Process hung due to inactivity (no output for ${HEALTH_CHECK_INACTIVITY_TIMEOUT}s)" \
        "Health check detected process was stuck with no log activity" \
        "Possible API hang or network issue. Process terminated by health check monitor."

    echo -e "${RED}Hung process handled. Task will be retried.${NC}"
}

# Function to handle empty log (Issue #22)
handle_empty_log() {
    local task_id="$1"

    echo -e "${RED}Handling empty log for task $task_id...${NC}"

    # Update todo list to mark as pending (will retry)
    update_task_status "$task_id" "pending" "Empty log detected - process produced no output (Issue #22)"
    increment_failure_count "$task_id"

    # Log progress
    log_progress "$task_id" "EMPTY_LOG" \
        "Process exited with code 0 but produced no meaningful output" \
        "Claude API may have returned empty response or failed silently" \
        "This often indicates API issues. Will retry with next attempt."

    echo -e "${RED}Empty log handled. Task will be retried.${NC}"
}

# Function to handle API error (Issue #22)
handle_api_error() {
    local task_id="$1"
    local error_msg="$2"

    echo -e "${RED}Handling API error for task $task_id: $error_msg${NC}"

    # Update todo list to mark as pending (will retry)
    update_task_status "$task_id" "pending" "API error: $error_msg (Issue #22)"
    increment_failure_count "$task_id"

    # Log progress
    log_progress "$task_id" "API_ERROR" \
        "Claude API returned an error: $error_msg" \
        "$error_msg" \
        "API errors are usually transient. Will retry after delay."

    echo -e "${RED}API error handled. Task will be retried.${NC}"
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

    # Run Claude with retry logic
    start_time=$(date +%s)
    attempt=1
    task_succeeded=false
    last_exit_code=0

    while [ $attempt -le $MAX_RETRIES ]; do
        if [ $attempt -gt 1 ]; then
            # Calculate delay (with optional exponential backoff)
            if [ "$EXPONENTIAL_BACKOFF" = true ]; then
                current_delay=$((RETRY_DELAY * attempt))
            else
                current_delay=$RETRY_DELAY
            fi
            echo -e "${YELLOW}Waiting ${current_delay}s before retry attempt $attempt of $MAX_RETRIES...${NC}"
            sleep $current_delay
            echo ""
        fi

        echo -e "${BLUE}Attempt $attempt of $MAX_RETRIES${NC}"

        if run_claude_with_timeout "$prompt_file" "$task_id" "$attempt"; then
            echo -e "${GREEN}Claude completed successfully on attempt $attempt.${NC}"
            task_succeeded=true
            break
        else
            last_exit_code=$?

            # Handle different exit codes (Issue #22 enhancements)
            case $last_exit_code in
                124)
                    # Timeout - don't retry timeouts, they take too long
                    echo -e "${RED}Task timed out on attempt $attempt. Not retrying timeouts.${NC}"
                    handle_timeout "$task_id"
                    break
                    ;;
                125)
                    # Hung process detected by health check - will retry
                    echo -e "${RED}Task hung on attempt $attempt (health check detected no activity).${NC}"
                    if [ $attempt -ge $MAX_RETRIES ]; then
                        handle_hung_process "$task_id"
                        break
                    else
                        echo -e "${YELLOW}Will retry (attempt $((attempt + 1)) of $MAX_RETRIES)...${NC}"
                        update_task_status "$task_id" "in_progress" "Retry after hung process (attempt $((attempt + 1)))"
                    fi
                    ;;
                126)
                    # Empty log detected - will retry
                    echo -e "${RED}Empty log detected on attempt $attempt.${NC}"
                    if [ $attempt -ge $MAX_RETRIES ]; then
                        handle_empty_log "$task_id"
                        break
                    else
                        echo -e "${YELLOW}Will retry (attempt $((attempt + 1)) of $MAX_RETRIES)...${NC}"
                        update_task_status "$task_id" "in_progress" "Retry after empty log (attempt $((attempt + 1)))"
                    fi
                    ;;
                127)
                    # API error detected - will retry
                    echo -e "${RED}API error detected on attempt $attempt.${NC}"
                    if [ $attempt -ge $MAX_RETRIES ]; then
                        # Get the API error message from log
                        local api_err_msg=$(grep -o "\[API ERROR DETECTION\] API error detected: .*" "$CURRENT_LOG_FILE" 2>/dev/null | head -1 | sed 's/\[API ERROR DETECTION\] API error detected: //')
                        handle_api_error "$task_id" "${api_err_msg:-Unknown API error}"
                        break
                    else
                        echo -e "${YELLOW}Will retry (attempt $((attempt + 1)) of $MAX_RETRIES)...${NC}"
                        update_task_status "$task_id" "in_progress" "Retry after API error (attempt $((attempt + 1)))"
                    fi
                    ;;
                *)
                    # Other exit codes - existing logic
                    echo -e "${RED}Claude exited with code $last_exit_code on attempt $attempt${NC}"
                    # Check if Claude updated the status to passed
                    current_status=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE" 2>/dev/null || echo "unknown")
                    if [ "$current_status" = "passed" ]; then
                        echo -e "${GREEN}Task was marked as passed despite exit code.${NC}"
                        task_succeeded=true
                        break
                    fi

                    # Issue #18: Validate task completion by checking acceptance criteria
                    echo -e "${BLUE}Performing artifact validation (Issue #18 enhancement)...${NC}"
                    if check_task_artifacts "$task_id"; then
                        echo -e "${GREEN}Artifact validation passed! Task appears to have completed successfully.${NC}"
                        # Update task status to passed if artifacts indicate success
                        if [ "$current_status" != "passed" ]; then
                            update_task_status "$task_id" "passed" "Auto-validated: artifacts indicate successful completion despite exit code $last_exit_code"
                            log_progress "$task_id" "PASSED (auto-validated)" \
                                "Task completed successfully (validated by artifact check)" \
                                "" \
                                "Exit code was $last_exit_code but artifact validation score was $ARTIFACT_PERCENTAGE%"
                        fi
                        task_succeeded=true
                        break
                    fi

                    if [ $attempt -lt $MAX_RETRIES ]; then
                        echo -e "${YELLOW}Will retry (attempt $((attempt + 1)) of $MAX_RETRIES)...${NC}"
                        # Reset status back to in_progress for retry
                        update_task_status "$task_id" "in_progress" "Retry attempt $((attempt + 1))"
                    fi
                    ;;
            esac
        fi
        attempt=$((attempt + 1))
    done

    # Handle final failure after all retries exhausted
    # Skip if already handled by timeout (124), hung (125), empty log (126), or API error (127)
    if [ "$task_succeeded" = false ] && [ $last_exit_code -ne 124 ] && [ $last_exit_code -ne 125 ] && [ $last_exit_code -ne 126 ] && [ $last_exit_code -ne 127 ]; then
        current_status=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE" 2>/dev/null || echo "unknown")
        if [ "$current_status" = "in_progress" ]; then
            # Final artifact validation check before marking as failed (Issue #18)
            echo -e "${BLUE}Final artifact validation before marking task as failed...${NC}"
            if check_task_artifacts "$task_id"; then
                echo -e "${GREEN}Final artifact validation passed! Marking task as successful.${NC}"
                update_task_status "$task_id" "passed" "Auto-validated after retries: artifacts indicate successful completion"
                log_progress "$task_id" "PASSED (auto-validated)" \
                    "Task completed successfully (final artifact validation passed)" \
                    "" \
                    "All retry attempts had non-zero exit codes, but artifact validation score was $ARTIFACT_PERCENTAGE%"
                task_succeeded=true
            else
                # Claude didn't update status after all retries, mark as failed
                echo -e "${RED}Artifact validation failed (score: $ARTIFACT_PERCENTAGE%). Marking task as failed.${NC}"
                update_task_status "$task_id" "pending" "Failed after $MAX_RETRIES attempts (exit code: $last_exit_code, artifact score: $ARTIFACT_PERCENTAGE%)"
                increment_failure_count "$task_id"
                log_progress "$task_id" "FAILED" \
                    "Claude failed after $MAX_RETRIES retry attempts" \
                    "Final exit code: $last_exit_code, Artifact validation score: $ARTIFACT_PERCENTAGE%" \
                    "Task failed consistently across all retry attempts. Consider breaking into smaller sub-tasks or checking for environmental issues."
            fi
        fi
    fi

    # Run validation for informational purposes on successful tasks
    if [ "$task_succeeded" = true ]; then
        echo -e "${BLUE}Running post-completion validation...${NC}"
        validate_task_completion "$task_id"
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    echo ""
    echo -e "${BLUE}Iteration $iteration completed in $((duration / 60))m $((duration % 60))s${NC}"
    echo ""

    # Show current statistics
    stats=$(jq '.statistics' "$TODO_FILE" 2>/dev/null || echo '{}')
    echo -e "${YELLOW}Current Statistics:${NC}"
    echo "$stats" | jq -r '"  Pending: \(.pending // 0) | Passed: \(.passed // 0) | Failed: \(.failed // 0)"' 2>/dev/null || echo "  (Statistics unavailable)"
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
jq '.statistics' "$TODO_FILE" 2>/dev/null || echo "  (Statistics unavailable)"

echo ""
echo -e "${YELLOW}Check progress.txt for detailed implementation log.${NC}"
echo -e "${YELLOW}Check the todo list for task status details.${NC}"
