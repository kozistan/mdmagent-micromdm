# Installation Guide

This guide walks you through installing and configuring the MDM Agent for microMDM on macOS devices.

## Prerequisites

### System Requirements

- **macOS 10.14** or later
- **Administrative privileges** for installation
- **Network access** to repository server
- **Internet connectivity** for package downloads

### Infrastructure Requirements

- **microMDM server** running and configured
- **Repository server** with HTTPS support (Apache/nginx)
- **Webhook server** for command feedback
- **SSH access** to repository server from MDM server

## Installation Methods

### Method 1: Automated Script Installation

The easiest way to install and configure the agent:

```bash
# Download and run installation script
curl -fsSL https://raw.githubusercontent.com/your-org/mdmagent-micromdm/main/deploy/scripts/install.sh | sudo bash

# Or with custom configuration
sudo ./deploy/scripts/install.sh \
  --server-url "https://repo.company.com" \
  --auth-user "repouser" \
  --auth-pass "secretpassword" \
  --mdm-endpoint "https://mdm.company.com/webhook/command-result" \
  --unattended
```

### Method 2: Manual PKG Installation

For more control over the installation process:

#### Step 1: Download Package

```bash
# Download the latest PKG installer
curl -O https://your-repo.com/packages/mdmagent_http_installer.pkg

# Verify package signature (optional)
pkgutil --check-signature mdmagent_http_installer.pkg
```

#### Step 2: Install Package

```bash
# Install the package
sudo installer -pkg mdmagent_http_installer.pkg -target /
```

#### Step 3: Configure Agent

Edit the agent configuration:

```bash
sudo nano /Library/Management/MDMAgent/mdmagent_http.sh
```

Update these variables:

```bash
# Server configuration
SERVER_URL="https://repo.example.com"
AUTH_USER="repouser"
AUTH_PASS="your-password"

# Webhook configuration
MDM_ENDPOINT="https://mdm.example.com/webhook/command-result"

# Polling configuration
POLL_INTERVAL=5
```

#### Step 4: Start Agent

```bash
# Restart the agent service
sudo launchctl unload /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
sudo launchctl load /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
```

### Method 3: Build from Source

For development or customization:

#### Step 1: Clone Repository

```bash
git clone https://github.com/your-org/mdmagent-micromdm.git
cd mdmagent-micromdm
```

#### Step 2: Build Package

```bash
cd build/
./build_pkg.sh
```

#### Step 3: Install Built Package

```bash
sudo installer -pkg output/mdmagent_http_installer.pkg -target /
```

## Configuration

### Environment Variables

You can configure the agent using environment variables:

```bash
export MDM_SERVER_URL="https://repo.company.com"
export MDM_AUTH_USER="repouser"
export MDM_AUTH_PASS="secretpassword"
export MDM_ENDPOINT="https://mdm.company.com/webhook/command-result"
export MDM_POLL_INTERVAL=5
```

### Configuration Files

#### Agent Configuration

The main agent script is located at:
```
/Library/Management/MDMAgent/mdmagent_http.sh
```

Key configuration variables:
- `SERVER_URL` - Repository server URL
- `AUTH_USER` - HTTP Basic Auth username
- `AUTH_PASS` - HTTP Basic Auth password
- `MDM_ENDPOINT` - Webhook endpoint for command results
- `POLL_INTERVAL` - How often to check for commands (seconds)

#### LaunchDaemon Configuration

The service configuration is at:
```
/Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
```

Key settings:
- `RunAtLoad` - Start automatically on boot
- `KeepAlive` - Restart if crashed
- `ThrottleInterval` - Minimum time between restarts

## Verification

### Check Installation

```bash
# Verify files are installed
ls -la /Library/Management/MDMAgent/
ls -la /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist

# Check service status
sudo launchctl list | grep mdmagent

# View recent logs
tail -20 /var/log/mdmagent.log
```

### Test Connectivity

```bash
# Test repository server connectivity
curl -u "repouser:password" https://repo.example.com/munki/

# Test webhook endpoint
curl -X POST -H "Content-Type: application/json" \
  -d '{"test": "connectivity"}' \
  https://mdm.example.com/webhook/command-result
```

### Send Test Command

From your MDM server:

```bash
# Send test command
./deploy/send_command DEVICE_UDID test "Installation verification"

# Check webhook logs
tail -f /var/log/micromdm/webhook.log
```

## Mass Deployment

### Using MDM

1. **Upload PKG** to your MDM system
2. **Create policy** to install on target devices
3. **Configure post-install** script for device-specific settings
4. **Deploy policy** to device groups

### Using Configuration Management

#### Ansible Example

```yaml
- name: Install MDM Agent
  ansible.builtin.command:
    cmd: installer -pkg /tmp/mdmagent_http_installer.pkg -target /
  become: yes

- name: Configure MDM Agent
  ansible.builtin.replace:
    path: /Library/Management/MDMAgent/mdmagent_http.sh
    regexp: 'SERVER_URL=".*"'
    replace: 'SERVER_URL="{{ mdm_server_url }}"'
  become: yes

- name: Start MDM Agent
  ansible.builtin.command:
    cmd: launchctl load /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
  become: yes
```

#### Puppet Example

```puppet
package { 'mdmagent':
  ensure   => installed,
  source   => '/tmp/mdmagent_http_installer.pkg',
  provider => 'pkgdmg',
}

file { '/Library/Management/MDMAgent/mdmagent_http.sh':
  ensure  => file,
  content => template('mdmagent/mdmagent_http.sh.erb'),
  mode    => '0755',
  owner   => 'root',
  group   => 'wheel',
  require => Package['mdmagent'],
  notify  => Service['mdmagent'],
}

service { 'mdmagent':
  ensure => running,
  enable => true,
  name   => 'com.tolarcompany.mdmagent.http',
}
```

### Using Scripts

#### Bulk Deployment Script

```bash
#!/bin/bash
# Bulk deployment to multiple devices

DEVICE_LIST="devices.txt"  # One hostname per line
PACKAGE_PATH="./mdmagent_http_installer.pkg"

while IFS= read -r hostname; do
  echo "Deploying to $hostname..."
  
  # Copy package
  scp "$PACKAGE_PATH" "admin@$hostname:/tmp/"
  
  # Install and configure
  ssh "admin@$hostname" "
    sudo installer -pkg /tmp/mdmagent_http_installer.pkg -target /
    sudo sed -i '' 's|SERVER_URL=\".*\"|SERVER_URL=\"https://repo.company.com\"|g' /Library/Management/MDMAgent/mdmagent_http.sh
    sudo launchctl load /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
    rm /tmp/mdmagent_http_installer.pkg
  "
  
  echo "Deployment to $hostname completed"
done < "$DEVICE_LIST"
```

## Troubleshooting

### Common Issues

#### Agent Not Starting

```bash
# Check LaunchDaemon status
sudo launchctl list | grep mdmagent

# Check for errors in system log
log show --predicate 'subsystem == "com.apple.launchd"' --info --last 1h | grep mdmagent

# Manually test agent script
sudo /Library/Management/MDMAgent/mdmagent_http.sh
```

#### Connectivity Issues

```bash
# Test network connectivity
ping repo.example.com

# Test HTTPS connectivity
curl -v https://repo.example.com/

# Test authentication
curl -u "repouser:password" https://repo.example.com/munki/
```

#### Permission Issues

```bash
# Fix agent script permissions
sudo chown root:wheel /Library/Management/MDMAgent/mdmagent_http.sh
sudo chmod +x /Library/Management/MDMAgent/mdmagent_http.sh

# Fix LaunchDaemon permissions
sudo chown root:wheel /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
sudo chmod 644 /Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist
```

### Log Files

- **Agent logs**: `/var/log/mdmagent.log`
- **Installation logs**: `/var/log/mdmagent_install.log`
- **System logs**: `log show --predicate 'subsystem == "com.tolarcompany.mdmagent"'`

### Getting Help

1. **Check logs** for error messages
2. **Verify configuration** settings
3. **Test connectivity** to servers
4. **Review documentation** for your specific setup
5. **Open an issue** on GitHub with logs and configuration

## Security Considerations

### Network Security

- Use **HTTPS** for all communications
- Implement **certificate pinning** if required
- Configure **firewall rules** appropriately
- Use **VPN** for remote devices if needed

### Authentication

- Use **strong passwords** for HTTP Basic Auth
- Consider **certificate-based authentication**
- Rotate **credentials regularly**
- Implement **access logging**

### Device Security

- **Sign PKG installers** with valid Developer ID
- Implement **code signing verification**
- Use **secure update mechanisms**
- Monitor for **unauthorized modifications**

## Next Steps

1. **Configure webhook server** for command feedback
2. **Set up monitoring** for agent health
3. **Create deployment policies** for your organization
4. **Test command functionality** with your devices
5. **Implement backup and recovery** procedures

For more information, see:
- [Configuration Guide](configuration.md)
- [Commands Reference](commands.md)
- [Troubleshooting Guide](troubleshooting.md)
