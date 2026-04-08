#!/bin/bash

# Script para ser usado como "Executar programa externo" no qBittorrent

# Configurações (altere se necessário)
MEDIA_PROCESSOR_SCRIPT="/PATH/TO/media-processor/scripts/media-processor-cli.sh"
DOWNLOAD_PATH="$TORRENT_PATH"
LOG_DIR="/var/log/media-processor/"
LOG_FILE="${LOG_DIR}/qbittorrent-hook.log"

# Log de entrada
{
  echo "$(date +%Y-%m-%d\ %H:%M:%S) Hook acionado"
  echo "  TORRENT_PATH=$TORRENT_PATH"
  echo "  TORRENT_NAME=$TORRENT_NAME"
  echo "  TORRENT_CATEGORY=$TORRENT_CATEGORY"
  echo "  TORRENT_TAGS=$TORRENT_TAGS"
  echo "  TORRENT_HASH=$TORRENT_HASH"
  echo "  TORRENT_CONTENT_PATH=$TORRENT_CONTENT_PATH"
  echo "  TORRENT_ROOT_PATH=$TORRENT_ROOT_PATH"
} >> "$LOG_FILE"

# Verifica se o script media-processor-cli.sh existe e é executável
if [ ! -x "$MEDIA_PROCESSOR_SCRIPT" ]; then
  echo "Erro: Script media-processor-cli.sh não encontrado ou não executável." >> "$LOG_FILE"
  exit 1
fi

# Verifica se $TORRENT_PATH está definida (necessário)
if [ -z "$TORRENT_PATH" ]; then
  echo "Erro: Variável TORRENT_PATH não definida." >> "$LOG_FILE"
  exit 1
fi

# Verifica se o caminho contém "incomplete" (arquivo ainda sendo baixado)
if echo "$TORRENT_PATH" | grep -q "incomplete"; then
  echo "AVISO: Arquivo ainda na pasta incomplete - $TORRENT_PATH" >> "$LOG_FILE"
  echo "  Aguardando download completo antes de processar..." >> "$LOG_FILE"
  exit 0
fi

# Verifica se o arquivo existe
if [ ! -e "$DOWNLOAD_PATH" ]; then
  echo "AVISO: Arquivo não encontrado - $DOWNLOAD_PATH" >> "$LOG_FILE"
  echo "  Pode estar na pasta incomplete?" >> "$LOG_FILE"
  exit 0
fi

# Executa o script media-processor-cli.sh para processar o arquivo
# usando --process para um único arquivo.
{
  echo "$(date +%Y-%m-%d\ %H:%M:%S) Iniciando processamento: $TORRENT_PATH"
  $MEDIA_PROCESSOR_SCRIPT --process "$DOWNLOAD_PATH" 2>&1
} >> "$LOG_FILE" &

echo "Script executado em background para processamento: $TORRENT_PATH" >> "$LOG_FILE"

exit 0
