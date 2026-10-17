#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK] $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
check "Порт отличен от 22" "true" "$([[ $(sudo sshd -T | awk '/^port/{print $2}') -ne 22 ]] && echo true || echo false)"
check "Лимит попыток maxauthtries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Входящий трафик по умолчанию deny" "deny" "$(sudo ufw status verbose | grep -o 'deny (incoming)' | awk '{print $1}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба Nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация Nginx корректна" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат валиден более 30 дней" "0" "$(openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; echo $?)"
check "Нет файлов с записью для всех и ключ 600" "0:600" "$(find /var/www/devops-site -perm -o+w | wc -l):$(sudo stat -c '%a' /etc/ssl/private/devops.key)"

echo "[5] Контейнеризация"
check "Служба docker активна" "active" "$(systemctl is-active docker)"
check "Контейнер СУБД в состоянии healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo 'not found')"
check "Порт 5000 открыт только на 127.0.0.1, а 5432 закрыт" "127.0.0.1:5000" "$(ss -tln | awk '{print $4}' | grep -E ':(5000|5432)$' | tr -d '\n')"
check "Права файла .env равны 600" "600" "$(stat -c '%a' "${HOME}/app/.env" 2>/dev/null || echo '0')"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
