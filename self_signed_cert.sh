#!/bin/bash

# Функция для ожидания нажатия Enter
wait_for_enter() {
    echo -e "\nНажмите [Enter], чтобы продолжить..."
    read -r
}

# Безопасная очистка экрана: не падает при неизвестном TERM
safe_clear() {
    if [ -n "${TERM:-}" ] && command -v clear >/dev/null 2>&1; then
        clear || true
    else
        printf "\033c"
    fi
}

# Извлечение данных панели из БД и лога, с безопасными значениями по умолчанию
extract_panel_data() {
    local db_path="$1"
    local log_file="$2"

    USER_EXT=""
    PASS_EXT=""
    PORT_EXT=""
    PATH_EXT=""

    if [ -f "$db_path" ]; then
        USER_EXT=$(sqlite3 "$db_path" "SELECT value FROM settings WHERE key='username';" 2>/dev/null)
        PASS_EXT=$(sqlite3 "$db_path" "SELECT value FROM settings WHERE key='password';" 2>/dev/null)
        PORT_EXT=$(sqlite3 "$db_path" "SELECT value FROM settings WHERE key='port';" 2>/dev/null)
        PATH_EXT=$(sqlite3 "$db_path" "SELECT value FROM settings WHERE key='webBasePath';" 2>/dev/null)
    fi

    if [[ -z "$USER_EXT" ]] && [ -f "$log_file" ]; then
        USER_EXT=$(grep "Username:" "$log_file" | tail -1 | awk '{print $NF}' | tr -d '\r')
    fi
    if [[ -z "$PASS_EXT" ]] && [ -f "$log_file" ]; then
        PASS_EXT=$(grep "Password:" "$log_file" | tail -1 | awk '{print $NF}' | tr -d '\r')
    fi
    if [[ ! "$PORT_EXT" =~ ^[0-9]+$ ]] && [ -f "$log_file" ]; then
        PORT_EXT=$(grep -E "Port:[[:space:]]+[0-9]+" "$log_file" | tail -1 | awk '{print $NF}' | tr -d '\r')
    fi
    if [[ -z "$PATH_EXT" ]] && [ -f "$log_file" ]; then
        PATH_EXT=$(grep "WebBasePath:" "$log_file" | tail -1 | awk '{print $NF}' | tr -d '\r')
    fi

    USER_EXT="${USER_EXT:-admin}"
    PASS_EXT="${PASS_EXT:-not-found}"
    PORT_EXT="${PORT_EXT:-2053}"
    PATH_EXT="${PATH_EXT:-/}"
}

# 1. Проверка на root
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo!"
  exit 1
fi

# 2. Обновление системы и базовые зависимости
echo "--- Обновление системы и установка базовых пакетов ---"
sudo apt update && sudo apt install -y git curl openssl qrencode systemd && rm -rf ~/self-signed-cert-script-by-antenka

# 3. Проверка на уже установленную панель
if [ -f "/usr/local/x-ui/x-ui" ]; then
DB_PATH="/etc/x-ui/x-ui.db"
extract_panel_data "$DB_PATH" "/tmp/3x_ui_install.log"
IP_EXT=$(curl -s ifconfig.me)
PATH_CLEAN=$(echo "$PATH_EXT" | tr -d '"/' )
if [[ -z "$PATH_CLEAN" ]]; then
    URL_EXT="https://${IP_EXT}:${PORT_EXT}/"
else
    URL_EXT="https://${IP_EXT}:${PORT_EXT}/${PATH_CLEAN}/"
fi
safe_clear
echo "═══════════════════════════════════════════════════════════"
echo "         УСТАНОВКА ЗАВЕРШЕНА! ДАННЫЕ ДЛЯ ВХОДА:            "
echo "═══════════════════════════════════════════════════════════"
echo "Username: ${USER_EXT}"
echo "Password: ${PASS_EXT}"
echo "Port: ${PORT_EXT}"
if [[ -z "$PATH_CLEAN" ]]; then
    echo "WebBasePath: /"
else
    echo "WebBasePath: /${PATH_CLEAN}/"
fi
echo "URL: ${URL_EXT}"
echo "═══════════════════════════════════════════════════════════"
echo -e "\e[1;33m⚠️  ОБЯЗАТЕЛЬНО СОХРАНИТЕ ЭТИ ДАННЫЕ!\e[0m"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo -e "\e[1;36mℹ️  ИНФОРМАЦИЯ О СЕРТИФИКАТАХ:\e[0m"
echo -e "В новой сборке скрипта сертификаты на 10 лет \e[1mне выпускаются\e[0m."
echo "Они автоматически генерируются самой панелью на 6 дней"
echo "и затем автоматически продлеваются каждые 6 дней."
echo ""
echo "Ничего вручную прописывать не нужно — сертификаты"
echo "уже автоматически прописаны в саму панель."
echo ""
echo -e "\e[1;32m✅ Можно сразу приступать к настройке соединения!\e[0m"
echo "═══════════════════════════════════════════════════════════"
echo ""
    exit 0
fi

# 4. Установка зависимостей
echo "--- Подготовка системы (sqlite3, expect) ---"
apt-get update && apt-get install -y expect curl sqlite3
sleep 1

echo "--- Запуск установки 3x-ui ---"
LOG_FILE="/tmp/3x_ui_install.log"
> "$LOG_FILE"

# 5. Установка через Expect (имитация ручного ввода с паузами)
expect <<EOF | tee "$LOG_FILE"
set timeout -1
spawn bash -c "curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh | bash"

expect {
    -re "(?i)Confirm the installation.*" {
        sleep 1
        send "y\r"
        exp_continue
    }
    -re "(?i)customize the Panel Port settings.*" {
        sleep 1
        send "n\r"
        exp_continue
    }
    -re "(?i)Choose an option.*" {
        sleep 1
        send "2\r"
        exp_continue
    }
    -re "(?i)Port to use for ACME.*" {
        sleep 1
        send "\r"
        exp_continue
    }
    eof
}
EOF

echo -e "\n--- Обработка данных (пауза 2 сек) ---"
sleep 2

# --- ИЗВЛЕЧЕНИЕ ДАННЫХ (БАЗА ДАННЫХ + ЛОГ) ---
DB_PATH="/etc/x-ui/x-ui.db"
extract_panel_data "$DB_PATH" "$LOG_FILE"

# Формирование ссылки
IP_EXT=$(curl -s ifconfig.me)
PATH_CLEAN=$(echo "$PATH_EXT" | tr -d '"/' )
if [[ -z "$PATH_CLEAN" ]]; then
    URL_EXT="https://${IP_EXT}:${PORT_EXT}/"
else
    URL_EXT="https://${IP_EXT}:${PORT_EXT}/${PATH_CLEAN}/"
fi

rm -f $LOG_FILE

# --- ВЫВОД ДАННЫХ ПАНЕЛИ ---
safe_clear
echo "═══════════════════════════════════════════════════════════"
echo "         УСТАНОВКА ЗАВЕРШЕНА! ДАННЫЕ ДЛЯ ВХОДА:            "
echo "═══════════════════════════════════════════════════════════"
echo "Username: ${USER_EXT}"
echo "Password: ${PASS_EXT}"
echo "Port: ${PORT_EXT}"
if [[ -z "$PATH_CLEAN" ]]; then
    echo "WebBasePath: /"
else
    echo "WebBasePath: /${PATH_CLEAN}/"
fi
echo "URL: ${URL_EXT}"
echo "═══════════════════════════════════════════════════════════"
echo -e "\e[1;33m⚠️  ОБЯЗАТЕЛЬНО СОХРАНИТЕ ЭТИ ДАННЫЕ!\e[0m"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo -e "\e[1;36mℹ️  ИНФОРМАЦИЯ О СЕРТИФИКАТАХ:\e[0m"
echo -e "В новой сборке скрипта сертификаты на 10 лет \e[1mне выпускаются\e[0m."
echo "Они автоматически генерируются самой панелью на 6 дней"
echo "и затем автоматически продлеваются каждые 6 дней."
echo ""
echo "Ничего вручную прописывать не нужно — сертификаты"
echo "уже автоматически прописаны в саму панель."
echo ""
echo -e "\e[1;32m✅ Можно сразу приступать к настройке соединения!\e[0m"
echo "═══════════════════════════════════════════════════════════"
echo ""

wait_for_enter

echo -e "\nСкрипт полностью завершил работу. Удачи!"
echo -e "\nСкрипт полностью завершил работу. Удачи!"
