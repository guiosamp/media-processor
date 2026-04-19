# 🎬 Media Processor

Pipeline automatizado de processamento de mídia para homelabs. Integra qBittorrent, FFmpeg, Jellyfin e Telegram em um único fluxo — do download ao catálogo, sem intervenção manual.

---

## Visão Geral

```
qBittorrent (conclui download)
        ↓
qbittorrent-hook.sh  (enfileira job via pasta compartilhada)
        ↓
queue-processor.sh   (roda no host via cron, a cada 1 min)
        ↓
qbittorrent-hook-host.sh
    ├─ MKV → converter_mp4.sh → MP4 com AAC
    ├─ MP4 → verifica codec de áudio → converte se necessário
    ├─ Move para /mnt/media/jellyfin/media/Filmes/
    ├─ Busca metadados no TMDB (fetch-media-info.sh)
    ├─ Notifica via Telegram com poster + sinopse (telegram-notifier.sh)
    └─ Deleta torrent + arquivos originais do qBittorrent
```

---

## Funcionalidades

- **Conversão automática** de MKV para MP4 com recodificação de áudio para AAC
- **Preservação de legendas** embarcadas (convertidas para `mov_text`)
- **Detecção inteligente de codec** — só recodifica o que for necessário
- **Metadados do TMDB** — busca título, sinopse e poster automaticamente
- **Notificação Telegram** com poster do filme e informações completas
- **Limpeza automática** — deleta o torrent e arquivos originais após processamento bem-sucedido
- **Bot Telegram** para solicitar downloads diretamente pelo chat (`/baixar`, `/serie`)
- **Busca de torrents via Jackett** com seleção interativa de resultados
- **Limpeza de nomes de arquivo** — suporta padrões com pontos ou espaços, remove tags técnicas e domínios

---

## Estrutura do Projeto

```
media-processor/
├── scripts/
│   ├── config.sh                    # ⚠️ NÃO versionado — credenciais
│   ├── config-example.sh            # Template de configuração
│   ├── qbittorrent-hook.sh          # Hook do qBittorrent (roda no container)
│   ├── qbittorrent-hook-host.sh     # Processamento principal (roda no host)
│   ├── queue-processor.sh           # Processa fila de jobs (cron no host)
│   ├── converter_mp4.sh             # Conversão MKV → MP4 via FFmpeg
│   ├── fetch-media-info.sh          # Busca metadados no TMDB
│   ├── telegram-notifier.sh         # Envia notificações via Telegram
│   ├── telegram-bot.sh              # Bot Telegram para solicitar downloads
│   ├── torrent-search.sh            # Busca torrents via Jackett API
│   ├── torrent-mover.sh             # Move torrents completos da pasta incomplete
│   ├── test-fetch-batch.sh          # Testa fetch-media-info em lote
│   ├── media-processor.service      # Unit file systemd (opcional)
│   └── queue/                       # Pasta de jobs pendentes (criada automaticamente)
├── references/                      # Documentação de referência
├── SKILL.md                         # Documentação para uso com OpenClaw
├── README.md                        # Este arquivo
├── LICENSE
└── .gitignore
```

---

## Pré-requisitos

### Host (Debian/Ubuntu)
```bash
sudo apt install ffmpeg jq python3 curl -y
```

### Docker
- qBittorrent (`lscr.io/linuxserver/qbittorrent`)
- Jellyfin
- Jackett (para o bot de download)

---

## Instalação

### 1. Clone o repositório

```bash
git clone https://github.com/seu-usuario/media-processor.git
cd media-processor/scripts
```

### 2. Configure as credenciais

```bash
cp config-example.sh config.sh
nano config.sh
```

Preencha o `config.sh`:

```bash
# Telegram
export TELEGRAM_BOT_TOKEN="seu_token"
export TELEGRAM_CHAT_ID="seu_chat_id"

# TMDB — https://www.themoviedb.org/settings/api
export TMDB_API_KEY="sua_chave"
export TMDB_BASE_URL="https://api.themoviedb.org/3"
export TMDB_POSTER_URL="https://image.tmdb.org/t/p/w500"

# qBittorrent
export QB_URL="http://localhost:8080"
export QB_USER="admin"
export QB_PASS="sua_senha"
export QB_SAVE_PATH="/mnt/media/qbittorrent/downloads/"

# Jackett
export JACKETT_URL="http://localhost:9117"
export JACKETT_API_KEY="sua_chave_jackett"

# Jellyfin
export JELLYFIN_MEDIA_DIR="/mnt/media/jellyfin/media/"
```

### 3. Torne os scripts executáveis

```bash
chmod +x *.sh
mkdir -p queue
```

### 4. Configure o docker-compose do qBittorrent

Monte a pasta de scripts no container:

```yaml
services:
  qbittorrent:
    volumes:
      - /mnt/media/qbittorrent/downloads:/downloads
      - /home/seu-usuario/media-processor/scripts:/scripts
```

### 5. Configure o hook no qBittorrent

Acesse **Opções → Downloads → Executar programa externo ao concluir o torrent**:

```
/scripts/qbittorrent-hook.sh "%F" "%I"
```

### 6. Adicione o cron no host

```bash
crontab -e
```

```cron
* * * * * /home/seu-usuario/media-processor/scripts/queue-processor.sh
```

---

## Bot Telegram

### Configuração

1. Crie um bot no [@BotFather](https://t.me/BotFather) e copie o token
2. Inicie uma conversa com o bot e acesse:
   ```
   https://api.telegram.org/bot<SEU_TOKEN>/getUpdates
   ```
3. Copie o `id` dentro de `chat` — esse é o seu `TELEGRAM_CHAT_ID`
4. Preencha `MP_BOT_TOKEN` e `MP_CHAT_ID` no `config.sh`

### Comandos disponíveis

| Comando | Descrição |
|---|---|
| `/baixar <título>` | Busca e baixa um filme |
| `/serie <título>` | Busca e baixa uma série |
| `1`, `2`, `3`... | Escolhe o resultado desejado |
| `0` | Cancela a operação |
| `/status` | Mostra downloads em andamento |
| `/cancelar` | Cancela operação atual |
| `/ajuda` | Lista os comandos |

### Iniciar o bot

```bash
# Em foreground (para testar)
./telegram-bot.sh

# Em background
nohup ./telegram-bot.sh >> /var/log/media-processor/bot.log 2>&1 &
```

---

## Scripts

### `converter_mp4.sh`

Converte arquivos MKV para MP4.

```bash
# Arquivo único
./converter_mp4.sh --path /caminho/filme.mkv

# Com offset de áudio
./converter_mp4.sh --path /caminho/filme.mkv --offset -1.5

# Apaga o original após conversão
./converter_mp4.sh --path /caminho/filme.mkv --delete

# Opções
--path    Arquivo .mkv ou diretório
--offset  Offset de áudio em segundos
--delete  Remove o .mkv original após conversão bem-sucedida
--log     Caminho personalizado para o log
```

### `fetch-media-info.sh`

Busca informações do filme no TMDB.

```bash
./fetch-media-info.sh "Nome do Filme (2024).mp4"

# Debug — mostra título e ano detectados
DEBUG=1 ./fetch-media-info.sh "Nome.Do.Filme.2024.1080p.BluRay.mkv"
```

Retorna JSON com `titulo`, `titulo_original`, `ano`, `sinopse`, `poster` e `nota`.

### `test-fetch-batch.sh`

Testa o `fetch-media-info.sh` contra todos os filmes da biblioteca Jellyfin.

```bash
./test-fetch-batch.sh
```

### `torrent-mover.sh`

Move torrents completos (em estado seeding) da pasta `incomplete` para a pasta de downloads.

```bash
./torrent-mover.sh
```

---

## Logs

```
/var/log/media-processor/
├── YYYY-MM-DD.log      # Log diário do processamento
├── ffmpeg.log          # Log detalhado do FFmpeg
└── torrent-mover.log   # Log do movimentador de torrents
```

---

## Observações

- Legendas PGS (imagem, comuns em BluRay) não podem ser convertidas para `mov_text` — são descartadas silenciosamente
- O torrent só é deletado se **todos** os arquivos forem processados com sucesso
- Se um processamento falhar, o torrent é mantido no qBittorrent para reprocessamento manual
- A variável `%F` no hook do qBittorrent pode ser um arquivo único ou uma pasta

---

## Licença

MIT — veja [LICENSE](LICENSE) para detalhes.
