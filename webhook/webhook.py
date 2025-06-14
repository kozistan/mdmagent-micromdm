#!/usr/bin/env python3
"""
MDM Agent Webhook Server for microMDM
Receives and processes command results from MDM agents
"""

from flask import Flask, request
import base64
import plistlib
import logging
import sys
import os
import json
from datetime import datetime

app = Flask(__name__)

# Configuration
LOGFILE = "/var/log/micromdm/webhook.log"
COMMAND_RESULTS_LOG = "/var/log/micromdm/command-results.log"

# Setup logging
logger = logging.getLogger('webhook')
logger.setLevel(logging.DEBUG if os.getenv("WEBHOOK_DEBUG") == "1" else logging.INFO)
logger.propagate = False

# Console handler
console_handler = logging.StreamHandler(sys.stdout)
console_handler.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s'))
logger.addHandler(console_handler)

# File handler
os.makedirs(os.path.dirname(LOGFILE), exist_ok=True)
file_handler = logging.FileHandler(LOGFILE)
file_handler.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(message)s'))
logger.addHandler(file_handler)

@app.route('/webhook', methods=['POST'])
def webhook():
    """
    Main microMDM webhook endpoint
    Processes acknowledgments and responses from enrolled devices
    """
    try:
        data = request.get_json()
        logger.info("=== MDM Event ===")
        logger.info(f"  topic: {data.get('topic')}")
        event = data.get("acknowledge_event", {})

        logger.info(f"  status: {event.get('status')}")
        logger.info(f"  udid: {event.get('udid')}")
        logger.info(f"  command_uuid: {event.get('command_uuid', 'N/A')}")

        # Log diagnostics for errors
        if event.get("error_chain"):
            logger.warning("  ErrorChain:")
            for i, e in enumerate(event["error_chain"]):
                logger.warning(f"    [{i}] {e}")
        if event.get("rejection_reason"):
            logger.warning(f"  RejectionReason: {event['rejection_reason']}")
        if event.get("error"):
            logger.warning(f"  Error: {event['error']}")

        raw_payload = event.get("raw_payload", "")
        if not raw_payload:
            return ''

        try:
            decoded = base64.b64decode(raw_payload)
            plist_data = plistlib.loads(decoded)

            request_type = plist_data.get("RequestType", "").lower()
            if request_type:
                logger.info(f"  RequestType: {request_type}")

            if "Payload" in plist_data:
                payload_preview = str(plist_data["Payload"])
                if len(payload_preview) > 200:
                    payload_preview = payload_preview[:200] + "..."
                logger.debug(f"  Payload (truncated): {payload_preview}")

            # Specific logging for known types
            if "InstalledApplicationList" in plist_data:
                logger.info("[InstalledApplicationList] Installed Apps:")
                for i, app in enumerate(plist_data["InstalledApplicationList"]):
                    name = app.get("Name", "Unknown")
                    bundle_id = app.get("Identifier", "Unknown")
                    version = app.get("ShortVersion", app.get("Version", app.get("BundleVersion", "")))
                    logger.info(f"  [{i}] {name} ({bundle_id}) v{version}")
                return ''

            if "ProfileList" in plist_data:
                logger.info("[ProfileList] Installed Profiles:")
                for i, profile in enumerate(plist_data["ProfileList"]):
                    ident = profile.get("PayloadIdentifier", "N/A")
                    name = profile.get("PayloadDisplayName", "N/A")
                    verified = "Verified" if profile.get("IsEncrypted", False) else "Unverified"
                    logger.info(f"  [{i}] {ident} ({name}) — {verified}")
                return ''

            if "ProvisioningProfileList" in plist_data:
                logger.info("[ProvisioningProfileList] Installed Provisioning Profiles:")
                for i, prov in enumerate(plist_data["ProvisioningProfileList"]):
                    ident = prov.get("PayloadIdentifier", "N/A")
                    name = prov.get("PayloadDisplayName", "N/A")
                    logger.info(f"  [{i}] {ident} ({name})")
                return ''

            if "CertificateList" in plist_data:
                logger.info("[CertificateList] Installed Certificates:")
                for i, cert in enumerate(plist_data["CertificateList"]):
                    common_name = cert.get("CommonName", "N/A")
                    is_root = cert.get("IsRoot", False)
                    logger.info(f"  [{i}] CN: {common_name} {'[ROOT]' if is_root else ''}")
                return ''

            if "SecurityInfo" in plist_data:
                logger.info("[SecurityInfo] Security Status:")
                for key, val in plist_data["SecurityInfo"].items():
                    logger.info(f"  {key}: {val}")
                return ''

            # Fallback - log entire payload
            logger.info("=== Decoded Payload ===")
            for key, value in plist_data.items():
                if isinstance(value, list):
                    logger.info(f"  {key}:")
                    for i, item in enumerate(value):
                        logger.info(f"    [{i}] {item}")
                elif isinstance(value, dict):
                    logger.info(f"  {key}:")
                    for subkey, subval in value.items():
                        logger.info(f"    {subkey}: {subval}")
                else:
                    logger.info(f"  {key}: {value}")

        except Exception as e:
            logger.warning(f"[!] Error decoding payload: {e}")

    except Exception as e:
        logger.error(f"[!] Unexpected error in webhook: {e}")
    return ''


@app.route('/command-result', methods=['POST', 'PUT'])
def command_result():
    """
    MDM Agent command result endpoint
    Receives command execution results from HTTP polling agents
    """
    try:
        data = request.get_json()
        
        # Validate required fields
        required_fields = ['device_udid', 'command_type', 'command_value', 'exit_code', 'status', 'timestamp']
        missing_fields = [field for field in required_fields if field not in data]
        
        if missing_fields:
            logger.error(f"Missing required fields: {missing_fields}")
            return {'error': 'Missing required fields', 'missing': missing_fields}, 400

        # Log command result
        logger.info("=== COMMAND RESULT ===")
        logger.info(f"  Device: {data.get('device_udid')}")
        logger.info(f"  Command: {data.get('command_type')} -> {data.get('command_value')}")
        logger.info(f"  Status: {data.get('status')} (exit code: {data.get('exit_code')})")
        logger.info(f"  Timestamp: {data.get('timestamp')}")

        # Log output if present
        if data.get('output'):
            output = data.get('output', '').strip()
            if output:
                # Truncate very long output for console log
                if len(output) > 500:
                    logger.info(f"  Output: {output[:500]}... [TRUNCATED]")
                else:
                    logger.info(f"  Output: {output}")

        logger.info("=== END COMMAND RESULT ===")

        # Write detailed log to separate file for analysis
        os.makedirs(os.path.dirname(COMMAND_RESULTS_LOG), exist_ok=True)
        
        log_entry = {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'device_udid': data.get('device_udid'),
            'command_type': data.get('command_type'),
            'command_value': data.get('command_value'),
            'exit_code': data.get('exit_code'),
            'status': data.get('status'),
            'output': data.get('output', ''),
            'agent_timestamp': data.get('timestamp')
        }
        
        with open(COMMAND_RESULTS_LOG, 'a') as f:
            f.write(json.dumps(log_entry) + '\n')

        return {'status': 'success'}, 200

    except Exception as e:
        logger.error(f"[!] Error processing command result: {e}")
        return {'error': 'Internal server error'}, 500


@app.route('/health', methods=['GET'])
def health():
    """
    Health check endpoint
    """
    return {
        'status': 'healthy',
        'service': 'mdm-agent-webhook',
        'version': '2.0',
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    }, 200


@app.route('/metrics', methods=['GET'])
def metrics():
    """
    Simple metrics endpoint
    Returns basic statistics about command processing
    """
    try:
        stats = {
            'total_commands': 0,
            'successful_commands': 0,
            'failed_commands': 0,
            'unique_devices': set(),
            'command_types': {}
        }
        
        # Parse command results log if it exists
        if os.path.exists(COMMAND_RESULTS_LOG):
            with open(COMMAND_RESULTS_LOG, 'r') as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())
                        stats['total_commands'] += 1
                        
                        if entry.get('status') == 'success':
                            stats['successful_commands'] += 1
                        else:
                            stats['failed_commands'] += 1
                            
                        stats['unique_devices'].add(entry.get('device_udid'))
                        
                        cmd_type = entry.get('command_type')
                        if cmd_type:
                            stats['command_types'][cmd_type] = stats['command_types'].get(cmd_type, 0) + 1
                            
                    except json.JSONDecodeError:
                        continue
        
        # Convert set to count
        stats['unique_devices'] = len(stats['unique_devices'])
        
        return {
            'metrics': stats,
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }, 200
        
    except Exception as e:
        logger.error(f"Error generating metrics: {e}")
        return {'error': 'Unable to generate metrics'}, 500


if __name__ == '__main__':
    # Configuration from environment variables
    host = os.getenv('WEBHOOK_HOST', '0.0.0.0')
    port = int(os.getenv('WEBHOOK_PORT', 5001))
    debug = os.getenv('WEBHOOK_DEBUG', '0') == '1'
    
    logger.info(f"Starting MDM Agent Webhook Server on {host}:{port}")
    logger.info(f"Debug mode: {'enabled' if debug else 'disabled'}")
    logger.info(f"Log file: {LOGFILE}")
    logger.info(f"Command results log: {COMMAND_RESULTS_LOG}")
    
    try:
        app.run(host=host, port=port, debug=debug)
    except Exception as e:
        logger.error(f"Failed to start webhook server: {e}")
        sys.exit(1)
