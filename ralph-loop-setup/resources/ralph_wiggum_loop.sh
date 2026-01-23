#!/bin/bash

# Ralph Wiggum Loop - Automated Task Implementation
# "I'm helping!" - Ralph Wiggum
#
# A simple loop that runs Claude Code to work through tasks.
# Claude AI handles all the intelligence: task selection, implementation,
# logging, and status updates.

set -u

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_ITERATIONS=${1:-999999}
TODO_FILE="${2:-${SCRIPT_DIR}/todolist.json}"
LOG_DIR="${SCRIPT_DIR}/logs"

# Crash resilience configuration
MAX_RETRIES=3               # Retry each iteration up to 3 times on crash
MAX_CONSECUTIVE_FAILURES=3  # Stop loop after 3 consecutive failures
RETRY_DELAY=30              # Wait 30 seconds between retries
consecutive_failures=0      # Track consecutive failures across iterations

# Resolve paths
TODO_FILE="$(cd "$(dirname "$TODO_FILE")" 2>/dev/null && pwd)/$(basename "$TODO_FILE")"
WORKING_DIR="$(dirname "$TODO_FILE")"
PROGRESS_FILE="${WORKING_DIR}/progress.txt"

mkdir -p "$LOG_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Ralph Wiggum Loop - \"I'm helping!\"                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Todo file: $TODO_FILE"
echo "Working dir: $WORKING_DIR"
echo "Max iterations: $MAX_ITERATIONS"
echo ""

# Check dependencies
if ! command -v claude &> /dev/null; then
    echo -e "${RED}Error: 'claude' CLI not found${NC}"
    exit 1
fi

if [ ! -f "$TODO_FILE" ]; then
    echo -e "${RED}Error: Todo file not found: $TODO_FILE${NC}"
    exit 1
fi

# The prompt - this is where all the magic happens
create_prompt() {
    cat << 'EOF'
You are an AI assistant working through a project todo list.

## Your Task

1. **Read todolist.json** to see all tasks and their statuses
2. **Choose ONE task** that is:
   - Status is "pending" (not completed, failed, or in_progress)
   - Dependencies are satisfied (all tasks in "dependencies" array have status "passed")
   - Choose wisely based on priority, impact, and likelihood of success
3. **Implement the task** completely
4. **Update todolist.json** - set the task's status to "passed" or "failed"
5. **Append to progress.txt** with:
   - Timestamp and task ID
   - What you did
   - Any lessons learned for future iterations

## Important Rules

- Focus on ONE task only
- This is automated - no questions, just do the work
- Update both todolist.json and progress.txt before finishing
- If a task fails, mark it "failed" with notes explaining why
- If no eligible tasks remain, just report that and exit

## Files

- Todo list: TODOFILE_PLACEHOLDER
- Progress log: PROGRESSFILE_PLACEHOLDER
- Working directory: WORKINGDIR_PLACEHOLDER

Start now: Read the todo list, pick a task, implement it, update the files.
EOF
}

# Check if Claude crashed (vs intentional exit)
check_for_crash() {
    local log_file=$1
    # Look for common crash patterns in the log
    if grep -q "Error: No messages returned\|promise rejected\|async function without a catch\|ECONNREFUSED\|timeout" "$log_file" 2>/dev/null; then
        return 0  # Crash detected
    fi
    return 1  # No crash - Claude exited normally
}

# Main loop
iteration=0

while [ $iteration -lt $MAX_ITERATIONS ]; do
    iteration=$((iteration + 1))

    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Iteration $iteration${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"

    # Check if there are any pending tasks left
    pending_count=$(jq '[.tasks[] | select(.status == "pending")] | length' "$TODO_FILE" 2>/dev/null || echo "0")

    if [ "$pending_count" -eq 0 ]; then
        echo -e "${GREEN}All tasks completed!${NC}"
        break
    fi

    echo "Pending tasks: $pending_count"
    echo ""

    # Create prompt with actual paths
    prompt=$(create_prompt | sed \
        -e "s|TODOFILE_PLACEHOLDER|$TODO_FILE|g" \
        -e "s|PROGRESSFILE_PLACEHOLDER|$PROGRESS_FILE|g" \
        -e "s|WORKINGDIR_PLACEHOLDER|$WORKING_DIR|g")

    # Run Claude with retry logic
    log_file="${LOG_DIR}/iteration_${iteration}_$(date +%Y%m%d_%H%M%S).log"
    retry_count=0
    iteration_success=false

    echo "Running Claude..."
    echo ""

    cd "$WORKING_DIR"

    # Retry loop for this iteration
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if echo "$prompt" | claude --dangerously-skip-permissions --print > "$log_file" 2>&1; then
            # Success!
            echo -e "${GREEN}Iteration $iteration completed${NC}"
            iteration_success=true
            consecutive_failures=0
            break
        else
            exit_code=$?
            echo -e "${YELLOW}Claude exited with code $exit_code${NC}"

            # Check if it's a crash or intentional exit
            if check_for_crash "$log_file"; then
                # It's a crash - retry
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $MAX_RETRIES ]; then
                    echo -e "${RED}Claude crashed. Retrying in ${RETRY_DELAY}s... (attempt $((retry_count + 1))/${MAX_RETRIES})${NC}"
                    sleep $RETRY_DELAY
                    # Update log filename for retry
                    log_file="${LOG_DIR}/iteration_${iteration}_retry${retry_count}_$(date +%Y%m%d_%H%M%S).log"
                else
                    echo -e "${RED}All ${MAX_RETRIES} retry attempts failed${NC}"
                fi
            else
                # Not a crash - Claude intentionally exited (maybe task failed)
                # This is okay - Claude updated the status already
                echo -e "${YELLOW}Claude exited intentionally (task may have failed)${NC}"
                iteration_success=true
                consecutive_failures=0
                break
            fi
        fi
    done

    # Check if all retries failed
    if [ "$iteration_success" = false ]; then
        consecutive_failures=$((consecutive_failures + 1))
        echo -e "${RED}Iteration $iteration failed after $MAX_RETRIES attempts${NC}"
        echo -e "${RED}Consecutive failures: ${consecutive_failures}/${MAX_CONSECUTIVE_FAILURES}${NC}"

        if [ $consecutive_failures -ge $MAX_CONSECUTIVE_FAILURES ]; then
            echo ""
            echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${RED}║  Too many consecutive failures (${consecutive_failures}). Stopping loop.        ║${NC}"
            echo -e "${RED}║  Check logs for errors and retry manually.                    ║${NC}"
            echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
            exit 1
        fi

        # Wait before next iteration after failure
        echo -e "${YELLOW}Waiting ${RETRY_DELAY}s before next iteration...${NC}"
        sleep $RETRY_DELAY
    else
        # Brief pause between successful iterations
        sleep 2
    fi

    echo "Log: $log_file"
    echo ""
done

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Ralph Wiggum Loop finished after $iteration iterations       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
