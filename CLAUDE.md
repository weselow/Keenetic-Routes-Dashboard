# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VPN routing system for Keenetic routers (KN-1012, MT7628N 580MHz, 64MB RAM). Automatically routes traffic to specific services (WhatsApp, Telegram, etc.) through a VPN interface using ipset + policy routing. Includes an optional lightweight web dashboard.

**Language:** Shell/Bash (core), HTML/JS with TailwindCSS (dashboard)
**Target platform:** Keenetic router with Entware (OPKG)
**Development machine runs Windows; the router runs Linux (MIPS)**

## Deployment

Development is done on a Windows machine; files are deployed to the router via SSH/SCP.

```bash
# SSH access to router
ssh -p 222 root@192.168.1.1

# Install core system (run on router)
./install.sh

# Install dashboard (run on router)
./install-dashboard.sh
```

**Note:** Keenetic's SSH (dropbear) does not support exec mode — only interactive sessions.

## Router Commands

```bash
# Service control
/opt/bin/vpn-routes.sh start|stop|restart|status|update

# Dashboard control
/opt/etc/init.d/S80vpn-routes-web start|stop|restart|status

# Logs
tail -f /opt/var/log/vpn-routes/vpn-routes.$(date +%Y-%m-%d).log
```

## Architecture

### Data Flow

1. `vpn-routes.sh` downloads route list from `iplist.opencck.org` (Windows BAT format)
2. Parses BAT → CIDR format (e.g., `route add 1.0.0.0 mask 255.128.0.0 0.0.0.0` → `1.0.0.0/1`)
3. Populates `ipset` (hash:net) for O(1) lookup
4. `iptables` mangle PREROUTING marks packets destined for ipset entries with `FWMARK 0x1`
5. `ip rule` sends marked packets to routing table 100
6. Table 100 routes everything through the VPN interface (WireGuard)

Routes update daily at 04:00 via cron. Falls back to cached routes if download fails.

### Dashboard

lighttpd on port 8080 serving static HTML + 10 CGI endpoints (shell scripts returning JSON). All rendering happens in the browser to minimize router load.

### File Layout

- `opt/bin/vpn-routes.sh` — main routing script (~850 lines)
- `opt/etc/vpn-routes/config.sh` — all configurable parameters
- `opt/share/vpn-routes/www/` — dashboard HTML + `api/*.cgi` endpoints
- `opt/etc/init.d/S99vpn-routes` — autostart init script
- `opt/etc/init.d/S80vpn-routes-web` — dashboard init script
- `opt/etc/lighttpd/vpn-routes.conf` — web server config
- `tz.md` / `tz-dashboard.md` — detailed technical specifications (Russian)

## Known Pitfalls

**PATH in CGI context:** All scripts (vpn-routes.sh and every .cgi file) must explicitly set `PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin` at the top. CGI environment does not inherit system PATH — omitting this causes "Exit code: 127" errors.

**curl globoff:** URLs with `[]` (e.g., `exclude[cidr4]=...`) require `curl -g` to disable glob interpretation.

**sed `&` escaping:** When saving URLs containing `&` to config via sed, the `&` must be escaped (`\&`) because sed interprets it as "insert matched text."

**Resource constraints:** The router has only 64MB RAM. Keep scripts minimal, avoid unnecessary processes, prefer shell builtins over external commands where possible.

## Configuration

All settings are in `opt/etc/vpn-routes/config.sh`: routes URL, VPN interface name, ipset name, fwmark, route table number, log retention, curl timeout, and verbosity.

## Log Format

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message
```

Levels: INFO, ERROR, DEBUG. Daily log files, 7-day retention.
