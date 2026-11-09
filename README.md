# AZX Server

Gerenciador local de servidores Minecraft Java para Windows, operado pelo arquivo `AZX-SERVER.bat`.

## Etapa 1 — Creator

O criador prepara instancias reais de Minecraft Java **1.20.1** com instaladores e arquivos obtidos das fontes oficiais:

- **Vanilla:** baixa o servidor pelo manifesto oficial da Mojang e confere o SHA-1.
- **Forge 47.2.0:** baixa o instalador oficial e executa a instalacao de servidor.
- **Fabric:** consulta os metadados oficiais do Fabric e baixa o launcher de servidor correspondente.

Na criacao, o usuario define nome, software, autenticacao oficial, porta TCP, maximo de jogadores, distancia de visao e memoria inicial/maxima.

Cada instancia fica em `servers/NOME_DO_SERVIDOR` e recebe `start.bat`, `server.properties`, `eula.txt`, `azx-server.json`, `LEIA-PRIMEIRO.txt` e as pastas `mods`, `config`, `world`, `logs`, `crash-reports` e `libraries`. O proprio Minecraft gera os arquivos do mundo no primeiro boot.

## Requisitos

- Windows 10/11 64-bit.
- Java 17 ou superior instalado e disponivel no PATH (Java 17 e a referencia recomendada para Minecraft 1.20.1).
- Internet durante a instalacao.
- Espaco em disco para os arquivos do servidor.

Download recomendado do Java: https://adoptium.net/temurin/releases/?version=17

## Comecar

1. Baixe o ZIP do repositorio e extraia a pasta.
2. Execute `AZX-SERVER.bat`.
3. Escolha **Criar servidor** e siga o assistente.
4. Abra a pasta da instancia criada.
5. Leia o EULA em `eula.txt`. Somente se concordar, altere manualmente `eula=false` para `eula=true`.
6. Execute `start.bat`.

O AZX nao aceita o EULA automaticamente e nao distribui Minecraft, Java ou mods.

## Mods e OptiFine

Coloque em `mods` somente mods de servidor compativeis com Minecraft 1.20.1 e com o loader escolhido. Em servidores modded, os jogadores geralmente precisam instalar os mods correspondentes no cliente. OptiFine e um mod de cliente; nao e instalado como componente do servidor.

## Rede e seguranca

O servidor usa a porta TCP escolhida no assistente. Para amigos fora da rede local, normalmente e necessario encaminhar essa porta no roteador e permitir a conexao no firewall do Windows. Ter um IP publico exibido nao garante acessibilidade: CGNAT, firewall ou regras do provedor podem impedir conexoes diretas.

Desativar `online-mode` permite conexoes sem autenticacao oficial, mas facilita falsificacao de nomes e impersonacao. Use somente em ambiente privado, com pessoas confiaveis, e mantenha whitelist/controles de acesso quando disponiveis.

## Etapa 2 — Manager

Cada instancia AZX recebe agora:

- `configure.bat`: menu para alterar MOTD, limite de jogadores, distancia de visao, porta, autenticacao, dificuldade, modo de jogo e whitelist.
- `stop.bat`: envia o comando `stop` pelo RCON para o Minecraft salvar o mundo e encerrar normalmente.
- `restart.bat`: solicita parada graciosa, aguarda o encerramento e abre uma nova janela para iniciar novamente.
- `reset.bat`: restaura configuracoes comuns sem apagar mundo, mods ou configs de mods.

O AZX envia os comandos administrativos ao RCON por meio de `127.0.0.1`, com senha aleatoria por instancia guardada em `azx-rcon.txt`. O RCON e um protocolo sem criptografia e o servidor pode escutar em interfaces de rede; por isso, mantenha a senha privada, nao encaminhe a porta RCON no roteador e nao crie regras de firewall que permitam acesso externo a essa porta. O AZX usa uma porta RCON separada da porta de jogo e desativa a transmissao de comandos RCON aos operadores.

Instancias criadas antes da Etapa 2 recebem os arquivos de gerenciamento e a configuracao RCON quando forem selecionadas em **Gerenciar servidor** no menu principal. Se uma dessas instancias ja estiver ligada, a configuracao RCON so passa a valer depois de um reinicio; ate la, desligue-a pelo console do Minecraft.

### Como usar

1. Abra `AZX-SERVER.bat`.
2. Escolha **Gerenciar servidor** e selecione uma instancia.
3. Para administrar diretamente, abra `configure.bat`, `stop.bat`, `restart.bat` ou `reset.bat` dentro da pasta da instancia.
4. Alteracoes em `server.properties` exigem reiniciar o servidor. Operacoes OP e whitelist podem ser enviadas ao servidor ligado.

## Etapa 3 — Monitoramento e diagnostico

Cada instancia AZX recebe tres ferramentas adicionais:

- `status.bat`: mostra se a porta TCP local responde, latencia de conexao TCP, processo Java/PID, memoria residente, CPU acumulada, tempo ligado, espaco livre e erros recentes do log.
- `monitorar.bat`: atualiza o painel de status continuamente; use Ctrl+C para sair.
- `diagnostico.bat`: verifica processo, porta local, enderecos IPv4 da LAN, perfis do Firewall do Windows e erros recentes do log.

O menu principal tambem oferece **Status do servidor** e **Diagnostico de rede**. O monitor consulta somente a instancia selecionada e nao encerra nem altera o mundo.

**Limites importantes:** o teste de ping mede o tempo de conexao TCP no proprio computador, nao o ping real de jogadores externos. O diagnostico nao consegue confirmar automaticamente encaminhamento de porta, disponibilidade publica ou CGNAT. Para acesso externo, encaminhe apenas a porta TCP do jogo para o IPv4 local correto e mantenha a porta RCON fechada. Nenhuma senha RCON e exibida pelo painel.

## Etapa 4 — AZX Monitor (penultima etapa)

A Etapa 4 amplia o monitoramento para um painel ao vivo, com coleta periodica de metricas e historico local:

- Estado do servidor pelo protocolo de status Minecraft, alem da conexao TCP local.
- Jogadores online/limite e nomes de amostra quando o proprio servidor os fornece.
- Processo Java/PID, memoria residente do processo, CPU acumulada e uptime.
- Espaco livre na unidade do servidor.
- Eventos recentes de entrada/saida e erros identificados no log.
- Historico de snapshots em CSV, salvo em `monitor-data/historico.csv`, enquanto `monitorar.bat` estiver aberto.
- Opcao **9. Monitoramento ao vivo** no menu principal.

Execute `status.bat` para uma leitura unica, `monitorar.bat` para acompanhar e registrar o historico, ou `diagnostico.bat` para verificacoes locais de rede.

**Limites das metricas:** memoria apresentada e o uso residente do processo Java, nao a ocupacao exata do heap da JVM. CPU e tempo acumulado do processo, nao porcentagem instantanea. TPS/MSPT nao e fornecido pelo servidor Vanilla; para essas metricas e necessario instalar um plugin/mod compativel. A lista de nomes e apenas a amostra disponibilizada pelo protocolo de status, nao necessariamente a lista completa. O historico CSV so e gravado enquanto o monitor continuo esta rodando.

## Limites atuais

As Etapas 1 a 4 cobrem criacao, administracao, diagnostico local e monitoramento com historico para Minecraft 1.20.1 com Vanilla, Forge e Fabric. Ainda faltam testes de execucao em Windows em diferentes instalacoes, backups, atualizacoes e suporte a mais loaders/versoes. O RCON nao e criptografado e nao deve ser exposto a internet.