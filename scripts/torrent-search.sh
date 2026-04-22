#!/bin/bash

# Busca torrents via Jackett e envia para qBittorrent

CONFIG_FILE="$(dirname "$0")/config.sh"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "Erro: config.sh não encontrado." >&2
  exit 1
fi

# ── Funções qBittorrent ───────────────────────────────────────────────────────

qbt_login() {
  QB_COOKIE=$(curl -s -c - \
    --data "username=${QB_USER}&password=${QB_PASS}" \
    "${QB_URL}/api/v2/auth/login" | grep SID | awk '{print "SID="$NF}')

  if [ -z "$QB_COOKIE" ]; then
    echo "Erro: falha ao autenticar no qBittorrent." >&2
    return 1
  fi
}

qbt_add_torrent() {
  local magnet="$1"
  local category="$2"

  qbt_login || return 1

  local result
  result=$(curl -s -b "$QB_COOKIE" \
    --data-urlencode "urls=$magnet" \
    --data "category=$category" \
    --data "savepath=${QB_SAVE_PATH}" \
    --data "autoTMM=false" \
    --data "contentLayout=Original" \
    "${QB_URL}/api/v2/torrents/add")

  [ "$result" == "Ok." ] && return 0 || return 1
}

# ── Funções Jackett ───────────────────────────────────────────────────────────

jackett_search() {
  local query="$1"
  local category="$2"

  local encoded_query
  encoded_query=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query")

  local url="${JACKETT_URL}/api/v2.0/indexers/all/results"
  url+="?apikey=${JACKETT_API_KEY}&Query=${encoded_query}&Category[]=${category}"

  curl -s "$url"
}

format_size() {
  local bytes="$1"
  if [ -z "$bytes" ] || [ "$bytes" == "null" ]; then
    echo "N/A"
    return
  fi
  local gb=$((bytes / 1073741824))
  local mb=$((bytes / 1048576))
  if [ "$gb" -gt 0 ]; then
    echo "${gb}.$(( (bytes % 1073741824) / 107374182 ))GB"
  else
    echo "${mb}MB"
  fi
}

# ── Execução ──────────────────────────────────────────────────────────────────

COMMAND="$1"
shift

case "$COMMAND" in
  --search)
    QUERY="$1"
    CATEGORY="${2:-2000}"
    STATE_FILE="${3:-/tmp/mp_pending_$$}"

    if [ -z "$QUERY" ]; then
      echo "Uso: $0 --search <título> [categoria] [state_file]" >&2
      exit 1
    fi

    response=$(jackett_search "$QUERY" "$CATEGORY")

    total=$(echo "$response" | jq '.Results | length' 2>/dev/null)
    if [ -z "$total" ] || [ "$total" -eq 0 ]; then
      echo "NONE"
      exit 0
    fi

    # Todos os resultados com MagnetUri, ordenados por seeders
    results=$(echo "$response" | jq '[
      .Results[] |
      select(.MagnetUri != null and .MagnetUri != "") |
      {
        titulo: .Title,
        tamanho: .Size,
        seeders: .Seeders,
        tracker: .TrackerId,
        magnet: .MagnetUri
      }
    ] | sort_by(-.seeders)')

    count=$(echo "$results" | jq 'length')
    if [ "$count" -eq 0 ]; then
      echo "NONE"
      exit 0
    fi

    # Salva todos os resultados no state file
    echo "$results" > "$STATE_FILE"

    # Formata e imprime cada resultado separado por marcador
    # O telegram-bot.sh lê esses blocos e envia em múltiplas mensagens
    echo "HEADER:🔍 <b>Resultados para:</b> ${QUERY} (${count} encontrados)"

    for i in $(seq 0 $((count - 1))); do
      titulo=$(echo "$results"  | jq -r ".[$i].titulo")
      tamanho=$(format_size "$(echo "$results" | jq -r ".[$i].tamanho")")
      seeders=$(echo "$results" | jq -r ".[$i].seeders")
      tracker=$(echo "$results" | jq -r ".[$i].tracker")
      num=$((i + 1))
      echo "RESULT:${num}. <b>${titulo}</b>"
      echo "RESULT:   📦 ${tamanho} | 🌱 ${seeders} seeders | 📡 ${tracker}"
    done

    echo "FOOTER:Responda com o <b>número</b> desejado ou <b>0</b> para cancelar."
    ;;

  --add)
    STATE_FILE="$1"
    CHOICE="$2"
    CATEGORY="${3:-filmes}"

    if [ -z "$STATE_FILE" ] || [ -z "$CHOICE" ]; then
      echo "Uso: $0 --add <state_file> <número> [categoria]" >&2
      exit 1
    fi

    if [ ! -f "$STATE_FILE" ]; then
      echo "Erro: state_file não encontrado." >&2
      exit 1
    fi

    if [ "$CHOICE" -eq 0 ]; then
      rm -f "$STATE_FILE"
      echo "CANCELLED"
      exit 0
    fi

    idx=$((CHOICE - 1))
    count=$(jq 'length' "$STATE_FILE")

    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
      echo "INVALID"
      exit 1
    fi

    titulo=$(jq -r ".[$idx].titulo" "$STATE_FILE")
    magnet=$(jq -r ".[$idx].magnet" "$STATE_FILE")
    rm -f "$STATE_FILE"

    if qbt_add_torrent "$magnet" "$CATEGORY"; then
      echo "OK:$titulo"
    else
      echo "ERROR"
    fi
    ;;

  *)
    echo "Uso: $0 --search <título> [categoria] [state_file]"
    echo "     $0 --add <state_file> <número> [categoria]"
    exit 1
    ;;
esac
