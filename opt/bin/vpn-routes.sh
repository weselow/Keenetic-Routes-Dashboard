#!/bin/sh
# VPN Routes - Автоматическая маршрутизация через VPN
# Версия: 1.0
# Для Keenetic с Entware

PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

set -e

# Путь к конфигурации
CONFIG_FILE="/opt/etc/vpn-routes/config.sh"

# Загрузка конфигурации
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "ОШИБКА: Файл конфигурации не найден: $CONFIG_FILE"
        exit 1
    fi
    . "$CONFIG_FILE"
}

# Логирование с timestamp (логи по дням)
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_date=$(date '+%Y-%m-%d')
    local log_line="[$timestamp] [$level] $message"

    # Вывод в stderr чтобы не мешать возврату значений из функций
    echo "$log_line" >&2

    # Запись в файл с датой
    if [ -n "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        local log_file="$LOG_DIR/vpn-routes.$log_date.log"
        echo "$log_line" >> "$log_file"
    fi
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_debug() {
    if [ "$VERBOSE" = "1" ]; then
        log "DEBUG" "$@"
    fi
}

# Проверка зависимостей
check_deps() {
    log_info "Проверка зависимостей..."
    local missing=""

    for cmd in curl ipset iptables ip; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        log_error "Отсутствуют команды:$missing"
        log_error "Установите: opkg install ipset iptables curl ca-certificates"
        return 1
    fi

    log_debug "Все зависимости найдены"
    return 0
}

# Проверка наличия VPN интерфейса
check_interface() {
    log_debug "Проверка интерфейса $VPN_INTERFACE..."

    if ! ip link show "$VPN_INTERFACE" >/dev/null 2>&1; then
        log_error "Интерфейс $VPN_INTERFACE не найден"
        log_error "Проверьте, что VPN подключение активно"
        return 1
    fi

    log_debug "Интерфейс $VPN_INTERFACE найден"
    return 0
}

# Конвертация маски в CIDR нотацию
mask_to_cidr() {
    local mask="$1"
    local cidr=0
    local IFS='.'

    for octet in $mask; do
        case $octet in
            255) cidr=$((cidr + 8));;
            254) cidr=$((cidr + 7));;
            252) cidr=$((cidr + 6));;
            248) cidr=$((cidr + 5));;
            240) cidr=$((cidr + 4));;
            224) cidr=$((cidr + 3));;
            192) cidr=$((cidr + 2));;
            128) cidr=$((cidr + 1));;
            0)   ;;
            *)   log_error "Некорректная маска: $mask"; return 1;;
        esac
    done

    echo "$cidr"
}

# Скачивание списка маршрутов
fetch_routes() {
    log_info "Скачивание списка маршрутов..."
    log_debug "URL: $ROUTES_URL"

    local temp_file="/tmp/vpn-routes-download.tmp"

    if curl -g -s --connect-timeout "$CURL_TIMEOUT" -o "$temp_file" "$ROUTES_URL"; then
        local count=$(wc -l < "$temp_file" 2>/dev/null || echo 0)
        log_info "Получено $count строк"

        if [ "$count" -eq 0 ]; then
            log_error "Получен пустой ответ"
            rm -f "$temp_file"
            return 1
        fi

        echo "$temp_file"
        return 0
    else
        log_error "Ошибка скачивания"
        rm -f "$temp_file"
        return 1
    fi
}

# Парсинг и конвертация маршрутов
parse_routes() {
    local input_file="$1"
    local output_file="$2"

    log_info "Парсинг маршрутов..."

    local count=0
    local errors=0

    # Очистка выходного файла
    > "$output_file"

    while IFS= read -r line; do
        # Пропуск пустых строк и комментариев
        case "$line" in
            ""|\#*|REM*|rem*) continue;;
        esac

        # Парсинг: route add IP mask MASK GATEWAY
        # Пример: route add 1.0.0.0 mask 255.128.0.0 0.0.0.0
        if echo "$line" | grep -qi "^route add"; then
            local ip=$(echo "$line" | awk '{print $3}')
            local mask=$(echo "$line" | awk '{print $5}')

            # Валидация IP
            if ! echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                log_debug "Пропуск некорректной строки: $line"
                errors=$((errors + 1))
                continue
            fi

            # Конвертация маски в CIDR
            local cidr=$(mask_to_cidr "$mask")
            if [ -z "$cidr" ]; then
                errors=$((errors + 1))
                continue
            fi

            echo "$ip/$cidr" >> "$output_file"
            count=$((count + 1))
        fi
    done < "$input_file"

    log_info "Обработано $count маршрутов, ошибок: $errors"

    if [ "$count" -eq 0 ]; then
        log_error "Не найдено ни одного валидного маршрута"
        return 1
    fi

    return 0
}

# Создание ipset
create_ipset() {
    log_info "Создание ipset $IPSET_NAME..."

    # Удаление старого ipset если существует
    if ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        log_debug "Удаление старого ipset"
        ipset flush "$IPSET_NAME"
        ipset destroy "$IPSET_NAME"
    fi

    # Создание нового ipset типа hash:net
    if ! ipset create "$IPSET_NAME" hash:net hashsize 4096 maxelem 65536; then
        log_error "Не удалось создать ipset"
        return 1
    fi

    log_debug "ipset создан"
    return 0
}

# Заполнение ipset
fill_ipset() {
    local routes_file="$1"

    log_info "Заполнение ipset..."

    local count=0
    local errors=0

    while IFS= read -r cidr; do
        if [ -n "$cidr" ]; then
            if ipset add "$IPSET_NAME" "$cidr" 2>/dev/null; then
                count=$((count + 1))
            else
                errors=$((errors + 1))
                log_debug "Не удалось добавить: $cidr"
            fi
        fi
    done < "$routes_file"

    log_info "Добавлено в ipset: $count записей, ошибок: $errors"
    return 0
}

# Настройка iptables правил
setup_iptables() {
    log_info "Настройка iptables..."

    # Проверяем, не установлено ли уже правило
    if iptables -t mangle -C PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null; then
        log_debug "Правило iptables уже существует"
        return 0
    fi

    # Добавляем правило маркировки
    if ! iptables -t mangle -A PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK"; then
        log_error "Не удалось добавить правило iptables"
        return 1
    fi

    # Также маркируем локально-сгенерированный трафик
    if ! iptables -t mangle -C OUTPUT -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null; then
        iptables -t mangle -A OUTPUT -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK"
    fi

    log_debug "Правила iptables добавлены"
    return 0
}

# Удаление iptables правил
cleanup_iptables() {
    log_info "Удаление правил iptables..."

    # Удаление правила PREROUTING
    while iptables -t mangle -D PREROUTING -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null; do
        :
    done

    # Удаление правила OUTPUT
    while iptables -t mangle -D OUTPUT -m set --match-set "$IPSET_NAME" dst -j MARK --set-mark "$FWMARK" 2>/dev/null; do
        :
    done

    log_debug "Правила iptables удалены"
    return 0
}

# Настройка policy routing
setup_routing() {
    log_info "Настройка policy routing..."

    # Добавляем правило ip rule
    if ! ip rule show | grep -q "fwmark $FWMARK lookup $ROUTE_TABLE"; then
        if ! ip rule add fwmark "$FWMARK" table "$ROUTE_TABLE" priority 100; then
            log_error "Не удалось добавить ip rule"
            return 1
        fi
        log_debug "ip rule добавлено"
    else
        log_debug "ip rule уже существует"
    fi

    # Добавляем маршрут по умолчанию в таблицу
    if ! ip route show table "$ROUTE_TABLE" | grep -q "default"; then
        if ! ip route add default dev "$VPN_INTERFACE" table "$ROUTE_TABLE"; then
            log_error "Не удалось добавить маршрут в таблицу $ROUTE_TABLE"
            return 1
        fi
        log_debug "Маршрут добавлен в таблицу $ROUTE_TABLE"
    else
        log_debug "Маршрут в таблице $ROUTE_TABLE уже существует"
    fi

    return 0
}

# Удаление policy routing
cleanup_routing() {
    log_info "Удаление policy routing..."

    # Удаление ip rule
    while ip rule del fwmark "$FWMARK" table "$ROUTE_TABLE" 2>/dev/null; do
        :
    done

    # Очистка таблицы маршрутизации
    ip route flush table "$ROUTE_TABLE" 2>/dev/null || true

    log_debug "Policy routing удалён"
    return 0
}

# Очистка ipset
cleanup_ipset() {
    log_info "Очистка ipset..."

    if ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        ipset flush "$IPSET_NAME"
        ipset destroy "$IPSET_NAME"
        log_debug "ipset удалён"
    else
        log_debug "ipset не существует"
    fi

    return 0
}

# Полная очистка
cleanup_all() {
    log_info "Полная очистка..."
    cleanup_iptables
    cleanup_routing
    cleanup_ipset
    log_info "Очистка завершена"
}

# Обновление маршрутов
do_update() {
    log_info "=== Начало обновления маршрутов ==="

    # Проверка зависимостей
    if ! check_deps; then
        return 1
    fi

    # Проверка интерфейса
    if ! check_interface; then
        return 1
    fi

    # Скачивание
    local temp_file=$(fetch_routes)
    if [ -z "$temp_file" ]; then
        log_error "Использую кэшированный список"
        if [ -f "$ROUTES_CACHE" ]; then
            temp_file="$ROUTES_CACHE"
        else
            log_error "Кэш не найден. Обновление невозможно."
            return 1
        fi
    fi

    # Парсинг
    local parsed_file="/tmp/vpn-routes-parsed.tmp"
    if ! parse_routes "$temp_file" "$parsed_file"; then
        rm -f "$temp_file" "$parsed_file"
        return 1
    fi

    # Сохранение в кэш
    cp "$parsed_file" "$ROUTES_CACHE"

    # Очистка старых правил (кроме iptables, т.к. ipset будет пересоздан)
    cleanup_routing
    cleanup_ipset

    # Создание и заполнение ipset
    if ! create_ipset; then
        rm -f "$temp_file" "$parsed_file"
        return 1
    fi

    if ! fill_ipset "$parsed_file"; then
        rm -f "$temp_file" "$parsed_file"
        return 1
    fi

    # Настройка iptables
    if ! setup_iptables; then
        rm -f "$temp_file" "$parsed_file"
        return 1
    fi

    # Настройка routing
    if ! setup_routing; then
        rm -f "$temp_file" "$parsed_file"
        return 1
    fi

    # Очистка временных файлов
    rm -f "$temp_file" "$parsed_file"

    log_info "=== Обновление завершено успешно ==="
    return 0
}

# Показать статус
do_status() {
    echo "=== VPN Routes Status ==="
    echo ""

    echo "--- Конфигурация ---"
    echo "URL: $ROUTES_URL"
    echo "Интерфейс: $VPN_INTERFACE"
    echo "ipset: $IPSET_NAME"
    echo "Таблица: $ROUTE_TABLE"
    echo "Метка: $FWMARK"
    echo ""

    echo "--- Интерфейс ---"
    if ip link show "$VPN_INTERFACE" >/dev/null 2>&1; then
        echo "Статус: АКТИВЕН"
        ip addr show "$VPN_INTERFACE" | grep -E "inet|state"
    else
        echo "Статус: НЕ НАЙДЕН"
    fi
    echo ""

    echo "--- ipset ---"
    if ipset list "$IPSET_NAME" >/dev/null 2>&1; then
        local count=$(ipset list "$IPSET_NAME" | grep -c "^[0-9]" || echo 0)
        echo "Статус: АКТИВЕН"
        echo "Записей: $count"
    else
        echo "Статус: НЕ СОЗДАН"
    fi
    echo ""

    echo "--- iptables (mangle) ---"
    if iptables -t mangle -L PREROUTING -n 2>/dev/null | grep -q "$IPSET_NAME"; then
        echo "Правило PREROUTING: УСТАНОВЛЕНО"
    else
        echo "Правило PREROUTING: НЕ УСТАНОВЛЕНО"
    fi
    if iptables -t mangle -L OUTPUT -n 2>/dev/null | grep -q "$IPSET_NAME"; then
        echo "Правило OUTPUT: УСТАНОВЛЕНО"
    else
        echo "Правило OUTPUT: НЕ УСТАНОВЛЕНО"
    fi
    echo ""

    echo "--- ip rule ---"
    if ip rule show | grep -q "fwmark $FWMARK"; then
        echo "Правило: УСТАНОВЛЕНО"
        ip rule show | grep "fwmark $FWMARK"
    else
        echo "Правило: НЕ УСТАНОВЛЕНО"
    fi
    echo ""

    echo "--- ip route (table $ROUTE_TABLE) ---"
    if ip route show table "$ROUTE_TABLE" 2>/dev/null | grep -q .; then
        ip route show table "$ROUTE_TABLE"
    else
        echo "Таблица пуста или не существует"
    fi
    echo ""

    echo "--- Кэш маршрутов ---"
    if [ -f "$ROUTES_CACHE" ]; then
        local cache_count=$(wc -l < "$ROUTES_CACHE")
        local cache_date=$(date -r "$ROUTES_CACHE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || stat -c %y "$ROUTES_CACHE" 2>/dev/null | cut -d. -f1)
        echo "Файл: $ROUTES_CACHE"
        echo "Записей: $cache_count"
        echo "Обновлён: $cache_date"
    else
        echo "Кэш не найден"
    fi
}

# Справка
show_help() {
    echo "VPN Routes - Маршрутизация трафика через VPN"
    echo ""
    echo "Использование: $0 <команда>"
    echo ""
    echo "Команды:"
    echo "  start    - Запустить (обновить и применить маршруты)"
    echo "  stop     - Остановить (удалить все правила)"
    echo "  restart  - Перезапустить"
    echo "  update   - Обновить маршруты"
    echo "  status   - Показать статус"
    echo "  help     - Показать справку"
    echo ""
    echo "Конфигурация: $CONFIG_FILE"
}

# Точка входа
main() {
    load_config

    case "${1:-}" in
        start|update)
            do_update
            ;;
        stop)
            cleanup_all
            ;;
        restart)
            cleanup_all
            do_update
            ;;
        status)
            do_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Неизвестная команда: ${1:-}"
            echo "Используйте: $0 help"
            exit 1
            ;;
    esac
}

main "$@"
