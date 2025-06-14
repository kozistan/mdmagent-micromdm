#!/bin/bash

# MDM Agent Uninstallation Script
# Complete removal of MDM Agent for microMDM
# Version: 2.0

set -e

# Configuration
LOG_FILE="/var/log/mdmagent_uninstall.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_message "INFO: $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_message "SUCCESS: $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING: $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_message "ERROR: $1"
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --force              Force removal without confirmation
  --keep-logs          Keep log files after uninstallation
  --dry-run            Show what would be removed without actually removing
  --help               Show this help message

Examples:
  # Interactive uninstallation
  $0
  
  # Force uninstallation without prompts
  $0 --force
  
  # Dry run to see what would be removed
  $0 --dry-run

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --keep-logs)
                KEEP_LOGS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Confirm uninstallation
confirm_uninstallation() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    echo "=== MDM Agent Uninstallation ==="
    echo
    echo "This will completely remove the MDM Agent from this system:"
    echo "  • Stop all agent processes"
    echo "  • Remove LaunchDaemon services"
    echo "  • Delete agent files and directories"
    echo "  • Remove configuration files"
    if [[ "$KEEP_LOGS" != "true" ]]; then
        echo "  • Delete log files"
    fi
    echo "  • Clean up temporary files"
    echo
    
    read -p "Are you sure you want to continue? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Uninstallation cancelled by user"
        exit 0
    fi
    
    echo
}

# Execute command (with dry-run support)
execute_command() {
    local description="$1"
    local command="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $description"
        echo "  Command: $command"
    else
        log_info "$description"
        if eval "$command"; then
            log_success "$description completed"
        else
            log_warning "$description failed (continuing)"
        fi
    fi
}

# Stop agent services
stop_services() {
    log_info "Stopping MDM Agent services..."
    
    # Stop and unload LaunchDaemon services
    execute_command "Stopping HTTP agent service" \
        "launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist 2>/dev/null || true"
    
    execute_command "Stopping legacy agent service" \
        "launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.plist 2>/dev/null || true"
    
    # Wait for services to stop
    if [[ "$DRY_RUN" != "true" ]]; then
        sleep 2
    fi
    
    # Force kill any remaining processes
    execute_command "Terminating agent processes" \
        "pkill -f mdmagent 2>/dev/null || true"
    
    execute_command "Force killing agent processes" \
        "pkill -9 -f mdmagent 2>/dev/null || true"
}

# Remove LaunchDaemon files
remove_launchdaemons() {
    log_info "Removing LaunchDaemon files..."
    
    local launchdaemons=(
        "/Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist"
        "/Library/LaunchDaemons/com.tolarcompany.mdmagent.plist"
    )
    
    for plist in "${launchdaemons[@]}"; do
        if [[ -f "$plist" ]] || [[ "$DRY_RUN" == "true" ]]; then
            execute_command "Removing $(basename "$plist")" \
                "rm -f '$plist'"
        fi
    done
}

# Remove agent files and directories
remove_agent_files() {
    log_info "Removing agent files and directories..."
    
    local directories=(
        "/Library/Management/MDMAgent"
        "/Library/Application Support/MDMAgent"
    )
    
    local files=(
        "/Library/Managed Preferences/com.tolarcompany.mdmagent.plist"
        "/usr/local/bin/mdmagent"
    )
    
    # Remove directories
    for dir in "${directories[@]}"; do
        if [[ -d "$dir" ]] || [[ "$DRY_RUN" == "true" ]]; then
            execute_command "Removing directory $dir" \
                "rm -rf '$dir'"
        fi
    done
    
    # Remove individual files
    for file in "${files[@]}"; do
        if [[ -f "$file" ]] || [[ "$DRY_RUN" == "true" ]]; then
            execute_command "Removing file $file" \
                "rm -f '$file'"
        fi
    done
}

# Remove log files
remove_logs() {
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log_info "Keeping log files as requested"
        return 0
    fi
    
    log_info "Removing log files..."
    
    local log_files=(
        "/var/log/mdmagent.log"
        "/var/log/mdmagent_install.log"
        "/var/log/mdmagent_uninstall.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]] || [[ "$DRY_RUN" == "true" ]]; then
            execute_command "Removing log file $log_file" \
                "rm -f '$log_file'"
        fi
    done
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    local temp_patterns=(
        "/tmp/mdmagent*"
        "/tmp/commands_response.json"
        "/tmp/mdm_*_result.txt"
        "/tmp/processed_*"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        execute_command "Removing temporary files: $pattern" \
            "rm -f $pattern 2>/dev/null || true"
    done
}

# Remove from system package database
remove_package_receipts() {
    log_info "Removing package receipts..."
    
    local package_ids=(
        "com.tolarcompany.mdmagent.http"
        "com.tolarcompany.mdmagent"
    )
    
    for package_id in "${package_ids[@]}"; do
        if pkgutil --pkgs | grep -q "$package_id" 2>/dev/null || [[ "$DRY_RUN" == "true" ]]; then
            execute_command "Removing package receipt: $package_id" \
                "pkgutil --forget '$package_id' 2>/dev/null || true"
        fi
    done
}

# Verify removal
verify_removal() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed - no actual changes made"
        return 0
    fi
    
    log_info "Verifying removal..."
    
    local remaining_items=0
    
    # Check for running processes
    if pgrep -f mdmagent >/dev/null 2>&1; then
        log_warning "MDM Agent processes are still running"
        ((remaining_items++))
    fi
    
    # Check for LaunchDaemon services
    if launchctl list | grep -q com.tolarcompany.mdmagent 2>/dev/null; then
        log_warning "MDM Agent services are still loaded"
        ((remaining_items++))
    fi
    
    # Check for agent files
    if [[ -d "/Library/Management/MDMAgent" ]]; then
        log_warning "Agent directory still exists"
        ((remaining_items++))
    fi
    
    # Check for LaunchDaemon files
    if [[ -f "/Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist" ]]; then
        log_warning "LaunchDaemon plist still exists"
        ((remaining_items++))
    fi
    
    if [[ $remaining_items -eq 0 ]]; then
        log_success "Removal verification passed - MDM Agent completely removed"
        return 0
    else
        log_warning "Removal verification found $remaining_items remaining items"
        echo
        echo "Manual cleanup may be required for:"
        echo "  • Any remaining processes: pkill -f mdmagent"
        echo "  • LaunchDaemon services: launchctl list | grep mdmagent"
        echo "  • Remaining files in /Library/Management/MDMAgent"
        echo
        return 1
    fi
}

# Display summary
show_summary() {
    echo
    echo "==============================================="
    echo "MDM Agent Uninstallation Summary"
    echo "==============================================="
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "This was a dry run - no changes were made to your system."
        echo "Run without --dry-run to perform actual removal."
    else
        echo "MDM Agent has been removed from this system."
        echo
        echo "What was removed:"
        echo "  ✓ Agent processes and services"
        echo "  ✓ LaunchDaemon configuration files"
        echo "  ✓ Agent scripts and directories"
        echo "  ✓ Configuration files"
        if [[ "$KEEP_LOGS" != "true" ]]; then
            echo "  ✓ Log files"
        else
            echo "  - Log files (kept as requested)"
        fi
        echo "  ✓ Temporary files"
        echo "  ✓ Package receipts"
        echo
        echo "The system is now clean of MDM Agent components."
    fi
    
    echo
    
    if [[ "$KEEP_LOGS" == "true" && "$DRY_RUN" != "true" ]]; then
        echo "Note: Installation and operation logs have been preserved:"
        echo "  • /var/log/mdmagent.log (if it existed)"
        echo "  • /var/log/mdmagent_install.log (if it existed)"
        echo "  • /var/log/mdmagent_uninstall.log"
        echo
    fi
}

# Main uninstallation function
main() {
    echo "==============================================="
    echo "MDM Agent for microMDM - Uninstallation Script"
    echo "==============================================="
    echo
    
    parse_arguments "$@"
    check_prerequisites
    confirm_uninstallation
    
    stop_services
    remove_launchdaemons
    remove_agent_files
    remove_logs
    cleanup_temp_files
    remove_package_receipts
    
    verify_removal
    show_summary
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_success "Uninstallation completed successfully!"
    fi
}

# Run main function
main "$@"
