# Configuração do qBittorrent

## Habilitar "Executar programa externo" (External Program)

1.  Vá nas configurações do qBittorrent.
2.  Em "Downloads", encontre a opção "Executar programa externo ao terminar a tarefa".
3.  No campo de texto, insira o *caminho completo* para o script `qbittorrent-hook.sh`.
    Exemplo: `/PATH/TO/media-processor/scripts/qbittorrent-hook.sh`
4.  Clique em "Aplicar" ou "OK" para salvar as configurações.

## Teste da Configuração

1.  Adicione um novo torrent ao qBittorrent.
2.  Aguarde o download ser concluído.
3.  Verifique os logs: `/var/log/qbittorrent-hook.log` e `/var/log/media-processor/<data>.log`
    -  Considere as permissões do utilizador que executa o qBittorrent.
