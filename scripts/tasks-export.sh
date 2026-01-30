#!/bin/bash

# Export tasks from Markdown to JSON format
# Converts ./.llm/tasks.md to ./.llm/tasks.json following the task-sources contract

TASKS_FILE="${1:-./.llm/tasks.md}"
OUTPUT_FILE="${2:-./.llm/tasks.json}"

# Check if the input file exists
if [ ! -f "$TASKS_FILE" ]; then
    echo "Error: Task file not found: $TASKS_FILE" >&2
    exit 1
fi

# Parse Markdown checklist and convert to JSON
TASKS_JSON='{"tasks":['
TASK_ID=0
FIRST_TASK=true

while IFS= read -r line; do
    # Match checklist items: - [ ] or - [x]
    if [[ $line =~ ^[[:space:]]*-[[:space:]]+\[([[:space:]xX])\][[:space:]]+(.+)$ ]]; then
        TASK_ID=$((TASK_ID + 1))
        CHECKED="${BASH_REMATCH[1]}"
        TITLE="${BASH_REMATCH[2]}"
        
        # Determine status based on checkbox
        if [[ "$CHECKED" == "x" || "$CHECKED" == "X" ]]; then
            STATUS="completed"
            CHECKED_VAL="true"
        else
            STATUS="open"
            CHECKED_VAL="false"
        fi
        
        # Escape special characters in title
        TITLE=$(printf '%s\n' "$TITLE" | sed 's/[\"\\]/\\&/g')
        
        # Add comma before new task (except first)
        if [ "$FIRST_TASK" = false ]; then
            TASKS_JSON="$TASKS_JSON,"
        fi
        FIRST_TASK=false
        
        # Add task object
        TASKS_JSON="$TASKS_JSON{\"id\":\"task-$TASK_ID\",\"title\":\"$TITLE\",\"description\":\"\",\"status\":\"$STATUS\",\"checked\":$CHECKED_VAL}"
    fi
done < "$TASKS_FILE"

TASKS_JSON="$TASKS_JSON]}"

# Write to output file
if ! echo "$TASKS_JSON" > "$OUTPUT_FILE"; then
    echo "Error: Failed to write to $OUTPUT_FILE" >&2
    exit 1
fi

echo "Successfully exported $TASK_ID task(s) to $OUTPUT_FILE"
exit 0
