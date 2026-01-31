#!/bin/sh
# VPN Routes - Установщик
# Запускать на роутере Keenetic с Entware

set -e

echo "=== VPN Routes Installer ==="
echo ""

# Проверка Entware
if [ ! -d "/opt/bin" ]; then
    echo "ОШИБКА: Entware не установлен!"
    echo "Установите Entware: https://help.keenetic.com/hc/ru/articles/360021214160"
    exit 1
fi

# Установка зависимостей
echo "Установка зависимостей..."
opkg update
opkg install ipset iptables curl ca-certificates

# Создание директорий
echo "Создание директорий..."
mkdir -p /opt/etc/vpn-routes
mkdir -p /opt/var/log

# Определение директории скрипта
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Копирование файлов
echo "Копирование файлов..."

if [ -f "$SCRIPT_DIR/opt/etc/vpn-routes/config.sh" ]; then
    # Установка из локальной директории
    cp "$SCRIPT_DIR/opt/etc/vpn-routes/config.sh" /opt/etc/vpn-routes/config.sh
    cp "$SCRIPT_DIR/opt/bin/vpn-routes.sh" /opt/bin/vpn-routes.sh
    cp "$SCRIPT_DIR/opt/etc/init.d/S99vpn-routes" /opt/etc/init.d/S99vpn-routes
    cp "$SCRIPT_DIR/opt/etc/cron.d/vpn-routes" /opt/etc/cron.d/vpn-routes
else
    echo "ОШИБКА: Файлы не найдены в $SCRIPT_DIR"
    echo "Убедитесь, что структура директорий opt/ находится рядом с install.sh"
    exit 1
fi

# Установка прав
echo "Установка прав..."
chmod +x /opt/bin/vpn-routes.sh
chmod +x /opt/etc/init.d/S99vpn-routes

# Настройка cron
echo "Настройка cron..."
if [ -f /opt/etc/crontab ]; then
    # Удаляем старую запись если есть
    sed -i '/vpn-routes/d' /opt/etc/crontab 2>/dev/null || true
fi
# Добавляем задание
echo "0 4 * * * /opt/bin/vpn-routes.sh update >> /opt/var/log/vpn-routes.log 2>&1" >> /opt/etc/crontab

# Перезапуск cron
if [ -f /opt/etc/init.d/S10cron ]; then
    /opt/etc/init.d/S10cron restart 2>/dev/null || true
fi

echo ""
echo "=== Установка завершена ==="
echo ""
echo "Следующие шаги:"
echo ""
echo "1. Отредактируйте конфигурацию:"
echo "   nano /opt/etc/vpn-routes/config.sh"
echo ""
echo "2. Проверьте настройки:"
echo "   - ROUTES_URL - URL для получения списка"
echo "   - VPN_INTERFACE - имя VPN-интерфейса"
echo ""
echo "3. Запустите вручную для проверки:"
echo "   /opt/bin/vpn-routes.sh start"
echo ""
echo "4. Проверьте статус:"
echo "   /opt/bin/vpn-routes.sh status"
echo ""
echo "Скрипт будет автоматически запускаться:"
echo "  - При старте роутера (через S99vpn-routes)"
echo "  - Каждый день в 04:00 (через cron)"
echo ""
