#!/bin/bash

# Bot Telegram para download de filmes/séries via qBittorrent + Jackett

CONFIG_FILE="$(dirname "$0")/config.sh"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "Erro: config.sh não encontrado." >&2
  exit 1
fi

TORRENT_SCRIPT="$(dirname "$0")/torrent-search.sh"
STATE_DIR="/tmp/media-processor-bot"
OFFSET_FILE="/tmp/media-processor-bot-offset"
mkdir -p "$STATE_DIR"

# ── Telegram helpers ──────────────────────────────────────────────────────────

tg_send() {
  local chat_id="$1"
  local message="$2"

  local payload
  payload=$(jq -n \
    --arg chat_id "$chat_id" \
    --arg text "$message" \
    '{chat_id: $chat_id, text: $text, parse_mode: "HTML"}')

  curl -s -X POST \
    "https://api.telegram.org/bot${MP_BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null
}

tg_get_updates() {
  local offset="${1:-0}"
  curl -s "https://api.telegram.org/bot${MP_BOT_TOKEN}/getUpdates?offset=${offset}&timeout=30"
}

# ── Gerenciamento de estado por usuário ───────────────────────────────────────

# Estado possíveis por usuário:
#   idle                    → aguardando comando
#   waiting_choice:<query>  → busca feita, aguardando número da escolha

get_state() {
  local chat_id="$1"
  local state_file="${STATE_DIR}/${chat_id}.state"
  if [ -f "$state_file" ]; then
    cat "$state_file"
  else
    echo "idle"
  fi
}

set_state() {
  local chat_id="$1"
  local state="$2"
  echo "$state" > "${STATE_DIR}/${chat_id}.state"
}

clear_state() {
  local chat_id="$1"
  rm -f "${STATE_DIR}/${chat_id}.state"
  rm -f "${STATE_DIR}/${chat_id}.results"
}

# ── Handlers ──────────────────────────────────────────────────────────────────

handle_search() {
  local chat_id="$1"
  local query="$2"
  local category="${3:-2000}"  # 2000=filmes, 5000=séries

  tg_send "$chat_id" "🔎 Buscando: <b>${query}</b>..."

  local state_file="${STATE_DIR}/${chat_id}.results"
  local output
  output=$("$TORRENT_SCRIPT" --search "$query" "$category" "$state_file" 2>/dev/null)

  if [ "$output" == "NONE" ] || [ -z "$output" ]; then
    tg_send "$chat_id" "❌ Nenhum resultado encontrado para: <b>${query}</b>"
    clear_state "$chat_id"
    return
  fi

  set_state "$chat_id" "waiting_choice:${query}"
  tg_send "$chat_id" "$output"
}

handle_choice() {
  local chat_id="$1"
  local choice="$2"
  local state_file="${STATE_DIR}/${chat_id}.results"

  # Determina categoria pelo estado salvo
  local category="filmes"
  local state
  state=$(get_state "$chat_id")
  if echo "$state" | grep -q "series"; then
    category="series"
  fi

  local result
  result=$("$TORRENT_SCRIPT" --add "$state_file" "$choice" "$category" 2>/dev/null)

  case "$result" in
    OK:*)
      local titulo="${result#OK:}"
      tg_send "$chat_id" "✅ Download iniciado: <b>${titulo}</b>
📂 Será processado automaticamente ao concluir."
      clear_state "$chat_id"
      ;;
    CANCELLED)
      tg_send "$chat_id" "🚫 Download cancelado."
      clear_state "$chat_id"
      ;;
    INVALID)
      tg_send "$chat_id" "⚠️ Número inválido. Escolha novamente ou envie <b>0</b> para cancelar."
      ;;
    *)
      tg_send "$chat_id" "❌ Erro ao adicionar torrent. Verifique o qBittorrent."
      clear_state "$chat_id"
      ;;
  esac
}

handle_message() {
  local chat_id="$1"
  local text="$2"

  local state
  state=$(get_state "$chat_id")

  # Verifica autorização (só responde ao seu chat_id)
  if [ "$chat_id" != "$TELEGRAM_CHAT_ID" ]; then
    tg_send "$chat_id" "⛔ Acesso não autorizado."
    return
  fi

  # Estado: aguardando escolha numérica
  if [[ "$state" == waiting_choice:* ]]; then
    if [[ "$text" =~ ^[0-9]+$ ]]; then
      handle_choice "$chat_id" "$text"
      return
    fi
    # Se enviou outro texto enquanto aguardava, cancela e reprocessa
    clear_state "$chat_id"
  fi

  # Comandos
  case "$text" in
    /baixar\ *|/filme\ *)
      local query="${text#* }"
      handle_search "$chat_id" "$query" "2000"
      ;;
    /serie\ *|/série\ *)
      local query="${text#* }"
      handle_search "$chat_id" "$query" "5000"
      ;;
    /cancelar)
      clear_state "$chat_id"
      tg_send "$chat_id" "🚫 Operação cancelada."
      ;;
    /status)
      local qbt_torrents
      qbt_torrents=$(curl -s -b "$(cat ${STATE_DIR}/qbt_cookie 2>/dev/null)" \
        "${QB_URL}/api/v2/torrents/info?filter=downloading" 2>/dev/null | \
        jq -r '.[].name' 2>/dev/null | head -5)

      if [ -n "$qbt_torrents" ]; then
        tg_send "$chat_id" "📥 <b>Downloads em andamento:</b>

${qbt_torrents}"
      else
        tg_send "$chat_id" "✅ Nenhum download em andamento."
      fi
      ;;
    /ajuda|/help|/start)
      tg_send "$chat_id" "🎬 <b>Media Processor Bot</b>

<b>Comandos disponíveis:</b>

/baixar <i>título</i> — Busca e baixa um filme
/serie <i>título</i> — Busca e baixa uma série
/status — Mostra downloads em andamento
/cancelar — Cancela a operação atual

<b>Exemplo:</b>
/baixar Inception 2010
/serie Breaking Bad"
      ;;
    *)
      tg_send "$chat_id" "❓ Comando não reconhecido. Use /ajuda para ver os comandos disponíveis."
      ;;
  esac
}

# ── Loop principal ────────────────────────────────────────────────────────────

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

log "Bot iniciado. Aguardando mensagens..."

offset=0
if [ -f "$OFFSET_FILE" ]; then
  offset=$(cat "$OFFSET_FILE")
fi

while true; do
  updates=$(tg_get_updates "$offset")

  if [ -z "$updates" ] || ! echo "$updates" | jq -e '.ok' > /dev/null 2>&1; then
    sleep 5
    continue
  fi

  count=$(echo "$updates" | jq '.result | length')

  for i in $(seq 0 $((count - 1))); do
    update_id=$(echo "$updates" | jq -r ".result[$i].update_id")
    chat_id=$(echo "$updates"   | jq -r ".result[$i].message.chat.id // empty")
    text=$(echo "$updates"      | jq -r ".result[$i].message.text // empty")

    if [ -n "$chat_id" ] && [ -n "$text" ]; then
      log "Mensagem de $chat_id: $text"
      handle_message "$chat_id" "$text"
    fi

    offset=$((update_id + 1))
    echo "$offset" > "$OFFSET_FILE"
  done

  [ "$count" -eq 0 ] && sleep 2
done
