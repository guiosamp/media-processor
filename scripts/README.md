# scripts/README.md - Instruções de Uso

Este diretório contém scripts que facilitam o processamento de mídia, a integração com qBittorrent e as notificações via Telegram.

## scripts/media-processor-cli.sh

Script principal para monitorar downloads, converter arquivos MKV para MP4, mover para Jellyfin e notificar via Telegram.

### Uso

*   **Monitoramento Contínuo (como serviço)**:

    ```bash
    ./media-processor-cli.sh --monitor
    ```
    Este comando manterá o script em execução contínua, monitorando a pasta de downloads.

    *   **Para executar como serviço (recomendado)**: consulte a seção "Configurar como Serviço Systemd" no SKILL.md

*   **Processamento Manual de um Arquivo:**

    ```bash
    ./media-processor-cli.sh --process <caminho_do_arquivo.mkv>
    ```

    Substitua `<caminho_do_arquivo.mkv>` pelo caminho completo do arquivo MKV que você deseja processar.

## scripts/qbittorrent-hook.sh

Script para ser usado com "Executar programa externo" no qBittorrent para automaticamente processar downloads concluídos.

### Configuração

1.  Configure o script no qBittorrent (ver Configuração do qBittorrent em SKILL.md).

## scripts/telegram-notifier.sh

Script para enviar notificações via Telegram.

### Configuração

1.  Edite o script para configurar o seu `TELEGRAM_BOT_TOKEN` e `TELEGRAM_CHAT_ID`.

2.  Execute:

    ```bash
    ./telegram-notifier.sh --setup
    ```

    Isso irá fornecer instruções adicionais sobre como configurar o bot.
