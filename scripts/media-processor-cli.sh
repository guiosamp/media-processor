#!/bin/bash

# Configurações
QB_DOWNLOADS_DIR='/mnt/media/qbittorrent/downloads/'
CONVERTER_SCRIPT="$(dirname "$0")/converter_mp4.sh"
JELLYFIN_MEDIA_DIR='/mnt/media/jellyfin/media/'
TELEGRAM_NOTIFIER_SCRIPT="$(dirname "$0")/telegram-notifier.sh"
LOG_DIR='/var/log/media-processor/'
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
PROCESSING_DIR="${LOG_DIR}/processing"

# Criar diretório de processamento se não existir
mkdir -p "$PROCESSING_DIR"

# Funções de log
log() {
  local level="$1"
  shift
  local msg="$*"
  echo "$(date +%Y-%m-%d\ %H:%M:%S) [${level}] ${msg}" >> "$LOG_FILE"
}

# Funções de controle de processamento
is_processing() {
  local file="$1"
  local lock_file="${PROCESSING_DIR}/$(basename "$file").lock"
  [ -f "$lock_file" ] && return 0
  return 1
}

mark_processing() {
  local file="$1"
  local lock_file="${PROCESSING_DIR}/$(basename "$file").lock"
  echo "$(date)" > "$lock_file"
  log INFO "Marcado como em processamento: $(basename "$file")"
}

unmark_processing() {
  local file="$1"
  local lock_file="${PROCESSING_DIR}/$(basename "$file").lock"
  rm -f "$lock_file"
  log INFO "Removido marcação de processamento: $(basename "$file")"
}

# Limpar locks antigos (mais de 24 horas)
clean_old_locks() {
  find "$PROCESSING_DIR" -name "*.lock" -mtime +1 -delete 2>/dev/null
}

# Apaga a pasta de origem após processamento bem-sucedido.
# Só executa se a pasta for uma subpasta de QB_DOWNLOADS_DIR,
# nunca a raiz de downloads em si.
cleanup_source_dir() {
  local file="$1"
  local dirpath="$(realpath "$(dirname "$file")")"
  local downloads_root="$(realpath "${QB_DOWNLOADS_DIR%/}")"

  # Garante que é uma subpasta, não a raiz
  if [[ "$dirpath" == "$downloads_root" ]]; then
    log INFO "Arquivo estava na raiz de downloads, nenhuma pasta para apagar: $dirpath"
    return 0
  fi

  if [[ "$dirpath" == "$downloads_root"/* ]]; then
    log INFO "Apagando pasta de origem: $dirpath"
    rm -rf "$dirpath"
    if [ $? -eq 0 ]; then
      log INFO "Pasta apagada com sucesso: $dirpath"
    else
      log ERRO "Falha ao apagar pasta: $dirpath"
    fi
  else
    log ERRO "Pasta fora de QB_DOWNLOADS_DIR, abortando limpeza por segurança: $dirpath"
  fi
}

# Função para verificar codec de áudio
get_audio_codec() {
  local file="$1"
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "unknown"
}

# Função para verificar se precisa converter áudio
needs_audio_conversion() {
  local file="$1"
  local codec=$(get_audio_codec "$file")

  if [[ "$codec" == "unknown" ]] || [[ -z "$codec" ]]; then
    log INFO "Não foi possível detectar codec de áudio em: $(basename "$file")"
    return 0  # Precisa converter
  fi

  codec=$(echo "$codec" | tr '[:upper:]' '[:lower:]')

  if [[ "$codec" == "aac" ]]; then
    log INFO "Codec de áudio já é AAC em: $(basename "$file")"
    return 1  # Não precisa converter
  else
    log INFO "Codec de áudio é '$codec' (não AAC) em: $(basename "$file")"
    return 0  # Precisa converter
  fi
}

# Função para mover arquivo para Jellyfin
move_to_jellyfin() {
  local mp4_file="$1"
  local filename="$2"
  local jellyfin_dir="${JELLYFIN_MEDIA_DIR%/}/Filmes/"

  mkdir -p "$jellyfin_dir"

  mv "$mp4_file" "$jellyfin_dir"
  if [ $? -eq 0 ]; then
    log INFO "Movido para Jellyfin: $mp4_file -> $jellyfin_dir"

    if [ -x "$TELEGRAM_NOTIFIER_SCRIPT" ]; then
      local final_path="${jellyfin_dir}$(basename "$mp4_file")"
      local file_size="$(du -h "$final_path" 2>/dev/null | cut -f1 || echo "N/A")"
      "$TELEGRAM_NOTIFIER_SCRIPT" --message "✅ Processamento concluído

Arquivo: $filename
Convertido: Sim ✅
Movido para: $jellyfin_dir
Tamanho: $file_size"
    fi
  else
    log ERRO "Falha ao mover para Jellyfin: $mp4_file"
    if [ -x "$TELEGRAM_NOTIFIER_SCRIPT" ]; then
      "$TELEGRAM_NOTIFIER_SCRIPT" --message "❌ Falha ao mover para Jellyfin: $filename"
    fi
  fi
}

# Função para processar arquivos MKV
process_mkv() {
  local file="$1"
  local filename="$(basename "$file")"
  local filebase="${filename%.*}"
  local dirpath="$(dirname "$file")"
  local mp4_file="${dirpath}/${filebase}.mp4"

  log INFO "Processando arquivo MKV: $filename"

  # Se o MP4 já existe localmente, vai direto para o Jellyfin
  if [ -f "$mp4_file" ]; then
    log INFO "Arquivo MP4 já existe, movendo para Jellyfin: $mp4_file"
    move_to_jellyfin "$mp4_file" "$filename"
    cleanup_source_dir "$file"
    return 0
  fi

  mark_processing "$file"
  log INFO "Iniciando conversão: $filename"

  if $CONVERTER_SCRIPT --path "$file"; then
    log INFO "Conversão concluída: $filename"
    unmark_processing "$file"
    sleep 2

    if [ -f "$mp4_file" ]; then
      log INFO "Conversão bem-sucedida: $filename"
      move_to_jellyfin "$mp4_file" "$filename"
      cleanup_source_dir "$file"
      return 0
    else
      log ERRO "Arquivo MP4 não encontrado após conversão: $mp4_file"
      return 1
    fi
  else
    log ERRO "Falha na conversão: $filename"
    unmark_processing "$file"
    return 1
  fi
}

# Função para processar arquivos MP4
process_mp4() {
  local file="$1"
  local filename="$(basename "$file")"
  local filebase="${filename%.*}"
  local dirpath="$(dirname "$file")"
  local output_file="${dirpath}/${filebase}_converted.mp4"

  log INFO "Processando arquivo MP4: $filename"

  if needs_audio_conversion "$file"; then
    log INFO "Convertendo áudio para AAC: $filename"
    mark_processing "$file"

    if ffmpeg -hide_banner -loglevel error -stats -i "$file" \
        -map 0:v -c:v copy \
        -map 0:a -c:a aac -b:a 192k -ac 2 \
        -map 0:s? -c:s copy \
        -movflags +faststart \
        "$output_file" 2>>"${LOG_DIR}/ffmpeg_audio.log"; then

      log INFO "Conversão de áudio concluída: $filename"
      mv "$output_file" "$file"
      log INFO "Arquivo MP4 atualizado com áudio AAC"
      unmark_processing "$file"
    else
      log ERRO "Falha na conversão de áudio: $filename"
      rm -f "$output_file"
      unmark_processing "$file"
      return 1
    fi
  else
    log INFO "Áudio já é AAC, não precisa converter: $filename"
  fi

  move_to_jellyfin "$file" "$filename"
  cleanup_source_dir "$file"
  return 0
}

# Função principal para processar arquivos
process_file() {
  local file="$1"
  local filename="$(basename "$file")"
  local extension="${filename##*.}"
  extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')

  # Ignorar arquivos ainda sendo baixados
  if echo "$file" | grep -q "incomplete"; then
    log INFO "Arquivo na pasta incomplete (download em andamento), ignorando: $filename"
    return 0
  fi

  # Ignorar se já está em processamento
  if is_processing "$file"; then
    log INFO "Arquivo já está em processamento, ignorando: $filename"
    return 0
  fi

  # Ignorar se já existe no Jellyfin
  local filename_only="$(basename "${file%.*}")"
  local jellyfin_path="${JELLYFIN_MEDIA_DIR%/}/Filmes/${filename_only}.mp4"
  if [ -f "$jellyfin_path" ]; then
    log INFO "Arquivo já existe no Jellyfin, ignorando: $filename"
    return 0
  fi

  if [[ "$extension" == "mkv" ]]; then
    process_mkv "$file"
  elif [[ "$extension" == "mp4" ]]; then
    process_mp4 "$file"
  else
    log INFO "Extensão não suportada: $extension, ignorando: $filename"
    return 0
  fi
}

# Monitoramento contínuo
if [[ "$1" == "--monitor" ]]; then
  log INFO "Iniciando monitoramento..."
  clean_old_locks

  while true; do
    find "$QB_DOWNLOADS_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" \) ! -path "*/incomplete/*" -print0 | while IFS= read -r -d $'\0' file; do
      process_file "$file"
    done
    sleep 60
  done
fi

# Processamento manual
if [[ "$1" == "--process" ]]; then
  if [ -z "$2" ]; then
    echo "Erro: Especifique o arquivo para processar"
    echo "Uso: $0 --process <arquivo>"
    exit 1
  fi
  process_file "$2"
fi

# Ajuda
if [ $# -eq 0 ]; then
  echo "Uso: $0 [--monitor] [--process <arquivo>]"
  echo "  --monitor  Monitora a pasta e processa arquivos .mkv e .mp4"
  echo "  --process  Processa um arquivo manualmente"
fi
