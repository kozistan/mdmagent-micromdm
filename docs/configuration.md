# Configuration Guide

## Overview
This document describes how to configure the MDM Agent and Webhook server components.

## Agent Configuration

### Environment Variables
The agent reads configuration from these environment variables:

```bash
DEVICE_UDID=58687F4F-898F-5153-9F83-88296A8111B0
SERVER_URL=https://repo.example.com
POLL_INTERVAL=5
MDM_ENDPOINT=https://mdm.example.com/webhook/command-result
```

### LaunchDaemon Configuration
Edit `/Library/LaunchDaemons/com.tolarcompany.mdmagent.http.plist`:

```xml
<dict>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DEVICE_UDID</key>
        <string>YOUR_DEVICE_UDID</string>
        <key>SERVER_URL</key>
        <string>https://your-repo-server.com</string>
        <key>MDM_ENDPOINT</key>
        <string>https://your-mdm-server.com/webhook/command-result</string>
    </dict>
</dict>
```

### Supported Commands
The agent supports these command types:

#### Test Command
```json
{
    "commands": [
        {
            "type": "test",
            "value": "Hello World"
        }
    ]
}
```

#### Hostname Command
```json
{
    "commands": [
        {
            "type": "hostname",
            "value": "new-hostname"
        }
    ]
}
```

#### Shell Command
```json
{
    "commands": [
        {
            "type": "shell",
            "value": "ls -la /Users",
            "parameters": "| grep admin"
        }
    ]
}
```

## Webhook Server Configuration

### Environment Setup
The webhook server requires these configurations:

```bash
# Server binding
HOST=0.0.0.0
PORT=5001

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/micromdm/webhook.log
```

### Endpoint Configuration
The webhook server provides these endpoints:

- `POST /webhook` - Receives MDM events from microMDM
- `PUT /command-result` - Receives command results from agents
- `POST /command-result` - Alternative method for command results

### microMDM Integration
Configure microMDM to send webhooks to:
```
http://your-webhook-server:5001/webhook
```

### HAProxy Integration
For external access through HAProxy, configure routing:

```haproxy
acl is_webhook_path path_beg -i /webhook/
use_backend backend_webhook if { ssl_fc_sni -i mdm.your-domain.com } is_webhook_path
```

## Security Considerations

### Certificate Management
- Use valid SSL certificates for all endpoints
- Implement certificate pinning where possible
- Rotate certificates regularly

### Network Security
- Restrict webhook access to known IP ranges
- Use firewall rules to limit exposure
- Implement rate limiting for webhook endpoints

### Agent Security
- Validate all incoming commands before execution
- Sanitize shell command inputs
- Log all command executions for audit

## Logging Configuration

### Agent Logging
Agent logs are written to:
```
/var/log/mdmagent.log
```

Log levels:
- INFO: Normal operations
- WARN: Non-critical issues
- ERROR: Critical failures

### Webhook Logging
Webhook logs include:
- Command results from agents
- MDM events from microMDM
- Error conditions and debugging info

Example log entry:
```
2025-06-14 10:04:55,374 [INFO] === COMMAND RESULT ===
2025-06-14 10:04:55,376 [INFO]   Device: 58687F4F-898F-5153-9F83-88296A8111B0
2025-06-14 10:04:55,376 [INFO]   Command: shell -> dscl . -list /Users
2025-06-14 10:04:55,376 [INFO]   Status: success (exit code: 0)
```

## Troubleshooting

### Common Issues

#### Agent Not Starting
- Check LaunchDaemon permissions: `sudo launchctl list | grep mdmagent`
- Verify network connectivity to server URL
- Check log file for specific errors

#### Commands Not Executing
- Verify JSON command format
- Check file permissions on command files
- Ensure agent has proper system permissions

#### Webhook Not Receiving Data
- Test webhook endpoint directly with curl
- Check HAProxy routing configuration
- Verify firewall settings

### Debug Mode
Enable debug logging by setting environment variable:
```bash
export DEBUG=1
```

This will increase log verbosity for troubleshooting.
