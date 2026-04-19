#!/bin/bash

# Hook chamado pelo qBittorrent (dentro do Docker)
# Configurar em: Opções → Downloads → Programa externo ao concluir:
# /scripts/qbittorrent-hook.sh "%F" "%I"

QUEUE_DIR="/scripts/queue"
mkdir -p "$QUEUE_DIR"

CONTENT_PATH="$1"
TORRENT_HASH="$2"

if [ -z "$CONTENT_PATH" ]; then
  echo "Uso: $0 <caminho> <hash>"
  exit 1
fi

JOB_FILE="${QUEUE_DIR}/$(date +%s%N).job"

# Converte caminho interno do container para caminho do host
HOST_PATH=$(echo "$CONTENT_PATH" | sed 's|^/downloads|/mnt/media/qbittorrent/downloads|')

# Salva caminho e hash no job
echo "PATH=${HOST_PATH}" > "$JOB_FILE"
echo "HASH=${TORRENT_HASH}" >> "$JOB_FILE"

echo "Job enfileirado: $JOB_FILE"
