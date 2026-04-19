#!/bin/bash

# Script para enviar notificações via Telegram

# Carrega configuração de arquivo separado se existir
CONFIG_FILE="$(dirname "$0")/telegram-config.sh"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  MP_BOT_TOKEN="<SEU_BOT_TOKEN>"
  TELEGRAM_CHAT_ID="<SEU_CHAT_ID>"
fi

# Verifica configuração
check_config() {
  if [ -z "$MP_BOT_TOKEN" ] || [ "$MP_BOT_TOKEN" == "<SEU_BOT_TOKEN>" ]; then
    echo "Erro: MP_BOT_TOKEN não configurado." >&2
    exit 1
  fi
  if [ -z "$TELEGRAM_CHAT_ID" ] || [ "$TELEGRAM_CHAT_ID" == "<SEU_CHAT_ID>" ]; then
    echo "Erro: TELEGRAM_CHAT_ID não configurado." >&2
    exit 1
  fi
}

# Envia mensagem de texto simples
send_message() {
  local message="$1"
  local url="https://api.telegram.org/bot${MP_BOT_TOKEN}/sendMessage"

  # Usa JSON para evitar problemas de encoding com acentos, &, +, etc.
  local payload
  payload=$(jq -n \
    --arg chat_id "$TELEGRAM_CHAT_ID" \
    --arg text "$message" \
    '{chat_id: $chat_id, text: $text, parse_mode: "HTML"}')

  curl -s -X POST "$url" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null
}

# Envia foto com caption (poster + mensagem numa única notificação)
send_photo() {
  local poster_url="$1"
  local caption="$2"
  local url="https://api.telegram.org/bot${MP_BOT_TOKEN}/sendPhoto"

  # Telegram limita caption a 1024 caracteres
  caption="${caption:0:1024}"

  local payload
  payload=$(jq -n \
    --arg chat_id "$TELEGRAM_CHAT_ID" \
    --arg photo "$poster_url" \
    --arg caption "$caption" \
    '{chat_id: $chat_id, photo: $photo, caption: $caption, parse_mode: "HTML"}')

  local response
  response=$(curl -s -X POST "$url" \
    -H "Content-Type: application/json" \
    -d "$payload")

  # Verifica se o envio do poster funcionou
  local ok
  ok=$(echo "$response" | jq -r '.ok')
  if [ "$ok" != "true" ]; then
    local error
    error=$(echo "$response" | jq -r '.description')
    echo "Aviso: falha ao enviar poster ($error), enviando só texto..." >&2
    send_message "$caption"
  fi
}

# Função principal de notificação
post_telegram() {
  local message="$1"
  local poster_url="$2"
  local overview="$3"

  # Adiciona sinopse à mensagem se disponível
  if [ -n "$overview" ]; then
    message="${message}

📖 <b>Sinopse:</b> ${overview}"
  fi

  if [ -n "$poster_url" ]; then
    send_photo "$poster_url" "$message"
  else
    send_message "$message"
  fi
}

# --- Execução ---

check_config

case "$1" in
  --message)
    shift
    message=""
    poster_url=""
    overview=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --message) shift; message="$1"; shift ;;
        -p)        shift; poster_url="$1"; shift ;;
        -o)        shift; overview="$1"; shift ;;
        *)         message="$1"; shift ;;
      esac
    done

    post_telegram "$message" "$poster_url" "$overview"
    ;;

  --setup)
    echo "Configuração do Telegram:"
    echo "1. Crie um bot com @BotFather e copie o token"
    echo "2. Envie uma mensagem para o bot e acesse:"
    echo "   https://api.telegram.org/bot<SEU_TOKEN>/getUpdates"
    echo "3. Copie o 'id' dentro de 'chat' — esse é seu CHAT_ID"
    echo "4. Crie o arquivo telegram-config.sh com:"
    echo "   MP_BOT_TOKEN=\"seu_token\""
    echo "   TELEGRAM_CHAT_ID=\"seu_chat_id\""
    ;;

  *)
    echo "Uso: $0 --message \"texto\" [-p <poster_url>] [-o \"sinopse\"]"
    echo "     $0 --setup"
    exit 1
    ;;
esac

exit 0
