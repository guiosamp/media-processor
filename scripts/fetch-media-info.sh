#!/bin/bash

# Script para buscar informações de mídia no TMDB

# Carrega configuração de arquivo separado se existir
CONFIG_FILE="$(dirname "$0")/telegram-config.sh"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "Erro: telegram-config.sh não encontrado. Copie telegram-config-example.sh e preencha." >&2
  exit 1
fi

# Função para limpar título
# Suporta tanto separadores por ponto ("Titulo.Do.Filme.1080p")
# quanto por espaço ("Titulo Do Filme 1080p Dublado")
clean_title() {
  local title="$1"

  # Remove extensões
  title=$(echo "$title" | sed -E 's/\.(mkv|mp4|avi|mov|wmv)$//i')

  # Remove tags técnicas entre parênteses: "(1080p)", "(BluRay)", "(Dublado)", etc.
  title=$(echo "$title" | sed -E \
    's/ \(([0-9]{3,4}[pP]|2160[pP]?|4K|UHD|HDR[a-zA-Z]*|BDRip|BluRay|WEB[a-zA-Z-]*|DVDRip|DVD|REMUX|x264|x265|h264|h265|HEVC|AAC|AC3|DTS|Dublado|Legendado|DUB|LEG)[^)]*\)//gi')

  # Remove " - Qualquer coisa" no final (ex: "- The Pirate Filmes", "- WWW.SITE.COM")
  title=$(echo "$title" | sed -E 's/ - [A-Za-z].*$//i')

  # Substitui pontos por espaços (estilo "Titulo.Do.Filme")
  title=$(echo "$title" | sed 's/\./ /g')

  # Corta tudo a partir da primeira tag técnica ou domínio encontrada
  title=$(echo "$title" | sed -E \
    's/ (HDRip|HDRIP|HDR|BDRip|BluRay|Blu-Ray|WEB-?DL|WEBRip|WEB|DVDRip|DVD|REMUX|EXTENDED)( .*)?$//i;
     s/ ([0-9]{3,4}[pP]|2160[pP]?|4K|UHD)( .*)?$//i;
     s/ (x264|x265|h264|h265|HEVC|AVC)( .*)?$//i;
     s/ (AAC|AC3|DTS|MP3|OPUS|TrueHD|Atmos)( .*)?$//i;
     s/ (Dublado|Legendado|Dual Audio|DUB|LEG|PT-BR|PT|BR|EN|ENG)( .*)?$//i;
     s/ - (WWW|HTTP).*$//i;
     s/ (WWW\.[A-Za-z]|YTS|RARBG|ETRG|YIFY).*$//i')

  # Remove múltiplos espaços e espaços no início/fim
  title=$(echo "$title" | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')

  echo "$title"
}

# Função para extrair ano (de parênteses ou solto no nome)
extract_year() {
  local filename="$1"
  local year=""

  # Prefere ano entre parênteses: "(2001)"
  if [[ "$filename" =~ \(([0-9]{4})\) ]]; then
    year="${BASH_REMATCH[1]}"
  # Fallback: primeiro número de 4 dígitos que pareça um ano
  elif [[ "$filename" =~ (^|[^0-9])((19|20)[0-9]{2})([^0-9]|$) ]]; then
    year="${BASH_REMATCH[2]}"
  fi

  # Valida intervalo razoável
  if [ -n "$year" ] && { [ "$year" -lt 1900 ] || [ "$year" -gt 2030 ]; }; then
    year=""
  fi

  echo "$year"
}

# Função para codificar URL com suporte a acentos
url_encode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
}

# Faz a busca no TMDB e retorna o primeiro resultado formatado
do_search() {
  local title="$1"
  local year="$2"
  local lang="$3"

  local encoded_title
  encoded_title=$(url_encode "$title")

  local url="${TMDB_BASE_URL}/search/movie?api_key=${TMDB_API_KEY}&query=${encoded_title}&language=${lang}&include_adult=false"
  [ -n "$year" ] && url+="&year=${year}"

  local response
  response=$(curl -s "$url")

  local result
  result=$(echo "$response" | jq '.results[0] // empty' 2>/dev/null)

  if [ -n "$result" ] && [ "$result" != "null" ]; then
    local poster_path
    poster_path=$(echo "$result" | jq -r '.poster_path // ""')
    local poster_url=""
    [ -n "$poster_path" ] && [ "$poster_path" != "null" ] && poster_url="${TMDB_POSTER_URL}${poster_path}"

    echo "$result" | jq -c --arg poster_url "$poster_url" '{
      titulo: .title,
      titulo_original: .original_title,
      ano: .release_date[0:4],
      sinopse: .overview,
      poster: $poster_url,
      nota: .vote_average
    }'
    return 0
  fi

  return 1
}

# Função principal
search_tmdb() {
  local filename="$1"

  local title
  title=$(clean_title "$filename")

  local year
  year=$(extract_year "$filename")

  # Remove o ano do título limpo para não atrapalhar a busca
  if [ -n "$year" ]; then
    title=$(echo "$title" | sed "s/ *$year *//g" | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')
  fi

  if [ -n "$DEBUG" ]; then
    echo "Título limpo: '$title'" >&2
    echo "Ano: '${year:-não detectado}'" >&2
  fi

  echo "🔍 Buscando: '$title' (${year:-ano não detectado})"
  echo ""

  # Tenta pt-BR primeiro, depois en-US como fallback
  if do_search "$title" "$year" "pt-BR"; then
    return 0
  fi

  echo "⚠️  Sem resultado em pt-BR, tentando en-US..." >&2
  if do_search "$title" "$year" "en-US"; then
    return 0
  fi

  # Última tentativa: sem o ano
  if [ -n "$year" ]; then
    echo "⚠️  Tentando sem o ano..." >&2
    if do_search "$title" "" "pt-BR"; then
      return 0
    fi
  fi

  echo "❌ Nenhum resultado encontrado para: $title"
  return 1
}

# Verifica dependências
for cmd in jq curl python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Erro: '$cmd' não está instalado."
    exit 1
  fi
done

if [ -z "$1" ]; then
  echo "Uso: $0 <nome_do_arquivo>"
  echo "     DEBUG=1 $0 <nome_do_arquivo>  # mostra título e ano detectados"
  exit 1
fi

search_tmdb "$1"
