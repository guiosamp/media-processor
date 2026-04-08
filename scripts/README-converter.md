# Script de Conversão MKV → MP4

## `converter_mp4.sh`

Script principal para conversão de arquivos MKV para MP4 com ajuste de offset de áudio.

### Características
- Conversão eficiente (copia codec de vídeo, converte áudio para AAC)
- Suporte a offset de áudio (correção de sincronização)
- Processamento em lote de diretórios
- Verificação de arquivos já convertidos
- Log detalhado

### Uso Básico
```bash
# Converter um arquivo específico
./converter_mp4.sh --path "/caminho/para/arquivo.mkv"

# Converter todos os MKV em um diretório
./converter_mp4.sh --path "/caminho/para/diretorio/"

# Com offset de áudio de +2 segundos
./converter_mp4.sh --path "/caminho/para/arquivo.mkv" --offset 2

# Apagar original após conversão
./converter_mp4.sh --path "/caminho/para/arquivo.mkv" --delete

# Modo interativo (sem argumentos)
./converter_mp4.sh
```

## Integração com Media Processor

O script é automaticamente chamado pelo `media-processor-cli.sh` durante o processamento. Não é necessário executá-lo manualmente.

### Logs
- Log principal: `/var/log/media-processor/converter_mp4.log`
- Logs de ffmpeg: `$LOG_FILE` (configurável)

### Dependências
```bash
# Ubuntu/Debian
sudo apt-get install ffmpeg

# Verificar instalação
ffmpeg -version
```

### Notas Técnicas
1. **Codec de vídeo**: Copiado (sem re-encode) para máxima qualidade e velocidade
2. **Codec de áudio**: Convertido para AAC 192kbps 2 canais (compatível com todos os players)
3. **Offset de áudio**: Útil para corrigir problemas de sincronização
4. **Metadados**: Inclui `movflags +faststart` para streaming otimizado

### Solução de Problemas
```bash
# Verificar logs
tail -f /var/log/media-processor/converter_mp4.log

# Testar com um arquivo pequeno
./converter_mp4.sh --path "arquivo_teste.mkv"

# Verificar permissões
chmod +x converter_mp4.sh
```

### Compatibilidade
- Testado com ffmpeg 4.x e 5.x
- Compatível com MKVs de qualquer codec (H264, H265, VP9, AV1)
- Saída MP4 compatível com Jellyfin, Plex, VLC, etc.