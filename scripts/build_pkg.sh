#!/bin/bash

# MDM Agent PKG Builder
# Creates signed installer package for distribution

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_NAME="mdmagent_http_installer"
PACKAGE_VERSION="2.0"
PACKAGE_ID="com.tolarcompany.mdmagent.http"
PAYLOAD_DIR="$SCRIPT_DIR/payload"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
OUTPUT_DIR="$SCRIPT_DIR/output"
TEMP_DIR="$SCRIPT_DIR/temp"

# Signing configuration (edit these for your environment)
DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAM_ID)"
KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking build prerequisites..."
    
    # Check for required tools
    for tool in pkgbuild productbuild; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed"
            exit 1
        fi
    done
    
    # Check for source files
    if [ ! -f "$PROJECT_ROOT/src/mdmagent_http.sh" ]; then
        log_error "Source agent script not found: $PROJECT_ROOT/src/mdmagent_http.sh"
        exit 1
    fi
    
    if [ ! -f "$PROJECT_ROOT/src/config/com.tolarcompany.mdmagent.http.plist" ]; then
        log_error "LaunchDaemon plist not found: $PROJECT_ROOT/src/config/com.tolarcompany.mdmagent.http.plist"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Prepare payload directory
prepare_payload() {
    log_info "Preparing package payload..."
    
    # Clean and create payload directory structure
    rm -rf "$PAYLOAD_DIR"
    mkdir -p "$PAYLOAD_DIR/Library/Management/MDMAgent"
    mkdir -p "$PAYLOAD_DIR/Library/LaunchDaemons"
    
    # Copy agent script
    cp "$PROJECT_ROOT/src/mdmagent_http.sh" "$PAYLOAD_DIR/Library/Management/MDMAgent/"
    chmod +x "$PAYLOAD_DIR/Library/Management/MDMAgent/mdmagent_http.sh"
    
    # Copy LaunchDaemon plist
    cp "$PROJECT_ROOT/src/config/com.tolarcompany.mdmagent.http.plist" "$PAYLOAD_DIR/Library/LaunchDaemons/"
    chmod 644 "$PAYLOAD_DIR/Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist"
    
    # Create configuration template
    cat > "$PAYLOAD_DIR/Library/Management/MDMAgent/config_template.sh" << 'EOF'
#!/bin/bash
# MDM Agent Configuration Template
# Copy this file to mdmagent_config.sh and customize for your environment

# Server configuration
SERVER_URL="https://repo.example.com"
AUTH_USER="repouser"
AUTH_PASS="your-password"

# Webhook configuration
MDM_ENDPOINT="https://mdm.example.com/webhook/command-result"

# Polling configuration
POLL_INTERVAL=5

# Apply configuration to agent script
sed -i '' "s|SERVER_URL=\".*\"|SERVER_URL=\"$SERVER_URL\"|g" /Library/Management/MDMAgent/mdmagent_http.sh
sed -i '' "s|AUTH_USER=\".*\"|AUTH_USER=\"$AUTH_USER\"|g" /Library/Management/MDMAgent/mdmagent_http.sh
sed -i '' "s|AUTH_PASS=\".*\"|AUTH_PASS=\"$AUTH_PASS\"|g" /Library/Management/MDMAgent/mdmagent_http.sh
sed -i '' "s|MDM_ENDPOINT=\".*\"|MDM_ENDPOINT=\"$MDM_ENDPOINT\"|g" /Library/Management/MDMAgent/mdmagent_http.sh
sed -i '' "s|POLL_INTERVAL=.*|POLL_INTERVAL=$POLL_INTERVAL|g" /Library/Management/MDMAgent/mdmagent_http.sh
EOF
    chmod +x "$PAYLOAD_DIR/Library/Management/MDMAgent/config_template.sh"
    
    log_success "Payload prepared"
}

# Prepare install scripts
prepare_scripts() {
    log_info "Preparing install scripts..."
    
    mkdir -p "$SCRIPTS_DIR"
    
    # Create postinstall script
    cat > "$SCRIPTS_DIR/postinstall" << 'EOF'
#!/bin/bash

# MDM Agent Post-Install Script

set -e

LOG_FILE="/var/log/mdmagent_install.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INSTALL] $1" | tee -a "$LOG_FILE"
}

log_message "Starting MDM Agent post-installation..."

# Set proper permissions
chown root:wheel /Library/Management/MDMAgent/mdmagent_http.sh
chmod +x /Library/Management/MDMAgent/mdmagent_http.sh

chown root:wheel /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
chmod 644 /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist

# Create log file with proper permissions
touch /var/log/mdmagent.log
chown root:wheel /var/log/mdmagent.log
chmod 644 /var/log/mdmagent.log

# Load LaunchDaemon
launchctl load /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist

log_message "Waiting for agent to start..."
sleep 5

# Check if agent is running
if launchctl list | grep -q com.tolarcompany.mdmagent.http; then
    log_message "MDM Agent started successfully"
else
    log_message "WARNING: MDM Agent may not have started properly"
fi

log_message "MDM Agent installation completed"

# Display configuration notice
cat << 'NOTICE'

================================================================================
MDM Agent Installation Complete
================================================================================

The MDM Agent has been installed and started. However, you need to configure
it for your environment:

1. Edit the configuration:
   sudo nano /Library/Management/MDMAgent/mdmagent_http.sh
   
   Update these variables:
   - SERVER_URL (your repository server)
   - AUTH_USER (authentication username)
   - AUTH_PASS (authentication password)
   - MDM_ENDPOINT (webhook endpoint URL)

2. Restart the agent after configuration:
   sudo launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
   sudo launchctl load /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist

3. Monitor agent logs:
   tail -f /var/log/mdmagent.log

For more information, visit:
https://github.com/your-org/mdmagent-micromdm

================================================================================

NOTICE

exit 0
EOF
    chmod +x "$SCRIPTS_DIR/postinstall"
    
    # Create preinstall script
    cat > "$SCRIPTS_DIR/preinstall" << 'EOF'
#!/bin/bash

# MDM Agent Pre-Install Script

set -e

LOG_FILE="/var/log/mdmagent_install.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INSTALL] $1" | tee -a "$LOG_FILE"
}

log_message "Starting MDM Agent pre-installation..."

# Stop existing agent if running
if launchctl list | grep -q com.tolarcompany.mdmagent.http; then
    log_message "Stopping existing MDM Agent..."
    launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist 2>/dev/null || true
fi

# Kill any running agent processes
pkill -f mdmagent_http.sh 2>/dev/null || true

# Remove lock files
rm -f /tmp/mdmagent.lock

log_message "Pre-installation completed"

exit 0
EOF
    chmod +x "$SCRIPTS_DIR/preinstall"
    
    log_success "Install scripts prepared"
}

# Build package
build_package() {
    log_info "Building package..."
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$TEMP_DIR"
    
    # Build component package
    pkgbuild \
        --root "$PAYLOAD_DIR" \
        --scripts "$SCRIPTS_DIR" \
        --identifier "$PACKAGE_ID" \
        --version "$PACKAGE_VERSION" \
        --install-location "/" \
        "$TEMP_DIR/${PACKAGE_NAME}_component.pkg"
    
    # Create distribution XML
    cat > "$TEMP_DIR/distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>MDM Agent for microMDM</title>
    <organization>com.tolarcompany</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
    
    <welcome language="en" mime-type="text/plain">
Welcome to the MDM Agent for microMDM installer.

This will install the HTTP polling MDM agent on your system.
    </welcome>
    
    <conclusion language="en" mime-type="text/plain">
MDM Agent has been successfully installed.

Please configure the agent for your environment by editing:
/Library/Management/MDMAgent/mdmagent_http.sh

Then restart the agent:
sudo launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
sudo launchctl load /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
    </conclusion>
    
    <pkg-ref id="$PACKAGE_ID"/>
    
    <choices-outline>
        <line choice="default">
            <line choice="$PACKAGE_ID"/>
        </line>
    </choices-outline>
    
    <choice id="default"/>
    <choice id="$PACKAGE_ID" visible="false">
        <pkg-ref id="$PACKAGE_ID"/>
    </choice>
    
    <pkg-ref id="$PACKAGE_ID" version="$PACKAGE_VERSION" onConclusion="none">
        ${PACKAGE_NAME}_component.pkg
    </pkg-ref>
</installer-gui-script>
EOF
    
    # Build final product
    local final_pkg="$OUTPUT_DIR/${PACKAGE_NAME}.pkg"
    
    if [ -n "$DEVELOPER_ID_INSTALLER" ]; then
        log_info "Building signed package..."
        productbuild \
            --distribution "$TEMP_DIR/distribution.xml" \
            --package-path "$TEMP_DIR" \
            --sign "$DEVELOPER_ID_INSTALLER" \
            --keychain "$KEYCHAIN_PATH" \
            "$final_pkg"
    else
        log_warning "No signing identity specified, building unsigned package"
        productbuild \
            --distribution "$TEMP_DIR/distribution.xml" \
            --package-path "$TEMP_DIR" \
            "$final_pkg"
    fi
    
    log_success "Package built: $final_pkg"
}

# Verify package
verify_package() {
    local pkg_path="$OUTPUT_DIR/${PACKAGE_NAME}.pkg"
    
    log_info "Verifying package..."
    
    # Check package signature
    if pkgutil --check-signature "$pkg_path" &>/dev/null; then
        log_success "Package signature is valid"
    else
        log_warning "Package is not signed or signature is invalid"
    fi
    
    # Display package info
    log_info "Package information:"
    pkgutil --payload-files "$pkg_path" | head -20
    
    local pkg_size=$(du -h "$pkg_path" | cut -f1)
    log_success "Package size: $pkg_size"
}

# Cleanup
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    log_success "Cleanup completed"
}

# Main execution
main() {
    echo "==============================================="
    echo "MDM Agent PKG Builder v$PACKAGE_VERSION"
    echo "==============================================="
    echo
    
    check_prerequisites
    prepare_payload
    prepare_scripts
    build_package
    verify_package
    cleanup
    
    echo
    log_success "Build completed successfully!"
    echo
    echo "Package location: $OUTPUT_DIR/${PACKAGE_NAME}.pkg"
    echo
    echo "To install:"
    echo "  sudo installer -pkg $OUTPUT_DIR/${PACKAGE_NAME}.pkg -target /"
    echo
    echo "To distribute:"
    echo "  Upload the PKG to your software distribution system"
    echo
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help|--clean]"
        echo
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --clean       Clean build artifacts only"
        echo
        exit 0
        ;;
    --clean)
        log_info "Cleaning build artifacts..."
        rm -rf "$PAYLOAD_DIR" "$SCRIPTS_DIR" "$OUTPUT_DIR" "$TEMP_DIR"
        log_success "Clean completed"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
