#!/usr/bin/env bash
# Обновляет маршруты (.bat) и списки доменов (.domains.txt) с iplist.opencck.org
# Использование: ./update.sh
set -euo pipefail

cd "$(dirname "$0")"
BASE="https://iplist.opencck.org/"

declare -A sites=(
  [youtube]="youtube.com"
  [telegram]="telegram.org"
  [instagram]="instagram.com"
  [facebook]="facebook.com"
)

route_re='^route add ([0-9]{1,3}\.){3}[0-9]{1,3} mask ([0-9]{1,3}\.){3}[0-9]{1,3} 0\.0\.0\.0$'
domain_re='^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
# сервис иногда отдаёт в «домены» внутренние зоны Google и обрезанные CNAME-цепочки
tld_deny='\.(google|googlevideo|internal|local|lan|home)$'

# --- Статические маршруты (IPv4, формат Keenetic .bat) ---
for name in "${!sites[@]}"; do
  site="${sites[$name]}"
  tmp="$(mktemp)"
  curl -fsS "${BASE}?format=bat&site=${site}&data=cidr4" -o "$tmp"

  # валидация: каждая непустая строка должна быть корректным route add
  if grep -vE "$route_re" "$tmp" | grep -q .; then
    echo "ОШИБКА: неожиданный ответ для $site (routes), файл не перезаписан" >&2
    rm -f "$tmp"
    continue
  fi

  mv "$tmp" "$name.bat"
  chmod 644 "$name.bat"   # mktemp создаёт 600 — файл должен читаться/раздаваться
  printf '%-14s -> %4s маршрутов\n' "$name.bat" "$(grep -c '^route add' "$name.bat")"
done

# --- Списки доменов (KeeneticOS 5.0+, «Маршруты по DNS») ---
for name in "${!sites[@]}"; do
  site="${sites[$name]}"
  tmp="$(mktemp)"
  curl -fsS "${BASE}?format=wildcard&site=${site}&data=domains" -o "$tmp"

  out="$(mktemp)"
  tr -s '[:space:]' '\n' < "$tmp" | tr -d '\r' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr 'A-Z' 'a-z' \
    | grep -E "$domain_re" | grep -v -- '---' | grep -vE "$tld_deny" \
    | awk 'length($0) <= 253' | sort -u > "$out"
  rm -f "$tmp"

  if [ ! -s "$out" ]; then
    echo "ОШИБКА: пустой ответ для $site (domains), файл не перезаписан" >&2
    rm -f "$out"
    continue
  fi

  mv "$out" "$name.domains.txt"
  chmod 644 "$name.domains.txt"
  printf '%-20s -> %4s доменов\n' "$name.domains.txt" "$(wc -l < "$name.domains.txt")"
done

cat youtube.domains.txt telegram.domains.txt instagram.domains.txt facebook.domains.txt | sort -u > all.domains.txt
chmod 644 all.domains.txt
printf '%-20s -> %4s доменов\n' all.domains.txt "$(wc -l < all.domains.txt)"