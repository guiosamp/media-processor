---
name: media-processor
description: Automatizar processamento de downloads do qBittorrent para Jellyfin, incluindo conversão MKV→MP4, organização de arquivos e notificações Telegram. Use quando: (1) Monitorar pasta de downloads do qBittorrent para processar novos arquivos, (2) Converter arquivos de vídeo para maior compatibilidade, (3) Organizar mídia na estrutura do Jellyfin, (4) Enviar notificações via Telegram sobre processamento concluído, (5) Lidar com problemas de permissões em arquivos de log.
---

# Media Processor - Skill para qBittorrent → Jellyfin

Skill para automatizar o processamento de downloads do qBittorrent, converter arquivos MKV para MP4, organizar na biblioteca do Jellyfin e enviar notificações via Telegram.

## Configuração do Ambiente

### Diretórios Padrão
- **Downloads do qBittorrent**: `/mnt/media/qbittorrent/downloads/`
- **Script de conversão**: `/PATH/TO/media-processor/scripts/converter_mp4.sh`
- **Biblioteca Jellyfin**: `/mnt/media/jellyfin/media/`
- **Logs**: `/var/log/media-processor/` (necessário criar com permissões adequadas)

### Permissões de Log
Para evitar erros de permissão:
```bash
sudo mkdir -p /var/log/media-processor/
sudo chown -R $USER:$USER /var/log/media-processor/
sudo chmod 755 /var/log/media-processor/
```

## Fluxo de Trabalho Principal

### 1. Monitorar Downloads
O script principal (`media-processor-cli.sh`) monitora a pasta de downloads do qBittorrent por novos arquivos concluídos.

### 2. Processar Arquivos
Para cada arquivo MKV encontrado:
- Executar `converter_mp4.sh` para conversão
- Aplicar offset de áudio se necessário (padrão: 0)
- Opcionalmente deletar original após conversão

### 3. Organizar no Jellyfin
Após conversão:
- Mover arquivo MP4 para estrutura organizada do Jellyfin
- Criar diretórios por categoria (filmes/séries)
- Renomear arquivos seguindo padrão Jellyfin

### 4. Notificar via Telegram
Enviar notificação com:
- Nome do arquivo processado
- Status da conversão
- Localização final
- Estatísticas do processamento

## Scripts Disponíveis

### scripts/media-processor-cli.sh
CLI unificado para monitoramento e processamento.

### scripts/qbittorrent-hook.sh
Script para configurar como "Executar programa externo" no qBittorrent. Acionado automaticamente quando downloads são concluídos.

### scripts/telegram-notifier.sh
Envia notificações via Telegram usando webhook.

## Uso Rápido

### Processamento Manual
```bash
./scripts/media-processor-cli.sh --process /mnt/media/qbittorrent/downloads/
```

### Monitoramento Contínuo (Serviço)
```bash
./scripts/media-processor-cli.sh --monitor --daemon
```

### Configurar como Serviço Systemd
```bash
sudo cp scripts/media-processor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable media-processor
sudo systemctl start media-processor
```

## Solução de Problemas

### Erros de Permissão
Se encontrar erros de permissão em arquivos de log:
1. Verifique proprietário dos diretórios de log
2. Ajuste permissões com `chmod` e `chown`
3. Configure logs em diretório com permissão de escrita

### Arquivos Não Processados
1. Verifique se arquivos são MKV válidos
2. Confirme espaço em disco disponível
3. Verifique permissões de leitura/escrita

### Processamento de Arquivos Incompletos
O script agora evita processar arquivos ainda em download:
1. **Hook do qBittorrent**: Detecta caminhos com "incomplete" e não processa
2. **Monitoramento**: Exclui arquivos na pasta `/incomplete/`
3. **Processamento manual**: Verifica se arquivo está na pasta incomplete

Se arquivos ainda estiverem sendo processados durante download:
- Verifique logs em `/var/log/media-processor/qbittorrent-hook.log`
- Confirme configuração do qBittorrent (caminho de download completo)
- Verifique se variável `TORRENT_PATH` está correta

### Notificações Telegram Não Enviadas
1. Verifique token e chat ID configurados
2. Confirme conectividade com API do Telegram
3. Verifique logs para mensagens de erro

## Configuração do Telegram

Para notificações via Telegram, configure:
- `TELEGRAM_BOT_TOKEN`: Token do bot
- `TELEGRAM_CHAT_ID`: ID do chat para notificações

Use `scripts/telegram-notifier.sh --setup` para configuração inicial.

## Configuração do qBittorrent

Para que o media-processor funcione automaticamente ao finalizar um download, siga os passos:

1.  Vá nas configurações do qBittorrent.
2.  Encontre a opção "Executar programa externo ao terminar a tarefa".
3.  No campo de texto, insira o *caminho completo* para o script `qbittorrent-hook.sh`.
    Exemplo: `/PATH/TO/media-processor/scripts/qbittorrent-hook.sh`
4.  Clique em "Aplicar" ou "OK" para salvar as configurações.

## Estrutura de organização recomendada para Jellyfin

A melhor prática para organizar sua biblioteca do Jellyfin é criar uma estrutura de diretórios clara e consistente:

```
/mnt/media/jellyfin/media/
├── Filmes/
│   ├── Nome do Filme (Ano)/
│   │   └── nome_do_filme.mp4
├── Series/
│   ├── Nome da Série/
│   │   ├── Temporada 01/
│   │   │   └── nome_da_serie - s01e01 - nome_do_episodio.mp4
│   │   ├── Temporada 02/
│   │   │   └── ...
│   └── ...
└── Animes/
    ├── Nome do Anime/
    │   ├── Temporada 01/
    │   │   └── ...
    └── ...
```

**Filmes**: Contém filmes organizados por seus respectivos nomes e anos de lançamento.
**Séries**: Organizadas por nome da série, temporadas e episódios.
**Animes**: Semelhante às séries, com nomes de animes e suas temporadas/episódios

**Importante**:
*   Esta estrutura facilita a catalogação e organização automática pelo Jellyfin.
*   Considere usar um software de renomeação em massa para padronizar os nomes dos arquivos.

**Considerações Finais**: Adapte essa estrutura às suas necessidades e preferências. Mantenha a organização consistente para evitar problemas de reconhecimento.
