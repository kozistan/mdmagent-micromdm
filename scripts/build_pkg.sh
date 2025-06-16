#!/bin/bash

# PKG Builder for HTTP MDM Agent
# Tolar Company s.r.o.

set -e

AGENT_DIR="./pkg_root/Library/Management/MDMAgent"
LAUNCHD_DIR="./pkg_root/Library/LaunchDaemons"
SCRIPTS_DIR="./pkg_scripts"
FINAL_PKG="mdmagent_http_installer.pkg"

echo " Building HTTP MDM Agent PKG..."

# Clean previous builds
rm -rf pkg_root pkg_scripts *.pkg 2>/dev/null || true

# Create directory structure
echo " Creating package structure..."
mkdir -p "$AGENT_DIR"
mkdir -p "$LAUNCHD_DIR"
mkdir -p "$SCRIPTS_DIR"

# Copy HTTP agent script
echo " Copying HTTP agent script..."
cp mdmagent_http.sh "$AGENT_DIR/"
chmod +x "$AGENT_DIR/mdmagent_http.sh"

# Copy HTTP LaunchDaemon plist
echo " Copying HTTP LaunchDaemon..."
cp com.tolarcompany.mdmagent.http.plist "$LAUNCHD_DIR/"

# Create preinstall script
echo " Creating preinstall script..."
cat > "$SCRIPTS_DIR/preinstall" << 'EOF'
#!/bin/bash

# Stop existing services if running
echo "Checking for existing MDM Agent services..."

# Stop old profile-based agent
if launchctl list | grep -q "com.tolarcompany.mdmagent"; then
    echo "Stopping old profile-based MDM Agent..."
    launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.plist 2>/dev/null || true
fi

# Stop HTTP agent if exists
if launchctl list | grep -q "com.tolarcompany.mdmagent.http"; then
    echo "Stopping existing HTTP MDM Agent..."
    launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist 2>/dev/null || true
fi

# Remove old files
echo "Cleaning old installations..."
rm -f /Library/Management/MDMAgent/mdmagent.sh 2>/dev/null || true
rm -f /Library/Management/MDMAgent/mdmagent_http.sh 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.tolarcompany.mdmagent.plist 2>/dev/null || true
rm -f /tmp/mdmagent.lock 2>/dev/null || true

# Clean any remaining temp files
rm -f /tmp/commands_response.json 2>/dev/null || true
rm -f /tmp/mdm_test_result.txt 2>/dev/null || true
rm -f /tmp/mdm_shell_result.txt 2>/dev/null || true

echo "Preinstall completed"
exit 0
EOF

# Create postinstall script
echo " Creating postinstall script..."
cat > "$SCRIPTS_DIR/postinstall" << 'EOF'
#!/bin/bash

# Create config directory and file
echo "Setting up MDM Agent configuration..."
mkdir -p /etc/mdm
chmod 700 /etc/mdm

# Create config file if it doesn't exist
if [ ! -f /etc/mdm/config ]; then
    echo "Creating new config file..."
    cat > /etc/mdm/config << CONFIGEOF
# MDM Agent Configuration
AUTH_USER="repouser"
AUTH_PASS="your-password"
CONFIGEOF
else
    echo "Config file already exists, preserving current settings"
    # Verify it has required keys
    if ! grep -q "AUTH_USER" /etc/mdm/config || ! grep -q "AUTH_PASS" /etc/mdm/config; then
        echo "Config file incomplete, adding missing credentials..."
        echo "" >> /etc/mdm/config
        echo "# Added during package installation" >> /etc/mdm/config
        grep -q "AUTH_USER" /etc/mdm/config || echo 'AUTH_USER="repouser"' >> /etc/mdm/config
        grep -q "AUTH_PASS" /etc/mdm/config || echo 'AUTH_PASS="your-password"' >> /etc/mdm/config
    fi
fi

# Secure config file
chmod 600 /etc/mdm/config
chown root:wheel /etc/mdm/config

# Set correct permissions
echo "Setting file permissions..."
chown root:wheel /Library/Management/MDMAgent/mdmagent_http.sh
chmod +x /Library/Management/MDMAgent/mdmagent_http.sh
chown root:wheel /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
chmod 644 /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist

# Load and start HTTP service
echo "Starting HTTP MDM Agent service..."
launchctl load /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist

# Wait for service to start
sleep 3

# Get device UDID for logging
DEVICE_UDID=$(system_profiler SPHardwareDataType | grep "Hardware UUID" | awk '{print $3}')

# Log installation
echo "[$(date '+%Y-%m-%d %H:%M:%S')] HTTP MDM Agent installed via PKG - Device: $DEVICE_UDID" >> /var/log/mdmagent.log

# Test connectivity
echo "Testing connectivity to repo.example.com..."
if curl -s -u "repouser:your-password" --connect-timeout 5 https://repo.example.com/commands/ >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Connectivity test to repo.example.com: SUCCESS" >> /var/log/mdmagent.log
    echo " HTTP MDM Agent installation completed successfully!"
    echo " Agent will poll: https://repo.example.com/commands/$DEVICE_UDID.json"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Connectivity test to repo.example.com: FAILED" >> /var/log/mdmagent.log
    echo "  HTTP MDM Agent installed but connectivity test failed"
    echo " Check network connectivity to repo.example.com"
fi

echo " Installation complete! Monitor logs with: tail -f /var/log/mdmagent.log"
echo " Config file created at: /etc/mdm/config"
exit 0
EOF

# Make scripts executable
chmod +x "$SCRIPTS_DIR/preinstall"
chmod +x "$SCRIPTS_DIR/postinstall"

# Build component package first
echo " Building component package..."
COMPONENT_PKG="mdmagent_http_component.pkg"
pkgbuild --root ./pkg_root \
         --scripts ./pkg_scripts \
         --identifier "com.tolarcompany.mdmagent.http" \
         --version "2.1" \
         --install-location "/" \
         "$COMPONENT_PKG"

# Build product archive with Distribution
echo " Building signed product archive..."
productbuild --package "$COMPONENT_PKG" \
             --identifier "com.tolarcompany.mdmagent.http.installer" \
             --version "2.1" \
             --sign "Developer ID Installer: Martin Kubovciak (8F5H7GQX9D)" \
             "$FINAL_PKG"

# Clean up component package
rm -f "$COMPONENT_PKG"

# Verify package
if [ -f "$FINAL_PKG" ]; then
    echo " Package created successfully: $FINAL_PKG"
    echo ""
    echo " Package info:"
    ls -lh "$FINAL_PKG"
    echo ""
    echo " Package contents:"
    pkgutil --payload-files "$FINAL_PKG"
    echo ""
    echo " Security improvements:"
    echo "- Config file with secure permissions (600)"
    echo "- Credentials stored in /etc/mdm/config"
    echo "- No hardcoded passwords in main script"
    echo ""
    echo " Next steps:"
    echo "1. Upload $FINAL_PKG to MDM server for distribution"
    echo "2. Set up API endpoint on repo.example.com:"
    echo "   sudo mkdir -p /var/www/html/api/commands"
    echo "   sudo chown www-data:www-data /var/www/html/api/commands"
    echo "3. Install command sender on repo.example.com"
    echo "4. Send InstallApplication command via MDM"
    echo ""
    echo " Local test:"
    echo "   sudo installer -pkg $FINAL_PKG -target /"
    echo ""
    echo " Command usage:"
    echo "   ./send_command.sh DEVICE_UDID test 'HTTP test'"
    echo "   ./send_command.sh DEVICE_UDID hostname 'new-name'"
    echo "   ./send_command.sh DEVICE_UDID shell 'echo hello'"
else
    echo " Package creation failed!"
    exit 1
fi

echo " HTTP MDM Agent PKG build completed!"
