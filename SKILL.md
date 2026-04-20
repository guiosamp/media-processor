---
name: media-processor
description: >
  Pipeline completo de automação de mídia para homelab. Processa downloads do
  qBittorrent (MKV/MP4), converte para formato compatível com SmartTVs antigas via FFmpeg,
  busca metadados no TMDB, notifica via Telegram e gerencia torrents via API.
  Inclui bot Telegram para solicitar downloads e busca via Jackett.
---

# Media Processor Skill

## Visão Geral

Esta skill automatiza o fluxo completo de mídia em um homelab Debian com Docker:

1. qBittorrent conclui o download e dispara um hook
2. O hook enfileira um job em pasta compartilhada entre container e host
3. O cron no host processa a fila, converte e move para o Jellyfin
4. O Telegram recebe notificação com poster e sinopse do filme

## Arquivos do Projeto

| Script | Onde roda | Responsabilidade |
|--------|-----------|------------------|
| `qbittorrent-hook.sh` | Container qBittorrent | Recebe `%F` e `%I`, enfileira `.job` |
| `queue-processor.sh` | Host (cron) | Lê a fila e dispara o processamento |
| `qbittorrent-hook-host.sh` | Host | Converte, move, notifica, deleta torrent |
| `converter_mp4.sh` | Host | Converte MKV → MP4 via FFmpeg |
| `fetch-media-info.sh` | Host | Busca metadados no TMDB |
| `telegram-notifier.sh` | Host | Envia mensagem/foto no Telegram |
| `telegram-bot.sh` | Host | Loop de escuta de comandos do Telegram |
| `torrent-search.sh` | Host | Busca torrents via Jackett API |
| `config.sh` | Host | Credenciais (não versionado) |

## Configuração Necessária

### Variáveis obrigatórias em `config.sh`

```bash
# Telegram
MP_BOT_TOKEN         # Token do bot de downloads (separado do OpenClaw)
MP_CHAT_ID           # ID do chat para o bot de downloads

# TMDB
TMDB_API_KEY         # Chave da API — https://www.themoviedb.org/settings/api
TMDB_BASE_URL        # https://api.themoviedb.org/3
TMDB_POSTER_URL      # https://image.tmdb.org/t/p/w500

# qBittorrent
QB_URL               # http://localhost:8080
QB_USER              # Usuário da WebUI
QB_PASS              # Senha da WebUI
QB_SAVE_PATH         # /mnt/media/qbittorrent/downloads/

# Jackett
JACKETT_URL          # http://localhost:9117
JACKETT_API_KEY      # Chave disponível na tela principal do Jackett

# Jellyfin
JELLYFIN_MEDIA_DIR   # /mnt/media/jellyfin/media/
```

## Integração qBittorrent (Docker)

O container do qBittorrent precisa montar a pasta de scripts:

```yaml
volumes:
  - /home/$USER/.openclaw/workspace/skills/media-processor/scripts:/scripts
```

Comando no qBittorrent (Opções → Downloads → Programa externo):
```
/scripts/qbittorrent-hook.sh "%F" "%I"
```

`%F` = caminho completo do conteúdo | `%I` = info hash do torrent

## Cron no Host

```cron
* * * * * /home/$USER/.openclaw/workspace/skills/media-processor/scripts/queue-processor.sh
```

## Fluxo Detalhado

### Hook (container → host)

```
qBittorrent dispara:
  /scripts/qbittorrent-hook.sh "/downloads/Filme.mkv" "abc123hash"

qbittorrent-hook.sh:
  - Converte caminho /downloads → /mnt/media/qbittorrent/downloads
  - Grava /scripts/queue/1713456789.job com:
      PATH=/mnt/media/qbittorrent/downloads/Filme.mkv
      HASH=abc123hash
```

### Processamento (host)

```
queue-processor.sh (cron):
  - Lê cada *.job em scripts/queue/
  - Extrai PATH e HASH
  - Chama qbittorrent-hook-host.sh "$PATH" "$HASH"

qbittorrent-hook-host.sh:
  Para cada arquivo MKV/MP4 encontrado:
    MKV → converter_mp4.sh → MP4 (AAC, mov_text, faststart)
    MP4 → verifica codec → recodifica áudio se não for AAC
    → mv para JELLYFIN_MEDIA_DIR/Filmes/
    → fetch-media-info.sh → TMDB JSON
    → telegram-notifier.sh --message ... -p poster -o sinopse

  Se todos OK:
    → qBittorrent API DELETE torrent + arquivos
  Se algum falhou:
    → Mantém torrent, loga aviso
```

### Bot de Download

```
Telegram: /baixar Inception 2010
  → telegram-bot.sh detecta comando
  → torrent-search.sh --search "Inception 2010" 2000 /tmp/state
    → Jackett API → filtra resultados com MagnetUri
    → Retorna lista formatada com tamanho e seeders
  → Usuário responde "2"
  → torrent-search.sh --add /tmp/state 2 filmes
    → qBittorrent API login → torrents/add com autoTMM=false
  → Download inicia → hook dispara ao concluir
```

## Limpeza de Títulos (`fetch-media-info.sh`)

O script limpa nomes de arquivo antes de consultar o TMDB, suportando dois padrões comuns:

**Por pontos:** `Filme.2024.1080p.BluRay.x264.DUAL.mkv`
**Por espaços:** `Filme 2024 HDRip 1080p Dublado - WWW.SITE.COM.mp4`

Padrões removidos:
- Tags técnicas: `HDRip`, `BluRay`, `WEB-DL`, `x264`, `x265`, `HEVC`, `IMAX`, `OPEN`, `MATTE`
- Qualidades: `1080p`, `720p`, `4K`, `UHD`
- Áudio: `AAC`, `AC3`, `DTS`, `Atmos`, `5.1`, `DUAL`
- Idioma: `Dublado`, `Legendado`, `PT-BR`, `DUB`
- Tags entre parênteses: `(1080p)`, `(BluRay)`, `(Dublado)`
- Tags grudadas após parênteses: `(1998)-DVDRipDublado`
- Domínios: `- WWW.SITE.COM`, `- The Pirate Filmes`
- Grupos: `YTS`, `RARBG`, `ETRG`, `YIFY`

Fallbacks de busca:
1. `pt-BR` com ano
2. `en-US` com ano
3. `pt-BR` sem ano

## Dependências do Host

```bash
# Obrigatórias
ffmpeg    # Conversão de vídeo/áudio
ffprobe   # Detecção de codec (incluso no ffmpeg)
jq        # Parse de JSON
python3   # Encoding de URL (urllib.parse)
curl      # Chamadas HTTP

# Instalação
sudo apt install ffmpeg jq python3 curl -y
```

## Logs

```
/var/log/media-processor/
├── YYYY-MM-DD.log    # Processamento diário
├── ffmpeg.log        # Saída do FFmpeg
└── converter_mp4.log # Log do converter_mp4.sh
```

## Notas Importantes

- `config.sh` nunca deve ser versionado — está no `.gitignore`
- O bot Telegram deve usar um token **separado** do OpenClaw para evitar conflito no `getUpdates`
- Legendas PGS (bitmap) são descartadas silenciosamente na conversão para MP4
- O torrent só é excluído se **todos** os arquivos forem processados sem erro
- Para pastas com múltiplos vídeos, todos são processados antes da deleção do torrent

## Troubleshooting

**Script não executa no qBittorrent:**
Verifique se o volume `/scripts` está montado no `docker-compose.yml` e se o script tem permissão de execução (`chmod +x`).

**TMDB retorna vazio:**
Use `DEBUG=1 ./fetch-media-info.sh "arquivo.mp4"` para ver o título e ano detectados. Ajuste o nome se necessário.

**Jackett não encontra resultados:**
Pesquise diretamente pelo título em português — trackers brasileiros indexam pelos títulos PT.

**Torrent não é deletado:**
Verifique no log se houve falha no processamento. O torrent é mantido intencionalmente quando há erros.
