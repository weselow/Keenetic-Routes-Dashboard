#!/bin/sh
# VPN Routes Dashboard - Installer
# Run on router with Entware

set -e

echo "=== VPN Routes Dashboard Installer ==="
echo ""

# Check Entware
if [ ! -d "/opt/bin" ]; then
    echo "ERROR: Entware not found!"
    exit 1
fi

# Install dependencies
echo "Installing lighttpd..."
opkg update
opkg install lighttpd lighttpd-mod-cgi

# Create directories
echo "Creating directories..."
mkdir -p /opt/share/vpn-routes/www/api
mkdir -p /opt/etc/lighttpd
mkdir -p /opt/var/run
mkdir -p /opt/var/log

# The script assumes files are already copied to proper locations
# This is handled by the deployment script

# Set permissions for CGI scripts
echo "Setting permissions..."
chmod +x /opt/share/vpn-routes/www/api/*.cgi 2>/dev/null || true
chmod +x /opt/etc/init.d/S80vpn-routes-web 2>/dev/null || true

# Start web server
echo "Starting web server..."
/opt/etc/init.d/S80vpn-routes-web start

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Dashboard URL: http://192.168.1.1:8080"
echo ""
echo "Commands:"
echo "  /opt/etc/init.d/S80vpn-routes-web start   - Start"
echo "  /opt/etc/init.d/S80vpn-routes-web stop    - Stop"
echo "  /opt/etc/init.d/S80vpn-routes-web status  - Status"
echo ""
