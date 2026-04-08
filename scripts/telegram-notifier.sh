#!/bin/bash

# Script para enviar notificações via Telegram usando webhook

# Tenta carregar configuração de arquivo separado
CONFIG_FILE="$(dirname "$0")/telegram-config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Configurações padrão (substituir)
    TELEGRAM_BOT_TOKEN="<SEU_BOT_TOKEN>"  # Substitua pelo seu token do bot
    TELEGRAM_CHAT_ID="<SEU_CHAT_ID>"      # Substitua pelo ID do seu chat
fi

# Funções
post_telegram() {
  local message="$1"
  local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
  local params="chat_id=${TELEGRAM_CHAT_ID}&parse_mode=html&text=$(echo "$message" | sed 's/\"/"/g')"

  curl -s -X POST "$url" -d "$params"
}

# Verifica se o bot token e chat ID foram definidos
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ "$TELEGRAM_BOT_TOKEN" == "<SEU_BOT_TOKEN>" ]; then
  echo "Erro: TELEGRAM_BOT_TOKEN não configurado. Edite o script ou crie telegram-config.sh." >&2
  exit 1
fi

if [ -z "$TELEGRAM_CHAT_ID" ] || [ "$TELEGRAM_CHAT_ID" == "<SEU_CHAT_ID>" ]; then
  echo "Erro: TELEGRAM_CHAT_ID não configurado. Edite o script ou crie telegram-config.sh." >&2
  exit 1
fi

# Envia a mensagem
if [ -n "$1" ] && [[ "$1" == --message* ]]; then
    message="$(echo "$@" | sed 's/^--message //')"
    post_telegram "$message"

elif [[ "$1" == --setup ]]; then
  echo "Configuração do Telegram iniciada:"
  echo "1. Crie um bot no Telegram com @BotFather" 
  echo "2. Pegue o seu 'bot token' (ex: 1234567890:ABCdefghIJklMNOPqrSTuvWXyz)"
  echo "3. Descubra seu chat ID enviando uma mensagem para seu bot e veja no site: https://api.telegram.org/bot<SEU_BOT_TOKEN>/getUpdates" 
  echo "4. Crie um arquivo telegram-config.sh baseado em telegram-config-example.sh e adicione suas credenciais"
  echo "5. Ou edite este script diretamente (não recomendado para compartilhamento)"
  echo ""
  echo "Arquivo de exemplo criado: telegram-config-example.sh"

else
    echo "Uso: $0 --message \"mensagem\"" 
    echo "  --setup = Mostra o passo a passo de configuração" 
fi
exit 0
