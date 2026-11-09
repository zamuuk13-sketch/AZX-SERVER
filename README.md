# AZX Server

Gerenciador local de servidores Minecraft Java para Windows, operado pelo arquivo `AZX-SERVER.bat`.

## Requisitos

- Windows 10/11 64-bit.
- Java 17 ou superior no PATH (Java 17 e a referencia recomendada para Minecraft 1.20.1).
- Internet durante a instalacao.
- Espaco em disco para os arquivos do servidor.

Download recomendado: https://adoptium.net/temurin/releases/?version=17

## Etapa 1 — AZX Creator

Cria instancias reais de Minecraft Java **1.20.1**:
- **Vanilla:** baixa o servidor pelo manifesto oficial da Mojang e confere o SHA-1.
- **Forge 47.2.0:** baixa o instalador oficial e executa a instalacao de servidor.
- **Fabric:** consulta os metadados oficiais e baixa o launcher de servidor correspondente.

O assistente define nome, software, autenticacao oficial, porta TCP, maximo de jogadores, distancia de visao e memoria inicial/maxima. Cada instancia recebe a estrutura de pastas, arquivos de inicializacao e configuracao. O mundo e gerado pelo Minecraft no primeiro boot.

## Comecar

1. Baixe o ZIP do repositorio e extraia a pasta.
2. Execute `AZX-SERVER.bat`.
3. Escolha **Criar servidor** e siga o assistente.
4. Leia `eula.txt`; somente se concordar, altere manualmente `eula=false` para `eula=true`.
5. Execute `start.bat`.

O AZX nunca aceita o EULA automaticamente e nao distribui Minecraft, Java ou mods.

## Etapa 2 — AZX Manager

Cada instancia recebe:
- `configure.bat`: MOTD, limite de jogadores, distancia de visao, porta, autenticacao, dificuldade, modo de jogo e whitelist.
- `stop.bat`: solicita parada graciosa via RCON para salvar o mundo.
- `restart.bat`: solicita parada, aguarda o encerramento e inicia novamente.
- `reset.bat`: restaura configuracoes comuns sem apagar mundo, mods ou configs de mods.

O RCON usa senha aleatoria por instancia em `azx-rcon.txt`. RCON nao e criptografado: mantenha a senha privada, nao encaminhe a porta RCON e nao crie regras de firewall que permitam acesso externo. O AZX nao exibe a senha no monitor.

## Etapa 3 — Diagnostico

O diagnostico consulta a porta TCP local, enderecos IPv4 da LAN, perfis do Firewall do Windows e erros recentes do log. Isso nao confirma encaminhamento de porta, acesso publico ou ausencia de CGNAT.

Para amigos fora da rede local, normalmente e necessario encaminhar somente a porta TCP do jogo no roteador e permitir essa porta no firewall. CGNAT ou regras do provedor podem impedir conexoes diretas.

## Etapa 4 — AZX Monitor

Ferramentas por instancia:
- `status.bat`: estado pelo protocolo de status Minecraft, jogadores/limite, amostra de nomes, processo Java/PID, memoria residente, CPU acumulada, uptime, espaco livre e erros recentes.
- `monitorar.bat`: painel ao vivo e historico CSV em `monitor-data/historico.csv`.
- `diagnostico.bat`: verificacoes locais de rede e firewall.
- Menu principal: status, diagnostico e monitoramento ao vivo.

**Limites:** a memoria e o working set do processo, nao o heap exato da JVM. CPU e tempo acumulado, nao porcentagem instantanea. TPS/MSPT requer plugin/mod compativel. Nomes sao apenas a amostra fornecida pelo protocolo de status. O historico CSV e gravado enquanto o monitor esta aberto.

## Etapa 5 — AZX Advanced (etapa final)

O menu **10. AZX Advanced** ou o arquivo `advanced.bat` de cada instancia oferece:

- **Backup completo ZIP:** copia arquivos da instancia e cria manifesto com SHA-256 por arquivo. Inclui mundo, mods, configuracoes, bibliotecas e arquivos de inicializacao; exclui os diretorios de backups e historico do monitor para evitar recursao e volume desnecessario.
- **Listagem de backups:** mostra nome, tamanho e data.
- **Verificacao de integridade:** extrai em pasta temporaria e confere todos os hashes SHA-256 antes de considerar o backup valido.
- **Restauracao:** exige confirmacao digitando `RESTAURAR`, valida o arquivo antes de alterar a instancia e cria automaticamente um backup do estado atual. A restauracao substitui os arquivos atuais pelos do backup; execute `start.bat` manualmente depois de revisar.
- **Limpeza:** remove somente arquivos antigos de `logs` e `crash-reports`, com idade e confirmacao definidas pelo usuario.

**Seguranca e limites do Advanced:**
- Backup, restauracao e limpeza exigem o servidor desligado; nao tente copiar um mundo em uso.
- Backups ZIP podem conter `azx-rcon.txt` e configuracoes sensiveis. Mantenha-os privados e guarde uma segunda copia em outro disco ou local seguro.
- A limpeza nao apaga mundos, mods, configs, bibliotecas ou backups.
- O AZX nao atualiza automaticamente Minecraft, Forge, Fabric ou mods. Atualizacoes de software exigem compatibilidade, copia de seguranca e procedimento especifico; nao substitua JARs automaticamente.
- Nao existe agendamento automatico de backup nesta versao; os backups sao iniciados pelo usuario.

## Escopo e testes

As cinco etapas do AZX estao implementadas para o fluxo de criacao 1.20.1 Vanilla, Forge e Fabric. O workflow do GitHub Actions valida sintaxe PowerShell e JSON, mas isso nao substitui teste funcional em uma maquina Windows com Java e servidores reais. Teste criacao, inicializacao, parada, backup, verificacao e restauracao em uma instancia descartavel antes de confiar os mundos importantes ao AZX.


## Etapa 6 — AZX External Access (Playit)

O AZX pode iniciar o agente oficial do Playit para publicar um servidor Minecraft Java sem encaminhamento de portas no roteador e sem exigir que os jogadores instalem um cliente.

### Configuracao inicial

1. Inicie \`AZX-SERVER.bat\` e abra **11. AZX External Access (Playit)**.
2. Selecione a instancia e escolha **Habilitar Playit / instalar e iniciar agente**.
3. Na primeira execucao, vincule o agente a sua conta gratuita Playit usando o link/codigo exibido na janela do agente.
4. No painel Playit, crie um tunel do tipo **Minecraft Java** apontando para \`127.0.0.1\` e para a porta configurada naquela instancia (normalmente \`25565\`).
5. Copie o endereco publico fornecido pelo Playit e use **Salvar endereco publico do tunel** no menu AZX.
6. A partir dai, o \`start.bat\` da instancia inicia o agente Playit automaticamente quando a integracao estiver habilitada.

Tambem e criado um \`playit.bat\` dentro da pasta de cada instancia para abrir diretamente o gerenciamento do tunel.

### Comportamento e limites

- O executavel e baixado sob demanda da release oficial \`playit-cloud/playit-agent\` e armazenado em \`services/playit/playit.exe\`. O AZX nao inclui binarios de terceiros no repositorio.
- A primeira vinculacao da conta e a criacao do tunel continuam sendo feitas pelo usuario no site oficial; o AZX nao pede nem armazena senha ou token da conta Playit.
- O agente e compartilhado por todas as instancias AZX no mesmo computador. Cada instancia precisa de seu proprio tunel configurado no painel, apontando para sua porta local.
- O endereco salvo no AZX e informativo; o AZX nao consulta a conta Playit para descobrir automaticamente o hostname nem garante que o tunel esteja online.
- Se o Playit falhar, o servidor Minecraft continua iniciando localmente.
- Somente o computador host executa o agente. Os amigos entram pelo endereco publico usando o Minecraft Java normal.
- A conexao depende da disponibilidade, limites e termos do plano Playit. Consulte o site oficial para detalhes atuais.
- O agente usa uma conexao de saida; nao e necessario abrir a porta do jogo no roteador para o tunel funcionar.

Site e downloads oficiais: https://playit.gg/  
Documentacao: https://playit.gg/support/
