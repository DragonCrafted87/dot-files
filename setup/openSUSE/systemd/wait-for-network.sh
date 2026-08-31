#!/bin/bash

# Script to bring up network interfaces using wicked and wait for an IP address
# Polls every 1 second for up to 30 seconds

TIMEOUT=30
INTERVAL=1
ELAPSED=0

# Get list of non-loopback interfaces
INTERFACES=$(wicked show all | grep -v 'lo' | grep -v ':' | awk '{print $1}' | grep -v '^$')

if [ -z "$INTERFACES" ]; then
    echo "No non-loopback interfaces found"
    exit 1
fi

# Attempt to bring up each interface
for IFACE in $INTERFACES; do
    echo "Bringing up interface $IFACE..."
    wicked ifup "$IFACE"
done

# Poll for IP address
while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check for any non-loopback interface with an IP address
    if ip addr show | grep -v "inet 127.0.0.1" | grep -q "inet "; then
        echo "Network interface has an IP address"
        ip addr show | grep "inet " | grep -v "127.0.0.1"
        exit 0
    fi
    echo "Waiting for network... ($ELAPSED/$TIMEOUT seconds)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "Timeout: No network interface received an IP address within $TIMEOUT seconds"
ip addr show
exit 1
