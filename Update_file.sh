#!/bin/bash

# Global variables
BACKUP_DIR="/var/tmp/file_bk"
LOG_FILE="$BACKUP_DIR/file_activity.log"
TIMESTAMP_FORMAT="%Y%m%d_%H%M%S"
DATE_FORMAT="%Y-%m-%d %H:%M:%S"


# Usage examples:
#
# 1. Modify file content
# modify_file_content "root" "/path/to/file.txt" "old text" "new text"
#
# 2. Add content to file
# add_file_content "root" "/path/to/file.txt" "content to add" "text to insert after"
#
# 3. Rollback file changes
# rollback_changes "/path/to/file.txt"
#
# Notes:
# - All operations automatically backup files to /var/tmp/file_bk/ directory
# - All operations are logged to /var/tmp/file_bk/file_activity.log
# - Modify and add operations require write permissions on target files
# - Rollback operation uses the most recent backup file



# Execute command using su -c
if ! su - "$USER_NAME" -c "$(declare -f modify_file_content); modify_file_content '$USER_NAME' '$FILE_PATH' '$SEARCH_TEXT' '$REPLACE_TEXT'"; then
    echo "Error: Failed to execute command as user $USER_NAME"
    return 1
fi



# Function to modify file content
# Parameters:
#   $1: username
#   $2: file path
#   $3: search text
#   $4: replace text
# Returns:
#   0 on success, 1 on failure
modify_file_content() {
    local USER_NAME=$1
    local FILE_PATH=$2
    local SEARCH_TEXT=$3
    local REPLACE_TEXT=$4

    # Check current user permissions
    local CURRENT_USER=$(whoami)
    if [ "$CURRENT_USER" != "$USER_NAME" ]; then
        echo "Error: This command can only be run as user $USER_NAME"
        return 1
    fi

    # Validate parameters
    if [ -z "$USER_NAME" ] || [ -z "$FILE_PATH" ] || [ -z "$SEARCH_TEXT" ] || [ -z "$REPLACE_TEXT" ]; then
        echo "Error: Missing required parameters"
        return 1
    fi
    # Switch to specified user
    if ! su "$USER_NAME" -c "echo 'Running as $USER_NAME'"; then
        echo "Error: Cannot switch to user $USER_NAME"
        return 1
    fi

    # Check if file exists
    if [ ! -f "$FILE_PATH" ]; then
        echo "Error: File $FILE_PATH does not exist"
        return 1
    fi

    # Check file permissions
    if [ ! -w "$FILE_PATH" ]; then
        echo "Error: No write permission for file $FILE_PATH"
        return 1
    fi

    # Create backup with timestamp under
    [ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR"
    local BACKUP_FILE="$BACKUP_DIR/$(basename ${FILE_PATH}).bak.$(date +$TIMESTAMP_FORMAT)"
    cp "$FILE_PATH" "$BACKUP_FILE" || {
        echo "Error: Failed to create backup"
        return 1
    }

    # Log the modification attempt
    [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
    echo "[$(date "+$DATE_FORMAT")] User:$USER_NAME Modified:$FILE_PATH" >> "$LOG_FILE"

    # Check match count and matching lines
    local MATCH_COUNT=$(grep -c "$SEARCH_TEXT" "$FILE_PATH")
    if [ "$MATCH_COUNT" -gt 1 ]; then
        echo "Error: Multiple matches found ($MATCH_COUNT occurrences). Details:"
        echo "----------------------------------------"
        while IFS= read -r line; do
            line_num=$(echo "$line" | cut -d: -f1)
            content=$(echo "$line" | cut -d: -f2-)
            echo "Line $line_num: $content"
        done < <(grep -n "$SEARCH_TEXT" "$FILE_PATH")
        echo "----------------------------------------"
        {
            echo "[$(date "+$DATE_FORMAT")] Error: Multiple matches found ($MATCH_COUNT occurrences)"
            echo "Matching lines details:"
            while IFS= read -r line; do
                line_num=$(echo "$line" | cut -d: -f1)
                content=$(echo "$line" | cut -d: -f2-)
                echo "Line $line_num: $content"
            done < <(grep -n "$SEARCH_TEXT" "$FILE_PATH")
            echo "----------------------------------------"
        } >> "$LOG_FILE"
        return 1
    elif [ "$MATCH_COUNT" -eq 0 ]; then
        echo "Warning: No matches found for keyword '$SEARCH_TEXT' in file $FILE_PATH"
        echo "[$(date "+$DATE_FORMAT")] Warning: No matches found for keyword '$SEARCH_TEXT' in file $FILE_PATH" >> "$LOG_FILE"
        return 0
    fi

    # Display content to be modified
    echo "Found following match:"
    grep -n "$SEARCH_TEXT" "$FILE_PATH"
    {
        echo "[$(date "+$DATE_FORMAT")] Found match:"
        grep -n "$SEARCH_TEXT" "$FILE_PATH"
    } >> "$LOG_FILE"

    # Perform replacement
    if sed -i.tmp "s/$SEARCH_TEXT/$REPLACE_TEXT/g" "$FILE_PATH"; then
        # Check if any changes were made
        if diff "$FILE_PATH" "$FILE_PATH.tmp" > /dev/null; then
            echo "Warning: No matching content found, file unchanged"
            rm "$FILE_PATH.tmp"
            return 0
        else
            # Show changes
            echo "Modification successful! Details:"
            echo "----------------------------------------"
            diff "$BACKUP_FILE" "$FILE_PATH"
            echo "----------------------------------------"
            
            # Log the changes
            {
                echo "Original text: $SEARCH_TEXT"
                echo "New text: $REPLACE_TEXT"
                echo "----------------------------------------"
            } >> "$LOG_FILE"
            
            # Cleanup
            rm "$FILE_PATH.tmp"
            echo "Backup saved as: $BACKUP_FILE"
            return 0
        fi
    else
        echo "Error: Modification failed"
        # Rollback
        cp "$BACKUP_FILE" "$FILE_PATH"
        rm -f "$FILE_PATH.tmp"
        return 1
    fi
} 

# Add content to file
add_content() {
    local ACCOUNT="$1"
    local FILE_PATH="$2" 
    local ADD_CONTENT="$3"
    local BEFORE_TEXT="$4"

    # Check required parameters
    if [ -z "$ACCOUNT" ] || [ -z "$FILE_PATH" ] || [ -z "$ADD_CONTENT" ]; then
        echo "Error: Missing required parameters"
        {
            echo "[$(date "+$DATE_FORMAT")] Add content failed: Missing required parameters"
            echo "Account: $ACCOUNT"
            echo "File: $FILE_PATH"
        } >> "$LOG_FILE"
        return 1
    fi

    # Check if file exists
    if [ ! -f "$FILE_PATH" ]; then
        echo "Error: File $FILE_PATH does not exist"
        {
            echo "[$(date "+$DATE_FORMAT")] Add content failed: File does not exist"
            echo "File: $FILE_PATH"
        } >> "$LOG_FILE"
        return 1
    fi

    # Create backup
    local BACKUP_FILE="${FILE_PATH}.$(date +$TIMESTAMP_FORMAT).bak"
    cp "$FILE_PATH" "$BACKUP_FILE"

    # Create temporary file for multi-line content
    local TEMP_CONTENT_FILE=$(mktemp)
    echo "$ADD_CONTENT" > "$TEMP_CONTENT_FILE"

    # Add content based on whether BEFORE_TEXT is provided
    if [ -n "$BEFORE_TEXT" ]; then
        # Add multi-line content after specified text
        if sed -i.tmp "/^$BEFORE_TEXT/r $TEMP_CONTENT_FILE" "$FILE_PATH"; then
            echo "Successfully added content at specified position"
        else
            echo "Error: Failed to add content at specified position"
            cp "$BACKUP_FILE" "$FILE_PATH"
            rm -f "$FILE_PATH.tmp" "$TEMP_CONTENT_FILE"
            return 1
        fi
    else
        # Add multi-line content at end of file
        if cat "$TEMP_CONTENT_FILE" >> "$FILE_PATH"; then
            echo "Successfully added content at end of file"
        else
            echo "Error: Failed to add content"
            cp "$BACKUP_FILE" "$FILE_PATH"
            rm -f "$TEMP_CONTENT_FILE"
            return 1
        fi
    fi

    # Log the changes
    {
        echo "[$(date "+$DATE_FORMAT")] Successfully added content"
        echo "Account: $ACCOUNT"
        echo "File: $FILE_PATH"
        echo "Added content:"
        echo "----------------------------------------"
        cat "$TEMP_CONTENT_FILE"
        echo "----------------------------------------"
        [ -n "$BEFORE_TEXT" ] && echo "Inserted after: $BEFORE_TEXT"
        echo "Backup file: $BACKUP_FILE"
        echo "----------------------------------------"
    } >> "$LOG_FILE"

    # Cleanup
    rm -f "$FILE_PATH.tmp" "$TEMP_CONTENT_FILE"
    echo "Backup saved as: $BACKUP_FILE"
    return 0
}

# Rollback function to revert changes
rollback_changes() {
    local FILE_PATH="$1"
    
    # Find the latest backup file
    local LATEST_BACKUP=$(ls -t "${FILE_PATH}".*.bak 2>/dev/null | head -n 1)
    
    if [ -z "$LATEST_BACKUP" ]; then
        echo "Error: No backup file found"
        {
            echo "[$(date "+$DATE_FORMAT")] Rollback failed: No backup file found for $FILE_PATH"
        } >> "$LOG_FILE"
        return 1
    fi

    # Perform rollback
    if cp "$LATEST_BACKUP" "$FILE_PATH"; then
        echo "Successfully rolled back to backup version"
        echo "Used backup file: $LATEST_BACKUP"
        {
            echo "[$(date "+$DATE_FORMAT")] Successfully rolled back $FILE_PATH"
            echo "Used backup file: $LATEST_BACKUP"
            echo "----------------------------------------"
        } >> "$LOG_FILE"
        return 0
    else
        echo "Error: Rollback failed"
        {
            echo "[$(date "+$DATE_FORMAT")] Rollback failed for $FILE_PATH"
            echo "Attempted to use backup file: $LATEST_BACKUP"
            echo "----------------------------------------"
        } >> "$LOG_FILE"
        return 1
    fi
}
