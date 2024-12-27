#!/bin/bash

# Global variables
CR_NUM="CHG000"
BACKUP_DIR="/var/tmp/file_bk"
LOG_FILE="$BACKUP_DIR/file_activity.log"
DATE_FORMAT="%Y-%m-%d %H:%M:%S"

# Usage examples:
#
# 1. Modify file content
# modify_file_content "tcadmin" "/path/to/file.txt" "old text" "new text"
#
# 2. Add file content 
# add_file_content "tcadmin" "/path/to/file.txt" "content to add"       #add at end of file
# add_file_content "tcadmin" "/path/to/file.txt" "content to add" "text to insert after"  #add after specified text
#
# 3. Rollback file changes
# rollback_changes "/path/to/file.txt"                  # Rollback to most recent backup
# rollback_changes "/path/to/file.txt" "/var/tmp/file_bk/test.txt.CHG000_2.bak"      # Rollback to specific version number
#
# Notes:
# - All operations automatically backup files to /var/tmp/file_bk/ directory
# - All operations are logged to /var/tmp/file_bk/file_activity.log
# - Modify and add operations require write permissions on target files
# - Rollback operation uses the most recent backup file



# Function to modify file content
# Parameters:
#   $1: username
#   $2: file path
#   $3: search text
#   $4: replace text
# Returns:
#   0 on success, 1 on failure
function modify_file_content() {
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
    
    # # Switch to specified user
    # if ! su "$USER_NAME" -c "echo 'Running as $USER_NAME'"; then
    #     echo "Error: Cannot switch to user $USER_NAME"
    #     return 1
    # fi

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

    # Get next version number
    local VERSION_NUM="${CR_NUM}_$(get_next_version "$FILE_PATH")"
    
    # Create backup with version number
    [ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR" && chmod 777 "$BACKUP_DIR"
    local BACKUP_FILE="$BACKUP_DIR/$(basename ${FILE_PATH}).${VERSION_NUM}.bak"
    cp "$FILE_PATH" "$BACKUP_FILE" || {
        echo "Error: Failed to create backup"
        return 1
    }

    # Log the modification attempt
    [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
    echo "[$(date "+$DATE_FORMAT")] User:$USER_NAME Modified:$FILE_PATH" >> "$LOG_FILE"

    # Check match count and matching lines
    # Only support single replacement
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
# Parameters:
#   $1: username
#   $2: file path
#   $3: content to add
#   $4: text to insert after (optional)
# Returns:
#   0 on success, 1 on failure
function add_content() {
    local USER_NAME="$1"
    local FILE_PATH="$2" 
    local ADD_CONTENT="$3"
    local BEFORE_TEXT="$4"

    # Check required parameters
    if [ -z "$USER_NAME" ] || [ -z "$FILE_PATH" ] || [ -z "$ADD_CONTENT" ]; then
        echo "Error: Missing required parameters"
        {
            echo "[$(date "+$DATE_FORMAT")] Add content failed: Missing required parameters"
            echo "User: $USER_NAME"
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
    # Get next version number
    local VERSION_NUM="${CR_NUM}_$(get_next_version "$FILE_PATH")"
    
    # Create backup with version number
    [ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR" && chmod 777 "$BACKUP_DIR"
    local BACKUP_FILE="$BACKUP_DIR/$(basename ${FILE_PATH}).${VERSION_NUM}.bak"
    cp "$FILE_PATH" "$BACKUP_FILE" || {
        echo "Error: Failed to create backup"
        return 1
    }

    # Create temporary file for multi-line content
    local TEMP_CONTENT_FILE=$(mktemp)
    echo "$ADD_CONTENT" > "$TEMP_CONTENT_FILE"

    # Add content based on whether BEFORE_TEXT is provided
    if [ -n "$BEFORE_TEXT" ]; then
        # Check if BEFORE_TEXT is provided and unique
        local MATCH_COUNT=$(grep -c "^$BEFORE_TEXT" "$FILE_PATH")
        if [ "$MATCH_COUNT" -gt 1 ]; then
            echo "Error: Multiple matches found ($MATCH_COUNT occurrences) for text: $BEFORE_TEXT"
            echo "Details:"
            echo "----------------------------------------"
            grep -n "^$BEFORE_TEXT" "$FILE_PATH"
            echo "----------------------------------------"
            {
                echo "[$(date "+$DATE_FORMAT")] Error: Multiple matches found ($MATCH_COUNT occurrences)"
                echo "Text: $BEFORE_TEXT"
                echo "File: $FILE_PATH"
                echo "Matching lines:"
                grep -n "^$BEFORE_TEXT" "$FILE_PATH"
                echo "----------------------------------------"
            } >> "$LOG_FILE"
            return 1
        elif [ "$MATCH_COUNT" -eq 0 ]; then
            echo "Error: No match found for text: $BEFORE_TEXT"
            {
                echo "[$(date "+$DATE_FORMAT")] Error: No match found"
                echo "Text: $BEFORE_TEXT"
                echo "File: $FILE_PATH"
            } >> "$LOG_FILE"
            return 1
        fi

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
        echo "User: $USER_NAME"
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

# Rollback changes to a file
# Parameters:
#   $1: file path
#   $2: backup file (optional)
# Returns:
#   0 on success, 1 on failure
function rollback() {
    local FILE_PATH=$1
    local BACKUP_FILE=$2

    # Check if file path is provided
    if [ -z "$FILE_PATH" ]; then
        echo "Error: File path is required"
        return 1
    fi

    # Check if backup file is related to target file
    if [ -n "$BACKUP_FILE" ] && [[ ! "$BACKUP_FILE" =~ "$(basename ${FILE_PATH})" ]]; then
        echo "Error: Backup file ${BACKUP_FILE} is not related to ${FILE_PATH}"
        return 1
    fi

    # If no specific backup file provided, use latest backup
    if [ -z "$BACKUP_FILE" ]; then
        BACKUP_FILE=$(ls -t "${BACKUP_DIR}/$(basename ${FILE_PATH}).${CR_NUM}_"* 2>/dev/null | head -n 1)
        if [ -z "$BACKUP_FILE" ]; then
            echo "Error: No backup file found for ${FILE_PATH}"
            return 1
        fi
    else
        # Verify specified backup file exists
        if [ ! -f "$BACKUP_FILE" ]; then
            echo "Error: Specified backup file does not exist: ${BACKUP_FILE}"
            return 1
        fi
    fi

    # Perform rollback
    if cp "$BACKUP_FILE" "$FILE_PATH"; then
        # Log the rollback operation
        {
            echo "[$(date "+$DATE_FORMAT")] Successfully rolled back file"
            echo "File: $FILE_PATH"
            echo "Restored from backup: $BACKUP_FILE"
            echo "----------------------------------------"
        } >> "$LOG_FILE"
        echo "Successfully rolled back to: $BACKUP_FILE"
        return 0
    else
        # Log rollback failure
        {
            echo "[$(date "+$DATE_FORMAT")] Error: Failed to rollback file"
            echo "File: $FILE_PATH"
            echo "Backup file: $BACKUP_FILE"
            echo "----------------------------------------"
        } >> "$LOG_FILE"
        echo "Error: Failed to rollback file"
        return 1
    fi
}

# Get next version number
# Parameters:
#   $1: file path
# Returns:
#   Next version number as string
function get_next_version() {
    local FILE_PATH=$1
    local LAST_VERSION=$(ls -t "${BACKUP_DIR}/$(basename ${FILE_PATH}).${CR_NUM}_"* 2>/dev/null | head -n 1 | grep -o "${CR_NUM}_[0-9]*" | cut -d'_' -f2)
    
    if [ -z "$LAST_VERSION" ]; then
        echo "1"
    else
        echo "$((LAST_VERSION + 1))"
    fi
}


# Main execution
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
    su - tcadmin -c "$(which bash) -c 'modify_file_content \"tcadmin\" \"/var/a.txt\" \"1111\" \"benben\"'"
}

# Execute main function
main
