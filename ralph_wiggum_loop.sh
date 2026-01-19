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
MAX_RETRIES=3  # Number of retry attempts per task before moving on
RETRY_DELAY=5  # Seconds to wait between retry attempts
EXPONENTIAL_BACKOFF=false  # If true, use exponential backoff (5s, 10s, 15s, etc.)
LOCK_FILE=""  # Will be set after TODO_FILE is determined

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
    jq -r '[.tasks[] | select(.status == "in_progress")] | length' "$TODO_FILE"
}

# Function to get stuck task IDs and names
get_stuck_tasks_info() {
    jq -r '.tasks[] | select(.status == "in_progress") | "\(.id): \(.name)"' "$TODO_FILE"
}

# Function to reset stuck tasks to pending
reset_stuck_tasks() {
    local tmp_file=$(mktemp)
    jq '
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
    ' "$TODO_FILE" > "$tmp_file" && mv "$tmp_file" "$TODO_FILE"
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
    local current_status=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")
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
    local build_command=$(jq -r '.metadata.build_command // ""' "$TODO_FILE")
    local test_command=$(jq -r '.metadata.test_command // ""' "$TODO_FILE")
    local extra_instructions=$(jq -r '.metadata.extra_instructions // ""' "$TODO_FILE")

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

    echo -e "${BLUE}Running Claude CLI...${NC}"
    echo -e "${BLUE}Log file: $log_file${NC}"
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

    # Change to working directory for Claude execution
    pushd "$WORKING_DIR" > /dev/null

    if [ -n "$timeout_cmd" ]; then
        # Use timeout command with tee to capture output while displaying
        if command -v stdbuf &> /dev/null; then
            stdbuf -oL -eL $timeout_cmd $TIMEOUT_SECONDS claude --dangerously-skip-permissions --print --no-session-persistence "$(cat "$prompt_file")" 2> >(tee -a "$stderr_log" >&2) | tee -a "$log_file" || exit_code=$?
        else
            $timeout_cmd $TIMEOUT_SECONDS claude --dangerously-skip-permissions --print --no-session-persistence "$(cat "$prompt_file")" 2> >(tee -a "$stderr_log" >&2) | tee -a "$log_file" || exit_code=$?
        fi
    else
        # Fallback: use background process with manual timeout
        # Use log file directly instead of /tmp
        claude --dangerously-skip-permissions --print --no-session-persistence "$(cat "$prompt_file")" 2> >(tee -a "$stderr_log" >&2) | tee -a "$log_file" &
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
    fi

    # Append footer to log file
    cat >> "$log_file" << EOF

================================================================================
Execution completed at: $(date '+%Y-%m-%d %H:%M:%S')
Exit code: $exit_code
================================================================================
EOF

    # Remove empty stderr log if no errors
    if [ ! -s "$stderr_log" ]; then
        rm -f "$stderr_log"
    fi

    echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}Log saved to: $log_file${NC}"

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
            if [ $last_exit_code -eq 124 ]; then
                # Timeout - don't retry timeouts, they take too long
                echo -e "${RED}Task timed out on attempt $attempt. Not retrying timeouts.${NC}"
                handle_timeout "$task_id"
                break
            else
                echo -e "${RED}Claude exited with code $last_exit_code on attempt $attempt${NC}"
                # Check if Claude updated the status to passed
                current_status=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")
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
            fi
        fi
        attempt=$((attempt + 1))
    done

    # Handle final failure after all retries exhausted
    if [ "$task_succeeded" = false ] && [ $last_exit_code -ne 124 ]; then
        current_status=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .status' "$TODO_FILE")
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
