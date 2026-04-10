#!/bin/bash

# Template de configuração do Telegram
# Copie este arquivo para telegram-config.sh e preencha com suas credenciais

# Token do bot do Telegram (obtenha com @BotFather)
export TELEGRAM_BOT_TOKEN="SEU_BOT_TOKEN_AQUI"

# ID do chat do Telegram (obtenha enviando mensagem para seu bot e verificando em https://api.telegram.org/bot<TOKEN>/getUpdates)
export TELEGRAM_CHAT_ID="SEU_CHAT_ID_AQUI"

# TMDB
export TMDB_API_KEY="SUA_API_TMDB"
export TMDB_BASE_URL="https://api.themoviedb.org/3"
export TMDB_POSTER_URL="https://image.tmdb.org/t/p/w500"

# Para usar:
# 1. Copie este arquivo: cp telegram-config-example.sh telegram-config.sh
# 2. Edite com suas credenciais: nano telegram-config.sh
# 3. Carregue as variáveis: source telegram-config.sh
# 4. Execute o notificador normalmente

echo "Configuração do Telegram carregada."
