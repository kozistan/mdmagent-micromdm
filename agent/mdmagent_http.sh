#!/bin/bash

# Tolar HTTP Polling MDM Agent v2.2 - Secure Version with User Management
# Polls for commands from HTTP endpoint instead of using managed preferences

set -e

# Configuration
SERVER_URL="https://repo.example.com"
DEVICE_UDID=$(system_profiler SPHardwareDataType | grep "Hardware UUID" | awk '{print $3}')
LOG_FILE="/var/log/mdmagent.log"
LOCK_FILE="/tmp/mdmagent.lock"
CONFIG_FILE="/etc/mdm/config"
POLL_INTERVAL=5
MDM_ENDPOINT="https://mdm.example.com/webhook/command-result"

# Load credentials from config file
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        if [ -z "$AUTH_USER" ] || [ -z "$AUTH_PASS" ]; then
            log_message "ERROR: Missing credentials in config file"
            exit 1
        fi
    else
        log_message "ERROR: Config file not found: $CONFIG_FILE"
        exit 1
    fi
}

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

    # Escape JSON characters in output
    escaped_output=$(echo "$output" | python3 -c "
import json
import sys
content = sys.stdin.read()
print(json.dumps(content), end='')
")

    webhook_data=$(cat << EOF
{
    "device_udid": "$DEVICE_UDID",
    "command_type": "$cmd_type",
    "command_value": "$cmd_value",
    "exit_code": $exit_code,
    "output": $escaped_output,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "$([[ $exit_code -eq 0 ]] && echo "success" || echo "failed")"
}
EOF
)
    curl -s -X PUT -H "Content-Type: application/json" -d "$webhook_data" "$MDM_ENDPOINT" >/dev/null 2>&1 || true
}

# Fetch commands from server
fetch_commands() {
    local commands_url="$SERVER_URL/commands/$DEVICE_UDID.json"

    log_message "Agent heartbeat - polling $commands_url"

    local http_code=$(curl -s -u "$AUTH_USER:$AUTH_PASS" -w "%{http_code}" -o /tmp/commands_response.json "$commands_url")

    if [ "$http_code" = "200" ]; then
        if [ -s /tmp/commands_response.json ]; then
            # Check if already processed using MD5 hash
            if command -v md5sum >/dev/null 2>&1; then
                cmd_hash=$(md5sum /tmp/commands_response.json | cut -d' ' -f1)
            else
                cmd_hash=$(md5 /tmp/commands_response.json | cut -d'=' -f2 | tr -d ' ')
            fi
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

                    # Validate hostname format
                    if [[ "$cmd_value" =~ ^[a-zA-Z0-9.-]+$ ]]; then
                        if sudo scutil --set ComputerName "$cmd_value" && sudo scutil --set LocalHostName "$cmd_value" && sudo scutil --set HostName "$cmd_value"; then
                            log_message "Hostname changed successfully"
                            send_mdm_response "$cmd_type" "$cmd_value" "0" "Hostname changed successfully"
                        else
                            log_message "Failed to change hostname"
                            send_mdm_response "$cmd_type" "$cmd_value" "1" "Failed to change hostname"
                        fi
                    else
                        log_message "Invalid hostname format: $cmd_value"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Invalid hostname format"
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
                "createuser")
                    log_message "Executing command: type=$cmd_type, value=$cmd_value, parameter=$cmd_parameter"
                    username="$cmd_value"
                    # Parse parameter: format "admin|password" or "standard|password"
                    IFS='|' read -r user_type password <<< "$cmd_parameter"

                    # Validate username format
                    if [[ ! "$username" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                        log_message "Invalid username format: $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Invalid username format"
                        continue
                    fi

                    # Validate user type
                    if [ "$user_type" != "admin" ] && [ "$user_type" != "standard" ]; then
                        log_message "Invalid user type: $user_type (must be 'admin' or 'standard')"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Invalid user type - use 'admin' or 'standard'"
                        continue
                    fi

                    # Validate password
                    if [ -z "$password" ]; then
                        log_message "Password cannot be empty for user $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Password cannot be empty"
                        continue
                    fi

                    # Check if user already exists
                    if dscl . -read /Users/"$username" >/dev/null 2>&1; then
                        log_message "User $username already exists"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "User already exists"
                        continue
                    fi

                    # Generate unique UID (start from 501 for regular users)
                    next_uid=$(dscl . -list /Users UniqueID | awk '$2 >= 501 {print $2}' | sort -n | tail -1)
                    if [ -z "$next_uid" ]; then
                        new_uid=501
                    else
                        new_uid=$((next_uid + 1))
                    fi

                    log_message "Creating user $username with UID $new_uid as $user_type user"

                    # User creation with working dscl approach
                    creation_output=""
                    if sudo dscl . -create /Users/"$username" && \
                       sudo dscl . -create /Users/"$username" UserShell /bin/bash && \
                       sudo dscl . -create /Users/"$username" RealName "$username" && \
                       sudo dscl . -create /Users/"$username" UniqueID "$new_uid" && \
                       sudo dscl . -create /Users/"$username" PrimaryGroupID 20 && \
                       sudo dscl . -create /Users/"$username" NFSHomeDirectory /Users/"$username" && \
                       sudo createhomedir -c -u "$username" && \
                       sudo dscl . -passwd /Users/"$username" "$password"; then

                        # Add to admin group if specified
                        if [ "$user_type" = "admin" ]; then
                            if sudo dscl . -append /Groups/admin GroupMembership "$username"; then
                                creation_output="User $username created successfully as admin user with UID $new_uid"
                            else
                                creation_output="User $username created but failed to add admin privileges"
                            fi
                        else
                            creation_output="User $username created successfully as standard user with UID $new_uid"
                        fi

                        log_message "$creation_output"
                        send_mdm_response "$cmd_type" "$cmd_value" "0" "$creation_output"
                    else
                        log_message "Failed to create user $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Failed to create user"
                    fi
                    ;;
                "disableuser")
                    log_message "Executing command: type=$cmd_type, value=$cmd_value"
                    username="$cmd_value"

                    # Validate username format
                    if [[ ! "$username" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                        log_message "Invalid username format: $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Invalid username format"
                        continue
                    fi

                    # Check if user exists
                    if ! dscl . -read /Users/"$username" >/dev/null 2>&1; then
                        log_message "User $username does not exist"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "User does not exist"
                        continue
                    fi

                    # Prevent disabling of system users and current user
                    current_user=$(whoami)
                    user_uid=$(dscl . -read /Users/"$username" UniqueID 2>/dev/null | awk '{print $2}')

                    if [ "$username" = "root" ] || [ "$username" = "$current_user" ] || [ "$user_uid" -lt 500 ]; then
                        log_message "Cannot disable system user or current user: $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Cannot disable system user or current user"
                        continue
                    fi

                    log_message "Disabling user $username"

                    # Disable user by setting shell to false and marking as disabled
                    if sudo dscl . -create /Users/"$username" UserShell /usr/bin/false && \
                       sudo dscl . -create /Users/"$username" RealName "$username (DISABLED)"; then
                        log_message "User $username disabled successfully"
                        send_mdm_response "$cmd_type" "$cmd_value" "0" "User $username disabled successfully"
                    else
                        log_message "Failed to disable user $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Failed to disable user"
                    fi
                    ;;
                "enableuser")
                    log_message "Executing command: type=$cmd_type, value=$cmd_value"
                    username="$cmd_value"

                    # Validate username format
                    if [[ ! "$username" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                        log_message "Invalid username format: $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Invalid username format"
                        continue
                    fi

                    # Check if user exists
                    if ! dscl . -read /Users/"$username" >/dev/null 2>&1; then
                        log_message "User $username does not exist"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "User does not exist"
                        continue
                    fi

                    log_message "Enabling user $username"

                    # Enable user by setting shell to bash and removing disabled marker
                    if sudo dscl . -create /Users/"$username" UserShell /bin/bash && \
                       sudo dscl . -create /Users/"$username" RealName "$username"; then
                        log_message "User $username enabled successfully"
                        send_mdm_response "$cmd_type" "$cmd_value" "0" "User $username enabled successfully"
                    else
                        log_message "Failed to enable user $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Failed to enable user"
                    fi
                    ;;
                "setpassword")
                    log_message "Executing command: type=$cmd_type, value=$cmd_value, parameter=$cmd_parameter"
                    username="$cmd_value"
                    password="$cmd_parameter"

                    # Validate username format
                    if [[ ! "$username" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                        log_message "Invalid username format: $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Invalid username format"
                        continue
                    fi

                    # Check if user exists
                    if ! dscl . -read /Users/"$username" >/dev/null 2>&1; then
                        log_message "User $username does not exist"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "User does not exist"
                        continue
                    fi

                    # Validate password (basic check)
                    if [ -z "$password" ]; then
                        log_message "Password cannot be empty for user $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Password cannot be empty"
                        continue
                    fi

                    log_message "Setting password for user $username"

                    # Set password using dscl
                    if sudo dscl . -passwd /Users/"$username" "$password"; then
                        log_message "Password set successfully for user $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "0" "Password set successfully"
                    else
                        log_message "Failed to set password for user $username"
                        send_mdm_response "$cmd_type" "$cmd_value" "1" "Failed to set password"
                    fi
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
    # Load configuration first
    load_config

    log_message "Tolar HTTP Polling MDM Agent v2.2 starting..."
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
