#!/bin/bash

# Bot Telegram para download de filmes e séries via qBittorrent + Jackett

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

# Estados:
#   idle
#   waiting_choice:filme:<query>
#   waiting_choice:serie:<query>

get_state() {
  local state_file="${STATE_DIR}/$1.state"
  [ -f "$state_file" ] && cat "$state_file" || echo "idle"
}

set_state() {
  echo "$2" > "${STATE_DIR}/$1.state"
}

clear_state() {
  rm -f "${STATE_DIR}/$1.state" "${STATE_DIR}/$1.results"
}

# ── Handlers ──────────────────────────────────────────────────────────────────

handle_search() {
  local chat_id="$1"
  local query="$2"
  local type="$3"
  local category="$4"

  tg_send "$chat_id" "🔎 Buscando <b>${type}</b>: <b>${query}</b>..."

  local state_file="${STATE_DIR}/${chat_id}.results"

  # Salva saída em arquivo temporário para preservar newlines corretamente
  local tmp_output
  tmp_output=$(mktemp)
  "$TORRENT_SCRIPT" --search "$query" "$category" "$state_file" > "$tmp_output" 2>/dev/null

  if grep -q "^NONE$" "$tmp_output" || [ ! -s "$tmp_output" ]; then
    tg_send "$chat_id" "❌ Nenhum resultado encontrado para: <b>${query}</b>"
    rm -f "$tmp_output"
    clear_state "$chat_id"
    return
  fi

  set_state "$chat_id" "waiting_choice:${type}:${query}"

  # Envia cabeçalho
  local header
  header=$(grep "^HEADER:" "$tmp_output" | sed "s/^HEADER://")
  tg_send "$chat_id" "$header"

  # Constrói blocos de resultados respeitando o limite de 3800 chars
  local block=""
  local MAX_LEN=3800

  while IFS= read -r line; do
    [[ "$line" == HEADER:* ]] && continue
    [[ "$line" == FOOTER:* ]] && continue
    [[ -z "$line" ]] && continue

    local entry="${line#RESULT:}"

    if [ $(( ${#block} + ${#entry} + 2 )) -gt $MAX_LEN ]; then
      tg_send "$chat_id" "$block"
      block="$entry"
    else
      if [ -z "$block" ]; then
        block="$entry"
      else
        block="${block}
${entry}"
      fi
    fi
  done < "$tmp_output"

  # Envia bloco restante
  [ -n "$block" ] && tg_send "$chat_id" "$block"

  # Envia rodapé
  local footer
  footer=$(grep "^FOOTER:" "$tmp_output" | sed "s/^FOOTER://")
  tg_send "$chat_id" "$footer"

  rm -f "$tmp_output"
}


handle_choice() {
  local chat_id="$1"
  local choice="$2"
  local state_file="${STATE_DIR}/${chat_id}.results"

  local state
  state=$(get_state "$chat_id")

  # Extrai tipo do estado: waiting_choice:filme:... ou waiting_choice:serie:...
  local type
  type=$(echo "$state" | cut -d':' -f2)
  local category="filmes"
  [ "$type" = "serie" ] && category="series"

  local result
  result=$("$TORRENT_SCRIPT" --add "$state_file" "$choice" "$category" 2>/dev/null)

  case "$result" in
    OK:*)
      local titulo="${result#OK:}"
      local emoji="🎬"
      [ "$type" = "serie" ] && emoji="📺"
      tg_send "$chat_id" "${emoji} Download iniciado: <b>${titulo}</b>
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

  # Verifica autorização
  if [ "$chat_id" != "$MP_CHAT_ID" ]; then
    tg_send "$chat_id" "⛔ Acesso não autorizado."
    return
  fi

  # Estado: aguardando escolha numérica
  if [[ "$state" == waiting_choice:* ]]; then
    if [[ "$text" =~ ^[0-9]+$ ]]; then
      handle_choice "$chat_id" "$text"
      return
    fi
    # Novo texto enquanto aguardava — cancela e reprocessa
    clear_state "$chat_id"
  fi

  # Comandos
  case "$text" in
    /filme\ *|/filme)
      local query="${text#/filme}"
      query="${query# }"
      if [ -z "$query" ]; then
        tg_send "$chat_id" "ℹ️ Use: /filme <b>título do filme</b>"
      else
        handle_search "$chat_id" "$query" "filme" "2000"
      fi
      ;;
    /serie\ *|/serie\ *|/série\ *|/série)
      local query="${text#/serie }"
      query="${query#/série }"
      query="${query# }"
      if [ -z "$query" ]; then
        tg_send "$chat_id" "ℹ️ Use: /serie <b>título da série</b>"
      else
        handle_search "$chat_id" "$query" "serie" "5000"
      fi
      ;;
    /cancelar)
      clear_state "$chat_id"
      tg_send "$chat_id" "🚫 Operação cancelada."
      ;;
    /status)
      local cookie
      cookie=$(curl -s -c - \
        --data "username=${QB_USER}&password=${QB_PASS}" \
        "${QB_URL}/api/v2/auth/login" 2>/dev/null | grep SID | awk '{print "SID="$NF}')

      local torrents
      torrents=$(curl -s -b "$cookie" \
        "${QB_URL}/api/v2/torrents/info?filter=downloading" 2>/dev/null | \
        jq -r '.[] | "• \(.name) (\( .progress * 100 | floor )%)"' 2>/dev/null | head -10)

      if [ -n "$torrents" ]; then
        tg_send "$chat_id" "📥 <b>Downloads em andamento:</b>

${torrents}"
      else
        tg_send "$chat_id" "✅ Nenhum download em andamento."
      fi
      ;;
    /ajuda|/help|/start)
      tg_send "$chat_id" "🎬 <b>Media Processor Bot</b>

<b>Comandos:</b>

/filme <i>título</i> — Busca e baixa um filme
/serie <i>título</i> — Busca e baixa uma série
/status — Downloads em andamento
/cancelar — Cancela a operação atual

<b>Exemplos:</b>
/filme Inception 2010
/serie Breaking Bad
/serie The Last of Us S02"
      ;;
    *)
      tg_send "$chat_id" "❓ Comando não reconhecido. Use /ajuda."
      ;;
  esac
}

# ── Loop principal ────────────────────────────────────────────────────────────

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

log "Bot iniciado. Aguardando mensagens..."

offset=0
[ -f "$OFFSET_FILE" ] && offset=$(cat "$OFFSET_FILE")

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
      log "[$chat_id] $text"
      handle_message "$chat_id" "$text"
    fi

    offset=$((update_id + 1))
    echo "$offset" > "$OFFSET_FILE"
  done

  [ "$count" -eq 0 ] && sleep 2
done
