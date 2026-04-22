#!/bin/bash

# Hook do qBittorrent (roda dentro do container Docker)
# Configurar em: Opções → Downloads → Programa externo ao concluir:
# /scripts/qbittorrent-hook.sh "%F" "%I" "%L"
#
# %F = caminho do conteúdo
# %I = info hash
# %L = categoria (filmes | series)

QUEUE_DIR="/scripts/queue"
mkdir -p "$QUEUE_DIR"

CONTENT_PATH="$1"
TORRENT_HASH="$2"
CATEGORY="${3:-filmes}"

if [ -z "$CONTENT_PATH" ]; then
  echo "Uso: $0 <caminho> <hash> [categoria]"
  exit 1
fi

JOB_FILE="${QUEUE_DIR}/$(date +%s%N).job"

# Converte caminho do container para caminho do host
HOST_PATH=$(echo "$CONTENT_PATH" | sed 's|^/downloads|/mnt/media/qbittorrent/downloads|')

echo "PATH=${HOST_PATH}"       > "$JOB_FILE"
echo "HASH=${TORRENT_HASH}"   >> "$JOB_FILE"
echo "CATEGORY=${CATEGORY}"   >> "$JOB_FILE"

echo "Job enfileirado: $JOB_FILE"
