#!/bin/bash

# Tolar HTTP Polling MDM Agent v2.0
# Polls for commands from HTTP endpoint instead of using managed preferences

set -e

# Configuration
SERVER_URL="https://repo.example.com"
DEVICE_UDID=$(system_profiler SPHardwareDataType | grep "Hardware UUID" | awk '{print $3}')
LOG_FILE="/var/log/mdmagent.log"
LOCK_FILE="/tmp/mdmagent.lock"
AUTH_USER="repouser"
AUTH_PASS="your-password"
POLL_INTERVAL=5
MDM_ENDPOINT="https://mdm.example.com/webhook/command-result"

# Logging function
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# Send webhook after command execution
send_mdm_response() {
    local cmd_type="$1"
    local cmd_value="$2" 
    local exit_code="$3"
    local output="$4"
    
    webhook_data=$(cat << EOF
{
    "device_udid": "$DEVICE_UDID",
    "command_type": "$cmd_type", 
    "command_value": "$cmd_value",
    "exit_code": $exit_code,
    "output": "$output",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "$([[ $exit_code -eq 0 ]] && echo "success" || echo "failed")"
}
EOF
)
    
    curl -s -X PUT -H "Content-Type: application/json" -d "$webhook_data" "$MDM_ENDPOINT" >/dev/null 2>&1 || true
}

# Test connectivity to server
test_connectivity() {
    local test_url="$SERVER_URL/munki/"
    if curl -s -f -u "$AUTH_USER:$AUTH_PASS" -w "%{http_code}" -o /dev/null "$test_url" >/dev/null 2>&1; then
        log_message "Connectivity test: SUCCESS"
        return 0
    else
        log_message "Connectivity test: FAILED (continuing anyway)"
        return 1
    fi
}

# Fetch commands from server
fetch_commands() {
    local commands_url="$SERVER_URL/commands/$DEVICE_UDID.json"
    
    log_message "Agent heartbeat - polling $commands_url"
    
    local http_code=$(curl -s -u "$AUTH_USER:$AUTH_PASS" -w "%{http_code}" -o /tmp/commands_response.json "$commands_url")
    
    if [ "$http_code" = "200" ]; then
        if [ -s /tmp/commands_response.json ]; then
            # Check if already processed using MD5 hash
            cmd_hash=$(md5 /tmp/commands_response.json | cut -d'=' -f2 | tr -d ' ')
            processed_marker="/tmp/processed_$cmd_hash"
            
            if [ ! -f "$processed_marker" ]; then
                log_message "Processing new commands (hash: $cmd_hash)"
                
                # Execute commands directly here
                commands_data=$(cat /tmp/commands_response.json)
                execute_commands "$commands_data"
                
                log_message "Commands processed successfully"
                touch "$processed_marker"
            else
                log_message "Commands already processed (hash: $cmd_hash), skipping"
            fi
            rm -f /tmp/commands_response.json
        fi
    elif [ "$http_code" = "404" ]; then
        # No commands available - normal
        rm -f /tmp/commands_response.json
        return 1
    else
        log_message "HTTP error fetching commands: $http_code"
        rm -f /tmp/commands_response.json
        return 1
    fi
}

# Process commands from server
process_commands() {
    local commands_output="$1"
    
    if [ -z "$commands_output" ]; then
        return 1
    fi
    
    log_message "Processing commands from server"
    
    # Parse JSON and extract commands using Python
    /usr/bin/python3 << PYTHON_SCRIPT
import json
import sys

try:
    data = json.loads('''$commands_output''')
    commands = data.get('commands', [])
    
    for cmd in commands:
        cmd_type = cmd.get('type', '')
        cmd_value = cmd.get('value', '')
        cmd_parameter = cmd.get('parameter', '')
        
        if cmd_type and isinstance(cmd_type, str) and not cmd_type.startswith('['):
            print(f"{cmd_type}|{cmd_value}|{cmd_parameter}")
            
except json.JSONDecodeError as e:
    print(f"JSON_ERROR|{e}|", file=sys.stderr)
except Exception as e:
    print(f"PARSING_ERROR|{e}|", file=sys.stderr)
PYTHON_SCRIPT
}

# Execute commands
execute_commands() {
    local commands_output=$(process_commands "$1")
    
    if [ -z "$commands_output" ]; then
        return 1
    fi
    
    echo "$commands_output" | while IFS='|' read -r cmd_type cmd_value cmd_parameter; do
        if [ -n "$cmd_type" ] && [ "$cmd_type" != "JSON_ERROR" ] && [ "$cmd_type" != "PARSING_ERROR" ]; then
            case "$cmd_type" in
                "test")
                    log_message "Executing command: type=$cmd_type, value=$cmd_value"
                    log_message "Test command executed: $cmd_value"
                    echo "Test executed at $(date): $cmd_value" > /tmp/mdm_test_result.txt
                    log_message "Test result written to /tmp/mdm_test_result.txt"
                    send_mdm_response "$cmd_type" "$cmd_value" "0" "Test executed successfully"
                    ;;
                "hostname")
                    log_message "Executing command: type=$cmd_type, value=$cmd_value"
                    log_message "Changing hostname to: $cmd_value"
                    if sudo scutil --set ComputerName "$cmd_value" && sudo scutil --set LocalHostName "$cmd_value" && sudo scutil --set HostName "$cmd_value"; then
                        log_message "Hostname changed successfully"
                        send_mdm_response "$cmd_type" "$cmd_value" "0" "Hostname changed successfully"
                    else
                        log_message "Failed to change hostname"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Failed to change hostname"
                    fi
                    ;;
                "shell")
                    log_message "Executing command: type=$cmd_type, value=$cmd_value"
                    log_message "Executing shell command: $cmd_value"
                    if [ -n "$cmd_parameter" ]; then
                        log_message "Shell command parameter: $cmd_parameter"
                    fi
                    
                    shell_output=$(eval "$cmd_value" 2>&1)
                    shell_exit_code=$?
                    
                    log_message "Shell command output: $shell_output"
                    log_message "Shell command exit code: $shell_exit_code"
                    
                    echo "Command: $cmd_value" > /tmp/mdm_shell_result.txt
                    echo "Exit Code: $shell_exit_code" >> /tmp/mdm_shell_result.txt
                    echo "Output:" >> /tmp/mdm_shell_result.txt
                    echo "$shell_output" >> /tmp/mdm_shell_result.txt
                    echo "Executed at: $(date)" >> /tmp/mdm_shell_result.txt
                    
                    send_mdm_response "$cmd_type" "$cmd_value" "$shell_exit_code" "$shell_output"
                    ;;
                *)
                    log_message "Unknown command type: $cmd_type"
                    send_mdm_response "$cmd_type" "$cmd_value" "1" "Unknown command type"
                    ;;
            esac
        fi
    done
}

# Cleanup function
cleanup() {
    log_message "Received shutdown signal, cleaning up..."
    rm -f "$LOCK_FILE"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main function
main() {
    log_message "Tolar HTTP Polling MDM Agent v2.0 starting..."
    log_message "PID: $$"
    log_message "Device UDID: $DEVICE_UDID"
    log_message "Server URL: $SERVER_URL"
    
    # Create lock file
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log_message "Another instance is already running with PID $lock_pid"
            exit 1
        else
            log_message "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    
    log_message "MDM Agent started successfully"
    
    # Initial connectivity test
    if test_connectivity; then
        log_message "Connectivity test: SUCCESS"
    else
        log_message "Connectivity test: FAILED (continuing anyway)"
    fi
    
    # Main polling loop
    while true; do
        if ! fetch_commands; then
            # No commands or error - continue polling
            true
        fi
        
        sleep "$POLL_INTERVAL"
    done
}

# Run main function
main "$@"
