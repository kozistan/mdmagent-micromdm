# Deployment Guide

## Overview
This document covers deployment strategies for the MDM Agent system including package building, distribution, and mass deployment.

## Prerequisites

### Server Requirements
- microMDM server (https://micromdm.io)
- Webhook server (Python 3.x with Flask)
- Web server for command file hosting
- HAProxy or similar load balancer (optional)

### Client Requirements
- macOS 10.13+ (High Sierra or newer)
- Network connectivity to command server
- Administrator privileges for installation

## Package Building

### Build PKG Installer
Use the provided build script:

```bash
cd scripts/
./build_pkg.sh
```

This creates a signed PKG installer ready for distribution.

### Manual PKG Building
If you need to customize the build process:

```bash
# Create package structure
mkdir -p build/payload/Library/Management/MDMAgent
mkdir -p build/payload/Library/LaunchDaemons

# Copy agent files
cp agent/mdmagent_http.sh build/payload/Library/Management/MDMAgent/
cp agent/com.tolarcompany.mdmagent.http.plist build/payload/Library/LaunchDaemons/

# Set permissions
chmod 755 build/payload/Library/Management/MDMAgent/mdmagent_http.sh
chmod 644 build/payload/Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist

# Build package
pkgbuild --root build/payload \
         --identifier com.tolarcompany.mdmagent.http \
         --version 2.0 \
         --scripts scripts/ \
         mdmagent_http_installer.pkg
```

## Distribution Methods

### Apple Configurator 2
1. Import the PKG into Apple Configurator 2
2. Create a configuration profile
3. Deploy to devices via USB or wireless

### Munki
Add to Munki repository:

```bash
# Import package
munkiimport mdmagent_http_installer.pkg

# Add to manifest
manifestutil add-pkg mdmagent_http_installer manifest_name
```

### Jamf Pro
1. Upload PKG to Jamf Pro
2. Create policy for deployment
3. Scope to target computers
4. Set deployment schedule

### Manual Distribution
For testing or small deployments:

```bash
# Copy to target device
scp mdmagent_http_installer.pkg admin@target-device:~/Desktop/

# Install on device
sudo installer -pkg mdmagent_http_installer.pkg -target /
```

## Mass Deployment Strategies

### Staged Rollout
Deploy in phases to minimize risk:

1. **Pilot Group** (5-10 devices)
   - Test basic functionality
   - Verify webhook connectivity
   - Monitor for 24-48 hours

2. **Beta Group** (50-100 devices)
   - Test at scale
   - Monitor performance impact
   - Validate command execution

3. **Production Rollout** (All devices)
   - Deploy to remaining devices
   - Monitor centralized logs
   - Prepare rollback plan

### Deployment Automation

#### Using Ansible
```yaml
- name: Deploy MDM Agent
  hosts: macos_devices
  tasks:
    - name: Copy installer
      copy:
        src: mdmagent_http_installer.pkg
        dest: /tmp/mdmagent_http_installer.pkg
    
    - name: Install package
      command: installer -pkg /tmp/mdmagent_http_installer.pkg -target /
      become: yes
```

#### Using SSH Loop
```bash
#!/bin/bash
DEVICES=(
    "192.168.1.100"
    "192.168.1.101"
    "192.168.1.102"
)

for device in "${DEVICES[@]}"; do
    echo "Deploying to $device..."
    scp mdmagent_http_installer.pkg admin@$device:/tmp/
    ssh admin@$device "sudo installer -pkg /tmp/mdmagent_http_installer.pkg -target /"
done
```

## Command Server Setup

### Repository Structure
Set up web server to host command files:

```
/var/www/html/commands/
├── 58687F4F-898F-5153-9F83-88296A8111B0.json
├── A1B2C3D4-E5F6-7890-ABCD-EF1234567890.json
└── ...
```

### Web Server Configuration

#### Apache
```apache
<Directory "/var/www/html/commands">
    Options -Indexes
    AllowOverride None
    Require all granted
    
    # Enable CORS for agent access
    Header always set Access-Control-Allow-Origin "*"
    Header always set Access-Control-Allow-Methods "GET, OPTIONS"
</Directory>
```

#### Nginx
```nginx
location /commands/ {
    alias /var/www/html/commands/;
    
    # Enable CORS
    add_header Access-Control-Allow-Origin *;
    add_header Access-Control-Allow-Methods "GET, OPTIONS";
    
    # Disable directory listing
    autoindex off;
}
```

## Webhook Server Deployment

### Systemd Service
Install webhook as system service:

```bash
# Copy service file
sudo cp webhook/micromdm-webhook.service /etc/systemd/system/

# Enable and start service
sudo systemctl enable micromdm-webhook.service
sudo systemctl start micromdm-webhook.service
```

### Docker Deployment
```dockerfile
FROM python:3.9-slim

WORKDIR /app
COPY webhook/requirements.txt .
RUN pip install -r requirements.txt

COPY webhook/webhook.py .

EXPOSE 5001
CMD ["python", "webhook.py"]
```

### HAProxy Configuration
For external access through load balancer:

```haproxy
backend backend_webhook
    mode http
    balance source
    server webhook-server 10.10.150.55:5001

frontend https_frontend
    bind *:443 ssl crt /path/to/certificate.pem
    
    acl is_webhook_path path_beg -i /webhook/
    use_backend backend_webhook if { ssl_fc_sni -i mdm.domain.com } is_webhook_path
```

## Monitoring and Maintenance

### Health Checks
Implement monitoring for:

- Agent connectivity (HTTP polling frequency)
- Webhook endpoint availability
- Command execution success rates
- Network connectivity issues

### Log Monitoring
Set up log aggregation for:

```bash
# Agent logs
/var/log/mdmagent.log

# Webhook logs  
/var/log/micromdm/webhook.log

# System logs
/var/log/system.log
```

### Performance Metrics
Monitor these key metrics:

- Command delivery latency
- Agent polling frequency
- Webhook response times
- Failed command execution rates

## Rollback Procedures

### Emergency Rollback
If issues occur during deployment:

```bash
# Uninstall agent
sudo ./scripts/uninstall.sh

# Stop webhook service
sudo systemctl stop micromdm-webhook.service

# Restore previous configuration
sudo systemctl start previous-mdm-service
```

### Selective Rollback
For specific devices:

```bash
# Create rollback script
cat > rollback.sh << 'EOF'
#!/bin/bash
sudo launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
sudo rm -rf /Library/Management/MDMAgent
sudo rm /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
EOF

# Deploy to affected devices
for device in $AFFECTED_DEVICES; do
    scp rollback.sh admin@$device:/tmp/
    ssh admin@$device "bash /tmp/rollback.sh"
done
```

## Security Considerations

### Package Signing
Always sign PKG installers:

```bash
productsign --sign "Developer ID Installer: Your Name" \
           mdmagent_http_installer.pkg \
           mdmagent_http_installer_signed.pkg
```

### Network Security
- Use HTTPS for all communications
- Implement certificate pinning
- Restrict webhook access by IP
- Use VPN for sensitive environments

### Access Control
- Limit command server access
- Implement webhook authentication
- Use least-privilege principles
- Regular security audits

## Troubleshooting Deployment

### Common Issues

#### Package Installation Fails
- Check installer signature
- Verify target volume permissions
- Review installation logs: `/var/log/install.log`

#### Agent Doesn't Start
- Verify LaunchDaemon permissions
- Check network connectivity
- Review agent logs

#### Webhook Connectivity Issues
- Test direct webhook endpoint
- Verify HAProxy configuration
- Check firewall rules

### Support Tools
Use these tools for deployment troubleshooting:

```bash
# Check agent status
sudo launchctl list | grep mdmagent

# Test command server connectivity
curl -v https://repo.domain.com/commands/test.json

# Test webhook endpoint
curl -X POST -H "Content-Type: application/json" \
     -d '{"test":"data"}' \
     https://mdm.domain.com/webhook/command-result
```
