#!/bin/bash

# Hardcoded configuration for reliability
CONFIG_FILE="/opt/raptor/config.conf"
HOSTNAME_FILE="/opt/raptor/hostname"
LOG_FILE="/var/log/raptor.log"
BASE_URL="https://amirvali.ir/raptor"
INTERVAL=60

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Use config values or defaults
LOG_FILE="${LOG_FILE:-/var/log/raptor.log}"
INTERVAL="${EXECUTION_INTERVAL:-60}"
BASE_URL="${BASE_URL:-https://amirvali.ir/raptor}"

# Get host identifier
get_hostname() {
    if [[ -f "$HOSTNAME_FILE" ]] && [[ -s "$HOSTNAME_FILE" ]]; then
        cat "$HOSTNAME_FILE" | tr -d '\n'
    else
        echo "unknown-host"
    fi
}

# Log function
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $message" >> "$LOG_FILE"
}

# Download file from server
download_file() {
    local url="$1"
    local output="$2"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s -f --connect-timeout 30 "$url" -o "$output" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=30 "$url" -O "$output" 2>/dev/null
    else
        return 1
    fi
}

# Fetch commands from server
fetch_commands_from_server() {
    local hostname=$(get_hostname)
    local updated=0
    
    log_message "DEBUG: Current host identifier: '$hostname'"
    
    # Fetch global commands
    if download_file "$BASE_URL/commands.txt" "/opt/raptor/commands.txt"; then
        log_message "Global commands updated"
        updated=1
    else
        log_message "DEBUG: Failed to download global commands"
    fi
    
    # Fetch host-specific commands
    local host_url="$BASE_URL/hosts/$hostname.txt"
    log_message "DEBUG: Trying to download host commands from: $host_url"
    
    if download_file "$host_url" "/opt/raptor/host_commands.txt"; then
        log_message "Host-specific commands updated for: $hostname"
        updated=1
    else
        log_message "DEBUG: No host-specific commands found at: $host_url"
        rm -f "/opt/raptor/host_commands.txt"
    fi
    
    return $updated
}

# Execute commands from file
execute_commands_from_file() {
    local file="$1"
    local context="$2"
    
    if [[ ! -f "$file" ]]; then
        log_message "DEBUG: File not found: $file"
        return 1
    fi
    
    local line_num=0
    local executed_commands=0
    
    while IFS= read -r command; do
        ((line_num++))
        
        # Skip empty lines and comments
        if [[ -z "$command" || "$command" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        command=$(echo "$command" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [[ -z "$command" ]]; then
            continue
        fi
        
        log_message "Executing $context command line $line_num: $command"
        ((executed_commands++))
        
        {
            echo "=== $context command execution start ==="
            eval "$command"
            local exit_code=$?
            echo "=== $context command execution end (exit code: $exit_code) ==="
        } >> "$LOG_FILE" 2>&1
        
        if [[ $exit_code -eq 0 ]]; then
            log_message "$context command line $line_num executed successfully"
        else
            log_message "$context command line $line_num failed (exit code: $exit_code)"
        fi
        
    done < "$file"
    
    if [[ $executed_commands -eq 0 ]]; then
        log_message "No valid $context commands found"
    else
        log_message "$executed_commands $context commands executed"
    fi
}

# Execute all commands
execute_commands() {
    local hostname=$(get_hostname)
    
    log_message "DEBUG: Executing commands for host: $hostname"
    
    # Execute global commands first
    if [[ -f "/opt/raptor/commands.txt" ]]; then
        execute_commands_from_file "/opt/raptor/commands.txt" "global"
    else
        log_message "DEBUG: Global commands file not found"
    fi
    
    # Execute host-specific commands
    if [[ -f "/opt/raptor/host_commands.txt" ]]; then
        execute_commands_from_file "/opt/raptor/host_commands.txt" "host-$hostname"
    else
        log_message "DEBUG: Host commands file not found"
    fi
}

# Main loop
main() {
    local hostname=$(get_hostname)
    log_message "Raptor service started for host: $hostname"
    log_message "Execution interval: $INTERVAL seconds"
    
    while true; do
        log_message "Checking for command updates..."
        
        fetch_commands_from_server
        execute_commands
        
        log_message "Waiting $INTERVAL seconds for next execution..."
        sleep "$INTERVAL"
    done
}

# Signal handling
cleanup() {
    log_message "Raptor service stopped"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start main function
main