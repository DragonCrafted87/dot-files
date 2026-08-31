#!/bin/bash
# Script to check the status of the BOINC client on openSUSE Leap 15.6
# Reports service state, attached projects, and running tasks
# Idempotent: safe to run multiple times
# Run with sudo to access BOINC data directory

# BOINC data directory
BOINC_DIR="/var/lib/boinc"
RPC_AUTH_FILE="${BOINC_DIR}/gui_rpc_auth.cfg"

echo "Checking BOINC client status..."

# Check if boinc-client service is running
echo -n "BOINC service status: "
if systemctl is-active --quiet boinc-client; then
    echo "Running"
else
    echo "Not running (start with 'sudo systemctl start boinc-client')"
    exit 1
fi

# Check for gui_rpc_auth.cfg
if [ ! -f "$RPC_AUTH_FILE" ]; then
    echo "Error: $RPC_AUTH_FILE not found. Run 'sudo /usr/local/bin/secondary-setup.sh' to generate it."
    exit 1
fi

# Read RPC password
if ! RPC_PASSWORD=$(cat "$RPC_AUTH_FILE"); then
    echo "Error: Failed to read RPC password from $RPC_AUTH_FILE. Check file permissions."
    echo "Ensure the file is readable by the boinc user and this script (run with sudo)."
    exit 1
fi

# Check attached projects
echo "Attached projects:"
if PROJECT_STATUS=$(boinccmd --passwd "$RPC_PASSWORD" --get_project_status 2>/dev/null); then
    if [ -z "$PROJECT_STATUS" ] || echo "$PROJECT_STATUS" | grep -q "no projects"; then
        echo "  No projects attached"
    else
        echo "$PROJECT_STATUS" | grep "master URL" | sed 's/.*master URL: /  - /'
    fi
else
    echo "  Error: Failed to retrieve project status. Check BOINC configuration."
fi

# Check running tasks
echo "Running tasks:"
if TASK_STATUS=$(boinccmd --passwd "$RPC_PASSWORD" --get_tasks 2>/dev/null); then
    if [ -z "$TASK_STATUS" ] || echo "$TASK_STATUS" | grep -q "no active tasks"; then
        echo "  No active tasks"
    else
        echo "$TASK_STATUS" | grep "name:" | sed 's/.*name: /  - /'
    fi
else
    echo "  Error: Failed to retrieve task status. Check BOINC configuration."
fi

echo "Status check complete."
echo "To configure BOINC for Science United, run 'sudo /usr/local/bin/boinc-config.sh'."
exit 0
