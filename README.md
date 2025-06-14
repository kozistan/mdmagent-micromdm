# MDM Agent for microMDM

Centralized HTTP polling MDM agent with webhook feedback for microMDM systems.

## Overview

This project provides an alternative to traditional MDM configuration profiles using HTTP polling mechanism. The agent runs on macOS devices, periodically checks for commands on a central server, and sends feedback via webhook.

## Features

- ✅ **HTTP Polling** - No configuration profiles required
- ✅ **Command Execution** - test, hostname, shell commands  
- ✅ **Webhook Feedback** - Real-time command results
- ✅ **Hash Tracking** - Prevents command duplicates
- ✅ **JSON Escaping** - Safe shell output processing
- ✅ **Signed PKG** - Production-ready distribution
- ✅ **LaunchDaemon** - Automatic startup

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
./deploy/send_command DEVICE_UDID test "Hello World"

# Change hostname
./deploy/send_command DEVICE_UDID hostname "new-device-name"

# Execute shell command
./deploy/send_command DEVICE_UDID shell "brew install git"
```

### Monitor Results

```bash
# Watch webhook logs
tail -f /var/log/micromdm/webhook.log
```

## Repository Structure

```
mdmagent-micromdm/
├── README.md
├── LICENSE
├── src/
│   ├── mdmagent_http.sh          # Main agent script
│   └── config/
│       └── com.tolarcompany.mdmagent.http.plist
├── build/
│   ├── build_pkg.sh              # PKG builder script
│   ├── payload/                  # PKG payload structure
│   └── scripts/                  # Pre/post install scripts
├── webhook/
│   ├── webhook.py                # Flask webhook server
│   ├── requirements.txt          # Python dependencies
│   └── config/
│       └── micromdm-webhook.service
├── deploy/
│   ├── send_command              # Command sender script
│   └── scripts/
│       ├── install.sh            # Deployment script
│       └── uninstall.sh          # Removal script
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

### Repository Server
- Web server (Apache/nginx) with HTTPS
- SSH daemon
- Munki repository (optional)

## Configuration

### Agent Configuration

Edit configuration in `src/config/mdmagent_config.sh`:

```bash
SERVER_URL="https://repo.example.com"
POLL_INTERVAL=5
MDM_ENDPOINT="https://mdm.example.com/webhook/command-result"
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
cd build/
./build_pkg.sh

# Output: mdmagent_http_installer.pkg
```

### Build Requirements

- **macOS** development machine
- **Xcode Command Line Tools**
- **Developer certificate** for signing
- **pkgbuild** and **productbuild** tools

## Deployment

### Mass Deployment

```bash
# Deploy to multiple devices
./deploy/scripts/bulk_deploy.sh device_list.txt

# Monitor deployment status
./examples/monitoring.sh
```

### Manual Deployment

```bash
# Copy PKG to target device
scp build/mdmagent_http_installer.pkg admin@target-device:~/

# Install remotely
ssh admin@target-device sudo installer -pkg ~/mdmagent_http_installer.pkg -target /
```

## Command Types

### Test Command
```bash
./deploy/send_command UDID test "Test message"
```

### Hostname Change
```bash
./deploy/send_command UDID hostname "new-hostname"
```

### Shell Command
```bash
./deploy/send_command UDID shell "command to execute"
```

## Webhook Response Format

```json
{
    "device_udid": "58687F4F-898F-5153-9F83-88296A8111B0",
    "command_type": "test",
    "command_value": "Hello World",
    "exit_code": 0,
    "output": "Command executed successfully",
    "timestamp": "2025-06-14T10:00:00Z",
    "status": "success"
}
```

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

## Security

- **HTTPS** for all communications
- **Basic Authentication** for repository access
- **Certificate pinning** available
- **Command validation** before execution
- **Audit logging** of all actions

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues and solutions.

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/your-org/mdmagent-micromdm/issues)
- **Documentation**: [Wiki](https://github.com/your-org/mdmagent-micromdm/wiki)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/mdmagent-micromdm/discussions)

---

**Made with ❤️ for macOS fleet management**
