#!/bin/bash

# Configurações
QB_DOWNLOADS_DIR='/mnt/media/qbittorrent/downloads/'
CONVERTER_SCRIPT="$(dirname "$0")/converter_mp4.sh"
JELLYFIN_MEDIA_DIR='/mnt/media/jellyfin/media/'
TELEGRAM_NOTIFIER_SCRIPT='scripts/telegram-notifier.sh'
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

# Função para verificar codec de áudio
get_audio_codec() {
  local file="$1"
  # Usa ffprobe para extrair o codec do primeiro stream de áudio
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "unknown"
}

# Função para verificar se precisa converter áudio
needs_audio_conversion() {
  local file="$1"
  local codec=$(get_audio_codec "$file")
  
  # Se não conseguir detectar o codec, assume que precisa converter por segurança
  if [[ "$codec" == "unknown" ]] || [[ -z "$codec" ]]; then
    log INFO "Não foi possível detectar codec de áudio em: $(basename "$file")"
    return 0  # Precisa converter
  fi
  
  # Converte para lowercase para comparação
  codec=$(echo "$codec" | tr '[:upper:]' '[:lower:]')
  
  # Se for AAC, não precisa converter
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
  
  # Remove barras extras e cria caminho limpo
  local jellyfin_dir="${JELLYFIN_MEDIA_DIR%/}/Filmes/"
  
  # Cria diretório se não existir
  mkdir -p "$jellyfin_dir"
  
  # Move para o Jellyfin
  mv "$mp4_file" "$jellyfin_dir"
  if [ $? -eq 0 ]; then
    log INFO "Movido para Jellyfin: $mp4_file -> $jellyfin_dir"

    # Notifica via Telegram
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
  
  # Verifica se o arquivo MP4 já existe localmente e está completo
  if [ -f "$mp4_file" ]; then
    local mp4_size=$(stat -c%s "$mp4_file" 2>/dev/null || echo 0)
    local mkv_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    
    # Verifica se o MP4 tem tamanho razoável (pelo menos 10% do MKV ou 100MB)
    local min_size=$((mkv_size / 10))
    if [ "$min_size" -lt 100000000 ]; then
      min_size=100000000  # Pelo menos 100MB
    fi
    
    if [ "$mp4_size" -gt "$min_size" ]; then
      log INFO "Arquivo MP4 já existe e parece completo: $mp4_file (${mp4_size} bytes)"
      move_to_jellyfin "$mp4_file" "$filename"
      return 0
    else
      log INFO "Arquivo MP4 existe mas parece incompleto (${mp4_size} bytes < ${min_size} bytes), reconvertendo..."
      # Remove o arquivo MP4 incompleto
      rm -f "$mp4_file"
    fi
  fi
  
  # Marcar como em processamento
  mark_processing "$file"
  
  # Converte para MP4
  log INFO "Iniciando conversão: $filename"
  
  # Usar converter_mp4.sh diretamente
  if $CONVERTER_SCRIPT --path "$file"; then
    log INFO "Conversão concluída: $filename"
    
    # Remover marcação de processamento
    unmark_processing "$file"
    
    # Aguarda para garantir que o arquivo foi escrito
    sleep 2
    
    # Verifica se o arquivo MP4 foi criado
    if [ -f "$mp4_file" ]; then
      local mp4_size=$(stat -c%s "$mp4_file" 2>/dev/null || echo 0)
      local mkv_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
      
      # Verifica tamanho mínimo
      local min_size=$((mkv_size / 10))
      if [ "$min_size" -lt 100000000 ]; then
        min_size=100000000
      fi
      
      if [ "$mp4_size" -gt "$min_size" ]; then
        log INFO "Conversão bem-sucedida: $filename (${mp4_size} bytes)"
        move_to_jellyfin "$mp4_file" "$filename"
        # Remove o MKV original após sucesso
        rm -f "$file"
        return 0
      else
        log ERRO "Arquivo MP4 incompleto: ${mp4_size} bytes"
        rm -f "$mp4_file"
        unmark_processing "$file"
        return 1
      fi
    else
      log ERRO "Arquivo MP4 não criado: $mp4_file"
      unmark_processing "$file"
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
  
  # Verificar se precisa converter o áudio
  if needs_audio_conversion "$file"; then
    log INFO "Convertendo áudio para AAC: $filename"
    
    # Marcar como em processamento
    mark_processing "$file"
    
    # Converter apenas o áudio
    if ffmpeg -hide_banner -loglevel error -stats -i "$file" \
        -map 0:v -c:v copy \
        -map 0:a -c:a aac -b:a 192k -ac 2 \
        -map 0:s? -c:s copy \
        -movflags +faststart \
        "$output_file" 2>>"${LOG_DIR}/ffmpeg_audio.log"; then
      
      log INFO "Conversão de áudio concluída: $filename"
      
      # Verificar tamanho
      if [ -f "$output_file" ]; then
        local orig_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        local conv_size=$(stat -c%s "$output_file" 2>/dev/null || echo 0)
        
        if [ "$conv_size" -gt $((orig_size * 80 / 100)) ]; then
          # Substituir original pelo convertido
          mv "$output_file" "$file"
          log INFO "Arquivo MP4 atualizado com áudio AAC"
        else
          log ERRO "Arquivo convertido muito pequeno"
          rm -f "$output_file"
          unmark_processing "$file"
          return 1
        fi
      fi
      
      unmark_processing "$file"
    else
      log ERRO "Falha na conversão de áudio: $filename"
      unmark_processing "$file"
      return 1
    fi
  else
    log INFO "Áudio já é AAC, não precisa converter: $filename"
  fi
  
  # Mover para Jellyfin
  move_to_jellyfin "$file" "$filename"
  return 0
}

# Função principal para processar arquivos
process_file() {
  local file="$1"
  local filename="$(basename "$file")"
  local extension="${filename##*.}"
  extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
  
  # Verificar se está na pasta incomplete (download em andamento)
  if echo "$file" | grep -q "incomplete"; then
    log INFO "Arquivo na pasta incomplete (download em andamento), ignorando: $filename"
    return 0
  fi
  
  # Verificar se já está em processamento
  if is_processing "$file"; then
    log INFO "Arquivo já está em processamento, ignorando: $filename"
    return 0
  fi
  
  # Verificar se já existe no Jellyfin
  local filename_only="$(basename "${file%.*}")"
  local jellyfin_path="${JELLYFIN_MEDIA_DIR%/}/Filmes/${filename_only}.mp4"
  if [ -f "$jellyfin_path" ]; then
    local jellyfin_size=$(stat -c%s "$jellyfin_path" 2>/dev/null || echo 0)
    local file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    
    local min_size=$((file_size / 10))
    if [ "$min_size" -lt 100000000 ]; then
      min_size=100000000
    fi
    
    if [ "$jellyfin_size" -gt "$min_size" ]; then
      log INFO "Arquivo já existe no Jellyfin (${jellyfin_size} bytes), ignorando: $filename"
      return 0
    else
      log INFO "Arquivo no Jellyfin incompleto (${jellyfin_size} bytes), processando..."
      rm -f "$jellyfin_path"
    fi
  fi
  
  # Processar de acordo com a extensão
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
    # Exclui arquivos na pasta incomplete - arquivos ainda sendo baixados
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