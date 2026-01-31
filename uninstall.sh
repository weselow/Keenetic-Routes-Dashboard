#!/bin/sh
# VPN Routes - Деинсталлятор
# Запускать на роутере Keenetic

set -e

echo "=== VPN Routes Uninstaller ==="
echo ""

# Остановка сервиса
echo "Остановка сервиса..."
if [ -x /opt/bin/vpn-routes.sh ]; then
    /opt/bin/vpn-routes.sh stop 2>/dev/null || true
fi

# Удаление из crontab
echo "Удаление из cron..."
if [ -f /opt/etc/crontab ]; then
    sed -i '/vpn-routes/d' /opt/etc/crontab 2>/dev/null || true
fi

# Удаление файлов
echo "Удаление файлов..."
rm -f /opt/bin/vpn-routes.sh
rm -f /opt/etc/init.d/S99vpn-routes
rm -f /opt/etc/cron.d/vpn-routes
rm -rf /opt/etc/vpn-routes
rm -f /opt/var/log/vpn-routes.log

echo ""
echo "=== Удаление завершено ==="
echo ""
echo "Пакеты ipset, iptables, curl остались установленными."
echo "Если они больше не нужны, удалите вручную:"
echo "  opkg remove ipset iptables curl"
echo ""
