# Media Processor Skill for qBittorrent → Jellyfin

Skill para automatizar o processamento de downloads do qBittorrent, converter arquivos MKV para MP4 e organizar na biblioteca do Jellyfin com notificações via Telegram.

## ⚡ Características Principais

- **Conversão automática MKV→MP4** com ffmpeg
- **Integração com qBittorrent** via "Executar programa externo"
- **Organização inteligente** para Jellyfin
- **Notificações via Telegram** sobre processamento
- **Proteção contra processamento de downloads incompletos**
- **Suporte a systemd** para execução como serviço
- **CLI unificado** para monitoramento e processamento manual

## 🚀 Instalação Rápida

### Pré-requisitos
```bash
# Instalar dependências
sudo apt-get update
sudo apt-get install -y ffmpeg curl

# Criar diretórios de log
sudo mkdir -p /var/log/media-processor/
sudo chown -R $USER:$USER /var/log/media-processor/
sudo chmod 755 /var/log/media-processor/
```

### Clonar o repositório
```bash
git clone https://github.com/guiosamp/media-processor.git
cd media-processor
```

### Configurar Telegram (opcional)
```bash
# 1. Copiar o template
cp scripts/telegram-config-example.sh scripts/telegram-config.sh

# 2. Editar com suas credenciais
nano scripts/telegram-config.sh

# 3. Configurar bot e chat ID conforme instruções em scripts/telegram-notifier.sh --setup
```

### Configurar qBittorrent
```bash
# 1. Ir para Configurações > Downloads no qBittorrent
# 2. Em "Executar programa externo ao terminar a tarefa", inserir:
#    /caminho/completo/para/media-processor/scripts/qbittorrent-hook.sh
```

## 📋 Estrutura do Projeto

```
media-processor/
├── SKILL.md                 # Documentação da skill (OpenClaw)
├── README.md                # Este arquivo
├── scripts/
│   ├── media-processor-cli.sh      # CLI principal
│   ├── qbittorrent-hook.sh         # Hook para qBittorrent
│   ├── telegram-notifier.sh        # Notificações Telegram
│   ├── telegram-config-example.sh  # Template de configuração
│   ├── converter_mp4.sh            # Conversor MKV→MP4 principal
│   ├── converter-wrapper.sh        # Wrapper para conversão
│   └── media-processor.service     # Service file systemd
├── references/
│   ├── qbittorrent-setup.md        # Configuração do qBittorrent
│   └── jellyfin-structure.md       # Estrutura do Jellyfin
├── examples/                # Exemplos de uso
└── .gitignore              # Arquivos ignorados (dados sensíveis)
```

## 🛠️ Uso

### Processamento Manual
```bash
./scripts/media-processor-cli.sh --process /caminho/para/arquivo.mkv
```

### Monitoramento Contínuo
```bash
./scripts/media-processor-cli.sh --monitor
```

### Como Serviço Systemd
```bash
sudo cp scripts/media-processor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable media-processor
sudo systemctl start media-processor
```

### Verificar logs
```bash
tail -f /var/log/media-processor/$(date +%Y-%m-%d).log
```

## ⚙️ Configuração

### Diretórios Padrão (editar conforme necessário)
- **Downloads do qBittorrent**: `/mnt/media/qbittorrent/downloads/`
- **Script de conversão**: `scripts/converter_mp4.sh` (incluído no repositório)
- **Biblioteca Jellyfin**: `/mnt/media/jellyfin/media/`

### Configuração do Telegram
1. Crie um bot com @BotFather e obtenha o token
2. Descubra seu chat ID enviando uma mensagem para o bot
3. Crie `scripts/telegram-config.sh` baseado no exemplo
4. Adicione suas credenciais no arquivo

## 🔒 Segurança

Este repositório NÃO contém:
- ✅ Tokens reais do Telegram
- ✅ Dados sensíveis de usuário
- ✅ Credenciais de API
- ✅ Informações pessoais

**Arquivos ignorados pelo git (veja .gitignore):**
- `telegram-config.sh` (criar manualmente)
- `*.log` (arquivos de log)
- `*.config.local` (configurações locais)
- Arquivos com `secrets` no nome

## 🐛 Solução de Problemas

### Erros de Permissão
```bash
sudo chown -R $USER:$USER /var/log/media-processor/
sudo chmod 755 /var/log/media-processor/
```

### Arquivos sendo processados durante download
O script detecta automaticamente arquivos na pasta `incomplete` e não os processa. Se ainda houver problemas:
1. Verifique logs: `/var/log/media-processor/qbittorrent-hook.log`
2. Confirme configuração do qBittorrent
3. Verifique variável `TORRENT_PATH`

### Não recebe notificações Telegram
1. Verifique se `telegram-config.sh` existe com credenciais corretas
2. Teste conexão: `curl https://api.telegram.org`
3. Verifique permissões do arquivo

## 📄 Licença

Este projeto está disponível sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

## 🤝 Contribuição

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues e pull requests.

## 🔗 Links Úteis

- [Documentação da skill](SKILL.md)
- [Configuração do qBittorrent](references/qbittorrent-setup.md)
- [Estrutura do Jellyfin](references/jellyfin-structure.md)
- [Exemplos de uso](examples/)