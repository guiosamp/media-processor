#!/bin/bash
# ============================================================
#  converter_mp4.sh — Converte MKV → MP4 (com ajuste de áudio)
# ============================================================

shopt -s globstar nullglob

# ── Defaults ─────────────────────────────────────────────────
OFFSET="0"
DELETE_ORIGINAL=false
LOG_FILE="/var/log/media-processor/converter_mp4.log"
BASE=""
INTERACTIVE=true

# ── Cores ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

# ── Logger ───────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${ts} [${level}] ${msg}" | tee -a "$LOG_FILE"
}

# ── Parse args ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --path)    BASE="$2";   INTERACTIVE=false; shift 2 ;;
        --offset)  OFFSET="$2"; INTERACTIVE=false; shift 2 ;;
        --delete)  DELETE_ORIGINAL=true;            shift   ;;
        --log)     LOG_FILE="$2";                   shift 2 ;;
        --help)
            echo "Uso: $0 [--path DIR_OU_ARQUIVO] [--offset SEGUNDOS] [--delete] [--log ARQUIVO]"
            echo "  --path    Diretório base ou arquivo .mkv específico"
            echo "  --offset  Offset de áudio em segundos (negativo = atrasa, positivo = adianta)"
            echo "  --delete  Apaga o .mkv original após conversão bem-sucedida"
            echo "  --log     Caminho do arquivo de log (padrão: /var/log/converter_mp4.log)"
            exit 0
            ;;
        *) echo -e "${RED}❌ Argumento desconhecido: $1${NC}"; exit 1 ;;
    esac
done

# ── Modo interativo (sem args) ───────────────────────────────
if $INTERACTIVE; then
    echo -e "${CYAN}📂 Escolha um diretório base${NC}"
    echo -e "   (use --path para modo automático)"
    read -e -p "Caminho: " BASE
    if [ -z "$BASE" ]; then
        echo -e "${RED}❌ Caminho não especificado${NC}"
        exit 1
    fi
fi

# ── Localização dos MKVs ─────────────────────────────────────
if [ -f "$BASE" ] && [[ "$BASE" == *.mkv ]]; then
    FILES=("$BASE")
elif [ -d "$BASE" ]; then
    FILES=("$BASE"/**/*.mkv)
else
    echo -e "${RED}❌ '$BASE' não é um arquivo .mkv nem um diretório${NC}"
    exit 1
fi

if [ ${#FILES[@]} -eq 0 ]; then
    log "WARN" "${YELLOW}⚠️  Nenhum arquivo .mkv encontrado em: $BASE${NC}"
    exit 0
fi

# ── Resumo ───────────────────────────────────────────────────
log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "INFO" "📂 Caminho base : $BASE"
log "INFO" "⏱️  Offset       : ${OFFSET}s"
log "INFO" "🗑️  Apagar orig. : $DELETE_ORIGINAL"
log "INFO" "📄 Arquivos     : ${#FILES[@]} .mkv encontrado(s)"
log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Contadores ───────────────────────────────────────────────
OK=0; FAIL=0; SKIP=0

# ── Loop de conversão ────────────────────────────────────────
for file in "${FILES[@]}"; do
    dir=$(dirname "$file")
    _bn=$(basename "$file"); base="${_bn%.*}"
    out="$dir/${base}.mp4"

    # Pula se o .mp4 já existir e não estiver vazio (>10MB)
    if [ -f "$out" ] && [ $(stat -c%s "$out" 2>/dev/null || echo 0) -gt 10000000 ]; then
        log "SKIP" "${YELLOW}⏭️  Já existe, pulando: $out${NC}"
        (( SKIP++ ))
        continue
    fi

    log "INFO" "🔄 Convertendo: $(basename "$file")"

    # Monta o comando ffmpeg dinamicamente
    FFMPEG_ARGS=(-fflags +genpts -hide_banner -loglevel error -stats)

    if [[ "$OFFSET" != "0" ]]; then
        FFMPEG_ARGS+=(-itsoffset "$OFFSET")
    fi

    # Comando simplificado - copia apenas vídeo e áudio, ignora legendas por enquanto
    FFMPEG_ARGS+=(
        -i "$file"
        -map 0:v -c:v copy
        -map 0:a -c:a aac -b:a 192k -ac 2
        -sn
        -movflags +faststart
        "$out"
    )

    # Executar ffmpeg e capturar PID
    log "INFO" "Executando ffmpeg..."
    ffmpeg "${FFMPEG_ARGS[@]}" 2>>"$LOG_FILE" &
    FFMPEG_PID=$!
    
    # Aguardar ffmpeg terminar completamente
    wait $FFMPEG_PID
    FFMPEG_EXIT=$?
    
    log "INFO" "ffmpeg terminou com código: $FFMPEG_EXIT"
    
    # Verificar se o arquivo foi criado (ffmpeg já verificou qualidade)
    if [ $FFMPEG_EXIT -eq 0 ] && [ -f "$out" ]; then
        chmod 755 "$out"
        log "INFO" "${GREEN}✔ Sucesso: $(basename "$out")${NC}"
        (( OK++ ))
        
        if $DELETE_ORIGINAL; then
            rm -f "$file"
            log "INFO" "🗑️  Original removido: $(basename "$file")"
        fi
    else
        log "ERROR" "${RED}❌ Falhou: $(basename "$file")${NC}"
        [ -f "$out" ] && rm -f "$out"
        (( FAIL++ ))
    fi
    
    sleep 1   # respiro entre conversões
done

# ── Relatório final ──────────────────────────────────────────
log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "INFO" "✅ Concluído — OK: $OK | Falhas: $FAIL | Pulados: $SKIP"
log "INFO" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ "$FAIL" -gt 0 ] && exit 2
exit 0
