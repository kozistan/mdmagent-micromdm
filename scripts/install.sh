#!/bin/bash

# MDM Agent Installation Script
# Automated installation and configuration for macOS devices
# Version: 2.0

set -e

# Configuration
PACKAGE_URL="https://your-repo.com/packages/mdmagent_http_installer.pkg"
TEMP_DIR="/tmp/mdmagent_install"
LOG_FILE="/var/log/mdmagent_install.log"

# Default configuration values (override with environment variables)
DEFAULT_SERVER_URL="https://repo.example.com"
DEFAULT_AUTH_USER="repouser"
DEFAULT_AUTH_PASS="your-password"
DEFAULT_MDM_ENDPOINT="https://mdm.example.com/webhook/command-result"
DEFAULT_POLL_INTERVAL=5

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
  --server-url URL      Repository server URL
  --auth-user USER      Authentication username  
  --auth-pass PASS      Authentication password
  --mdm-endpoint URL    Webhook endpoint URL
  --poll-interval SEC   Polling interval in seconds
  --package-url URL     Custom package download URL
  --skip-download       Skip package download (use local)
  --unattended          Run without user interaction
  --help               Show this help message

Environment Variables:
  MDM_SERVER_URL       Repository server URL
  MDM_AUTH_USER        Authentication username
  MDM_AUTH_PASS        Authentication password
  MDM_ENDPOINT         Webhook endpoint URL
  MDM_POLL_INTERVAL    Polling interval in seconds

Examples:
  # Interactive installation
  $0
  
  # Unattended installation with configuration
  $0 --unattended \\
     --server-url "https://repo.company.com" \\
     --auth-user "repouser" \\
     --auth-pass "secretpassword" \\
     --mdm-endpoint "https://mdm.company.com/webhook/command-result"

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --server-url)
                SERVER_URL="$2"
                shift 2
                ;;
            --auth-user)
                AUTH_USER="$2"
                shift 2
                ;;
            --auth-pass)
                AUTH_PASS="$2"
                shift 2
                ;;
            --mdm-endpoint)
                MDM_ENDPOINT="$2"
                shift 2
                ;;
            --poll-interval)
                POLL_INTERVAL="$2"
                shift 2
                ;;
            --package-url)
                PACKAGE_URL="$2"
                shift 2
                ;;
            --skip-download)
                SKIP_DOWNLOAD=true
                shift
                ;;
            --unattended)
                UNATTENDED=true
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
    
    # Check macOS version
    local macos_version=$(sw_vers -productVersion)
    local major_version=$(echo "$macos_version" | cut -d. -f1)
    local minor_version=$(echo "$macos_version" | cut -d. -f2)
    
    if [[ $major_version -lt 10 || ($major_version -eq 10 && $minor_version -lt 14) ]]; then
        log_error "macOS 10.14 or later is required (found: $macos_version)"
        exit 1
    fi
    
    # Check for required commands
    for cmd in curl installer; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Get configuration values
get_configuration() {
    log_info "Configuring installation..."
    
    # Use command line arguments, then environment variables, then defaults
    SERVER_URL="${SERVER_URL:-${MDM_SERVER_URL:-$DEFAULT_SERVER_URL}}"
    AUTH_USER="${AUTH_USER:-${MDM_AUTH_USER:-$DEFAULT_AUTH_USER}}"
    AUTH_PASS="${AUTH_PASS:-${MDM_AUTH_PASS:-$DEFAULT_AUTH_PASS}}"
    MDM_ENDPOINT="${MDM_ENDPOINT:-${MDM_ENDPOINT:-$DEFAULT_MDM_ENDPOINT}}"
    POLL_INTERVAL="${POLL_INTERVAL:-${MDM_POLL_INTERVAL:-$DEFAULT_POLL_INTERVAL}}"
    
    # Interactive configuration if not unattended
    if [[ "$UNATTENDED" != "true" ]]; then
        echo
        echo "=== MDM Agent Configuration ==="
        echo
        
        read -p "Repository Server URL [$SERVER_URL]: " input
        SERVER_URL="${input:-$SERVER_URL}"
        
        read -p "Authentication Username [$AUTH_USER]: " input
        AUTH_USER="${input:-$AUTH_USER}"
        
        read -s -p "Authentication Password: " input
        echo
        if [[ -n "$input" ]]; then
            AUTH_PASS="$input"
        fi
        
        read -p "Webhook Endpoint URL [$MDM_ENDPOINT]: " input
        MDM_ENDPOINT="${input:-$MDM_ENDPOINT}"
        
        read -p "Poll Interval (seconds) [$POLL_INTERVAL]: " input
        POLL_INTERVAL="${input:-$POLL_INTERVAL}"
        
        echo
        echo "Configuration Summary:"
        echo "  Server URL: $SERVER_URL"
        echo "  Auth User: $AUTH_USER"
        echo "  Auth Pass: [HIDDEN]"
        echo "  Webhook: $MDM_ENDPOINT"
        echo "  Poll Interval: $POLL_INTERVAL seconds"
        echo
        
        if [[ "$UNATTENDED" != "true" ]]; then
            read -p "Continue with installation? [y/N]: " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                log_info "Installation cancelled by user"
                exit 0
            fi
        fi
    fi
    
    log_success "Configuration completed"
}

# Download package
download_package() {
    if [[ "$SKIP_DOWNLOAD" == "true" ]]; then
        log_info "Skipping package download"
        return
    fi
    
    log_info "Downloading package from $PACKAGE_URL..."
    
    mkdir -p "$TEMP_DIR"
    local package_file="$TEMP_DIR/mdmagent_http_installer.pkg"
    
    if curl -L -o "$package_file" "$PACKAGE_URL"; then
        log_success "Package downloaded successfully"
        PACKAGE_FILE="$package_file"
    else
        log_error "Failed to download package"
        exit 1
    fi
}

# Install package
install_package() {
    local package_file="${PACKAGE_FILE:-./mdmagent_http_installer.pkg}"
    
    if [[ ! -f "$package_file" ]]; then
        log_error "Package file not found: $package_file"
        exit 1
    fi
    
    log_info "Installing MDM Agent package..."
    
    if installer -pkg "$package_file" -target /; then
        log_success "Package installed successfully"
    else
        log_error "Package installation failed"
        exit 1
    fi
}

# Configure agent
configure_agent() {
    log_info "Configuring MDM Agent..."
    
    local agent_script="/Library/Management/MDMAgent/mdmagent_http.sh"
    
    if [[ ! -f "$agent_script" ]]; then
        log_error "Agent script not found after installation: $agent_script"
        exit 1
    fi
    
    # Apply configuration
    sed -i '' "s|SERVER_URL=\".*\"|SERVER_URL=\"$SERVER_URL\"|g" "$agent_script"
    sed -i '' "s|AUTH_USER=\".*\"|AUTH_USER=\"$AUTH_USER\"|g" "$agent_script"
    sed -i '' "s|AUTH_PASS=\".*\"|AUTH_PASS=\"$AUTH_PASS\"|g" "$agent_script"
    sed -i '' "s|MDM_ENDPOINT=\".*\"|MDM_ENDPOINT=\"$MDM_ENDPOINT\"|g" "$agent_script"
    sed -i '' "s|POLL_INTERVAL=.*|POLL_INTERVAL=$POLL_INTERVAL|g" "$agent_script"
    
    log_success "Agent configured successfully"
}

# Start agent
start_agent() {
    log_info "Starting MDM Agent..."
    
    # Unload if already loaded
    launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist 2>/dev/null || true
    
    # Load LaunchDaemon
    if launchctl load /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist; then
        log_success "MDM Agent started successfully"
    else
        log_warning "Failed to start MDM Agent"
        return 1
    fi
    
    # Wait and check status
    sleep 3
    
    if launchctl list | grep -q com.tolarcompany.mdmagent.http; then
        log_success "MDM Agent is running"
        
        # Show agent logs
        if [[ -f /var/log/mdmagent.log ]]; then
            echo
            echo "Recent agent logs:"
            tail -10 /var/log/mdmagent.log
        fi
    else
        log_warning "MDM Agent may not be running properly"
        return 1
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check files exist
    if [[ ! -f "/Library/Management/MDMAgent/mdmagent_http.sh" ]]; then
        log_error "Agent script not found"
        ((errors++))
    fi
    
    if [[ ! -f "/Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist" ]]; then
        log_error "LaunchDaemon plist not found"
        ((errors++))
    fi
    
    # Check agent is running
    if ! launchctl list | grep -q com.tolarcompany.mdmagent.http; then
        log_error "Agent is not running"
        ((errors++))
    fi
    
    # Check log file
    if [[ ! -f "/var/log/mdmagent.log" ]]; then
        log_warning "Agent log file not found"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Installation verification passed"
        return 0
    else
        log_error "Installation verification failed ($errors errors)"
        return 1
    fi
}

# Cleanup temporary files
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    log_success "Cleanup completed"
}

# Main installation function
main() {
    echo "==============================================="
    echo "MDM Agent for microMDM - Installation Script"
    echo "==============================================="
    echo
    
    parse_arguments "$@"
    check_prerequisites
    get_configuration
    download_package
    install_package
    configure_agent
    start_agent
    
    if verify_installation; then
        echo
        log_success "Installation completed successfully!"
        echo
        echo "Next steps:"
        echo "1. Monitor agent logs: tail -f /var/log/mdmagent.log"
        echo "2. Send test command from MDM server"
        echo "3. Check webhook logs for command results"
        echo
        echo "Configuration:"
        echo "  Agent script: /Library/Management/MDMAgent/mdmagent_http.sh"
        echo "  LaunchDaemon: /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist"
        echo "  Log file: /var/log/mdmagent.log"
        echo
    else
        log_error "Installation completed with errors"
        echo
        echo "Troubleshooting:"
        echo "1. Check installation logs: cat $LOG_FILE"
        echo "2. Check agent logs: cat /var/log/mdmagent.log"
        echo "3. Verify configuration in agent script"
        echo
        exit 1
    fi
    
    cleanup
}

# Handle cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
