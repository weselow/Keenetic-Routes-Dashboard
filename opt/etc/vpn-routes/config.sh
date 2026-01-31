#!/bin/sh
# VPN Routes - Конфигурация
# Редактируйте этот файл под свои нужды

# URL для получения списка маршрутов
# Формат ответа: Windows BAT (route add X.X.X.X mask Y.Y.Y.Y 0.0.0.0)
ROUTES_URL="https://iplist.opencck.org/?format=bat&data=cidr4&site=whatsapp.com"

# Имя VPN-интерфейса (WireGuard)
# Укажите имя интерфейса из вывода: ip link show | grep nwg
VPN_INTERFACE="<VPN_INTERFACE>"

# Имя ipset для хранения подсетей
IPSET_NAME="vpn_routes"

# Метка для маркировки пакетов (hex)
FWMARK="0x1"

# Номер таблицы маршрутизации
ROUTE_TABLE="100"

# Файл для кэша маршрутов
ROUTES_CACHE="/opt/etc/vpn-routes/routes.list"

# Директория для логов (логи по дням: vpn-routes.YYYY-MM-DD.log)
LOG_DIR="/opt/var/log/vpn-routes"

# Хранить логи за последние N дней
LOG_RETENTION_DAYS=7

# Таймаут для curl (секунды)
CURL_TIMEOUT=30

# Включить подробное логирование (1 = да, 0 = нет)
VERBOSE=1
