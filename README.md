# MDM Agent for microMDM

Centralized HTTP polling MDM agent with webhook feedback and user management for microMDM systems.

## Overview

This project provides an alternative to traditional MDM configuration profiles using HTTP polling mechanism. The agent runs on macOS devices, periodically checks for commands on a central server, and sends feedback via webhook.

## Features

- ✅ **HTTP Polling** - No configuration profiles required
- ✅ **Command Execution** - test, hostname, shell commands
- ✅ **User Management** - Create, disable, enable users remotely
- ✅ **Password Management** - Set user passwords securely
- ✅ **Webhook Feedback** - Real-time command results
- ✅ **Hash Tracking** - Prevents command duplicates
- ✅ **JSON Escaping** - Safe shell output processing
- ✅ **Signed PKG** - Production-ready distribution
- ✅ **LaunchDaemon** - Automatic startup
- ✅ **Secure Config** - External credentials file

## Architecture

```
MDM Server → SSH → Repo Server → HTTP → Agent → Webhook → Logs
```

1. **MDM Server** (`send_command`) sends commands via SSH to repo server
2. **Agent** polls for commands from HTTPS endpoint every 5 seconds
3. **Agent** executes commands and sends results to webhook
4. **Webhook** logs results to centralized logs

## Quick Start

### Installation

```bash
# Download PKG installer
curl -O https://your-repo.com/packages/mdmagent_http_installer.pkg

# Install on target device
sudo installer -pkg mdmagent_http_installer.pkg -target /
```

### Send Commands

```bash
# Test command
./tools/api/commands/send_command DEVICE_UDID test "Hello World"

# Change hostname
./tools/api/commands/send_command DEVICE_UDID hostname "new-device-name"

# Execute shell command
./tools/api/commands/send_command DEVICE_UDID shell "brew install git"

# Create admin user
./tools/api/commands/send_command DEVICE_UDID createuser "johndoe" "admin|mypassword123"

# Create standard user
./tools/api/commands/send_command DEVICE_UDID createuser "janedoe" "standard|userpass456"

# Disable user
./tools/api/commands/send_command DEVICE_UDID disableuser "johndoe"

# Enable user
./tools/api/commands/send_command DEVICE_UDID enableuser "johndoe"

# Set user password
./tools/api/commands/send_command DEVICE_UDID setpassword "johndoe" "newpassword"
```

### Monitor Results

```bash
# Watch webhook logs
tail -f /var/log/micromdm/webhook.log

# Watch agent logs
tail -f /var/log/mdmagent.log
```

## Repository Structure

```
mdmagent-micromdm/
├── README.md
├── LICENSE
├── scripts/
│   ├── mdmagent_http.sh          # Main agent script (v2.2)
│   └── build_http_pkg.sh         # PKG builder script
├── config/
│   └── com.tolarcompany.mdmagent.http.plist
├── tools/
│   └── api/
│       └── commands/
│           └── send_command      # Command sender script
├── webhook/
│   ├── webhook.py                # Flask webhook server
│   ├── requirements.txt          # Python dependencies
│   └── config/
│       └── micromdm-webhook.service
├── docs/
│   ├── installation.md           # Installation guide
│   ├── configuration.md          # Configuration options
│   ├── commands.md               # Available commands
│   └── troubleshooting.md        # Common issues
└── examples/
    ├── bulk_commands.sh          # Bulk command examples
    └── monitoring.sh             # Monitoring examples
```

## Requirements

### MDM Server
- microMDM running
- SSH access to repository server
- Python 3.7+ for webhook

### Target Devices
- macOS 10.14+
- Network access to repository server
- Administrative privileges for installation
- Command Line Tools (installed automatically)

### Repository Server
- Web server (Apache/nginx) with HTTPS
- SSH daemon
- Munki repository (optional)

## Configuration

### Agent Configuration

Configuration is stored in `/etc/mdm/config` (created during installation):

```bash
# MDM Agent Configuration
AUTH_USER="repouser"
AUTH_PASS="your-password"
```

### Webhook Configuration

Configure webhook endpoint in `webhook/webhook.py`:

```python
# Webhook server configuration
app.run(host='0.0.0.0', port=5001)
```

## Building

### Build PKG Installer

```bash
# Build signed PKG
./build_http_pkg.sh

# Output: mdmagent_http_installer.pkg
```

### Build Requirements

- **macOS** development machine
- **Xcode Command Line Tools**
- **Developer certificate** for signing
- **pkgbuild** and **productbuild** tools

## Command Types

### System Commands

#### Test Command
```bash
./tools/api/commands/send_command UDID test "Test message"
```

#### Hostname Change
```bash
./tools/api/commands/send_command UDID hostname "new-hostname"
```

#### Shell Command
```bash
./tools/api/commands/send_command UDID shell "command to execute"
```

### User Management Commands

#### Create User
```bash
# Create admin user
./tools/api/commands/send_command UDID createuser "username" "admin|password123"

# Create standard user  
./tools/api/commands/send_command UDID createuser "username" "standard|password123"
```

#### Disable/Enable User
```bash
# Disable user (sets shell to /usr/bin/false)
./tools/api/commands/send_command UDID disableuser "username"

# Enable user (sets shell to /bin/bash)
./tools/api/commands/send_command UDID enableuser "username"
```

#### Set Password
```bash
./tools/api/commands/send_command UDID setpassword "username" "newpassword"
```

### JSON Command Format

```json
{
  "commands": [
    {
      "type": "createuser",
      "value": "johndoe", 
      "parameter": "admin|mypassword123"
    },
    {
      "type": "disableuser",
      "value": "johndoe",
      "parameter": ""
    }
  ]
}
```

## Webhook Response Format

```json
{
    "device_udid": "58687F4F-898F-5153-9F83-88296A8111B0",
    "command_type": "createuser",
    "command_value": "johndoe",
    "exit_code": 0,
    "output": "User johndoe created successfully as admin user with UID 501",
    "timestamp": "2025-06-16T10:00:00Z",
    "status": "success"
}
```

## Security Features

- **HTTPS** for all communications
- **Basic Authentication** for repository access
- **Secure config file** (`/etc/mdm/config` with 600 permissions)
- **User validation** (prevents system user modification)
- **Command validation** before execution
- **Audit logging** of all actions
- **No hardcoded passwords** in scripts

### User Management Security

- Cannot modify system users (UID < 500)
- Cannot modify current user
- Cannot modify root user
- Username format validation
- Password requirements enforced
- All changes logged

## Monitoring

### Agent Status
```bash
# Check agent status on device
sudo launchctl list | grep mdmagent

# View agent logs
tail -f /var/log/mdmagent.log
```

### Webhook Logs
```bash
# Monitor webhook responses
tail -f /var/log/micromdm/webhook.log
```

### Command History
```bash
# View processed commands
ls -la /tmp/processed_*
```

### User Management Monitoring
```bash
# List all users (excluding system users)
dscl . -list /Users | grep -v '^_' | grep -v root

# Check user status
dscl . -read /Users/username UserShell
```

## Troubleshooting

### Common Issues

#### Command Line Tools License
If you encounter Xcode license errors, the PKG installer automatically attempts to resolve this. For manual resolution:

```bash
# Check Command Line Tools status
xcode-select -p

# Install if missing
xcode-select --install
```

#### User Creation Failures
Check logs for DS Error -14120:
```bash
tail -f /var/log/mdmagent.log | grep -E "(createuser|disableuser)"
```

#### Config File Missing
```bash
# Verify config exists
ls -la /etc/mdm/config

# Recreate if missing
sudo mkdir -p /etc/mdm
sudo tee /etc/mdm/config << EOF
AUTH_USER="repouser"  
AUTH_PASS="your-password"
EOF
sudo chmod 600 /etc/mdm/config
```

See [docs/troubleshooting.md](docs/troubleshooting.md) for detailed solutions.

## Version History

### v2.2 (Current)
- ✅ User management commands (createuser, disableuser, enableuser)
- ✅ Password management (setpassword) 
- ✅ Security validations for user operations
- ✅ Improved error handling

### v2.1
- ✅ Secure external configuration file
- ✅ Command Line Tools integration
- ✅ Improved PKG installer

### v2.0
- ✅ HTTP polling architecture
- ✅ Webhook feedback system
- ✅ Signed PKG distribution

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/user-management`)
3. Commit changes (`git commit -m 'Add user management features'`)
4. Push to branch (`git push origin feature/user-management`)
5. Open Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/your-org/mdmagent-micromdm/issues)
- **Documentation**: [Wiki](https://github.com/your-org/mdmagent-micromdm/wiki)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/mdmagent-micromdm/discussions)

---


