#!/bin/bash

# Roda no HOST — processa o conteúdo baixado pelo qBittorrent
# Chamado pelo queue-processor.sh

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_FILE="${SCRIPT_DIR}/telegram-config.sh"

if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "Erro: telegram-config.sh não encontrado." >&2
  exit 1
fi

CONVERTER_SCRIPT="${SCRIPT_DIR}/converter_mp4.sh"
FETCH_MEDIA_SCRIPT="${SCRIPT_DIR}/fetch-media-info.sh"
TELEGRAM_NOTIFIER_SCRIPT="${SCRIPT_DIR}/telegram-notifier.sh"
JELLYFIN_FILMES_DIR="${JELLYFIN_MEDIA_DIR%/}/Filmes"
LOG_DIR="/var/log/media-processor"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"

mkdir -p "$LOG_DIR" "$JELLYFIN_FILMES_DIR"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" | tee -a "$LOG_FILE"
}

notify() {
  local filename="$1"
  local jellyfin_path="$2"

  [ ! -x "$TELEGRAM_NOTIFIER_SCRIPT" ] && return 0

  local file_size
  file_size="$(du -h "$jellyfin_path" 2>/dev/null | cut -f1 || echo "N/A")"

  local poster_url="" overview="" titulo=""

  if [ -x "$FETCH_MEDIA_SCRIPT" ]; then
    local media_info
    media_info=$("$FETCH_MEDIA_SCRIPT" "$filename" 2>/dev/null | grep '^{')
    if [ -n "$media_info" ]; then
      poster_url=$(echo "$media_info" | jq -r '.poster // ""')
      overview=$(echo "$media_info"   | jq -r '.sinopse // ""')
      titulo=$(echo "$media_info"     | jq -r '.titulo // ""')
    fi
  fi

  local message
  message=$(printf "✅ <b>Novo filme disponível</b>\n\n🎬 <b>Título:</b> %s\n📁 <b>Arquivo:</b> %s\n💾 <b>Tamanho:</b> %s" \
    "${titulo:-não identificado}" \
    "$filename" \
    "$file_size")

  "$TELEGRAM_NOTIFIER_SCRIPT" --message "$message" -p "$poster_url" -o "$overview"
}

qbt_delete() {
  local hash="$1"
  [ -z "$hash" ] && return 0

  local cookie
  cookie=$(curl -s -c -     --data "username=${QB_USER}&password=${QB_PASS}"     "${QB_URL}/api/v2/auth/login" | grep SID | awk '{print "SID="$NF}')

  if [ -z "$cookie" ]; then
    log ERRO "Falha ao autenticar no qBittorrent para deletar torrent"
    return 1
  fi

  curl -s -b "$cookie" -X POST     --data "hashes=${hash}&deleteFiles=true"     "${QB_URL}/api/v2/torrents/delete" > /dev/null

  log INFO "Torrent deletado do qBittorrent (hash: ${hash})"
}

process_file() {
  local file="$1"
  local filename
  filename="$(basename "$file")"
  local ext="${filename##*.}"
  ext="${ext,,}"

  log INFO "Processando: $filename"

  local dest_mp4="${JELLYFIN_FILMES_DIR}/${filename%.*}.mp4"

  if [ -f "$dest_mp4" ]; then
    log INFO "Já existe no Jellyfin, ignorando: $filename"
    return 0
  fi

  if [ "$ext" = "mkv" ]; then
    log INFO "Convertendo MKV: $filename"
    if "$CONVERTER_SCRIPT" --path "$file"; then
      local mp4_file="${file%.*}.mp4"
      if [ -f "$mp4_file" ]; then
        mv "$mp4_file" "$JELLYFIN_FILMES_DIR/"
        log INFO "Movido para Jellyfin: $(basename "$mp4_file")"
        notify "$filename" "${JELLYFIN_FILMES_DIR}/$(basename "$mp4_file")"
      else
        log ERRO "MP4 não encontrado após conversão: $mp4_file"
        return 1
      fi
    else
      log ERRO "Falha na conversão: $filename"
      return 1
    fi

  elif [ "$ext" = "mp4" ]; then
    local codec
    codec=$(ffprobe -v error -select_streams a:0 \
      -show_entries stream=codec_name \
      -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    codec="${codec,,}"

    if [ "$codec" != "aac" ]; then
      log INFO "Convertendo áudio ($codec → AAC): $filename"
      local tmp="${file%.*}_aac.mp4"
      if ffmpeg -hide_banner -loglevel error -stats \
          -i "$file" \
          -map 0:v -c:v copy \
          -map 0:a -c:a aac -b:a 192k -ac 2 \
          -map 0:s? -c:s mov_text \
          -movflags +faststart \
          "$tmp" 2>>"${LOG_DIR}/ffmpeg.log"; then
        mv "$tmp" "$dest_mp4"
      else
        log ERRO "Falha na conversão de áudio: $filename"
        rm -f "$tmp"
        return 1
      fi
    else
      cp "$file" "$dest_mp4"
    fi

    log INFO "Movido para Jellyfin: $(basename "$dest_mp4")"
    notify "$filename" "$dest_mp4"

  else
    log INFO "Extensão não suportada, ignorando: $filename"
  fi
}

# ── Entry point ───────────────────────────────────────────────────────────────

CONTENT_PATH="$1"
TORRENT_HASH="$2"

if [ -z "$CONTENT_PATH" ]; then
  echo "Uso: $0 <caminho> [hash]"
  exit 1
fi

log INFO "=== Iniciando: $CONTENT_PATH ==="

PROCESSED=0
FAILED=0

if [ -f "$CONTENT_PATH" ]; then
  if process_file "$CONTENT_PATH"; then
    PROCESSED=$((PROCESSED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
elif [ -d "$CONTENT_PATH" ]; then
  log INFO "Pasta detectada, buscando vídeos..."
  while IFS= read -r -d $'\0' file; do
    if process_file "$file"; then
      PROCESSED=$((PROCESSED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
  done < <(find "$CONTENT_PATH" -type f \( -iname "*.mkv" -o -iname "*.mp4" \) -print0)
else
  log ERRO "Caminho não encontrado: $CONTENT_PATH"
  exit 1
fi

log INFO "=== Concluído — OK: $PROCESSED | Falhas: $FAILED ==="

# Deleta o torrent do qBittorrent apenas se tudo foi processado com sucesso
if [ "$FAILED" -eq 0 ] && [ "$PROCESSED" -gt 0 ]; then
  qbt_delete "$TORRENT_HASH"
else
  log INFO "Torrent mantido no qBittorrent devido a falhas no processamento"
fi
