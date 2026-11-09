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

## Limites desta etapa

A Etapa 1 entrega o criador e a instalacao base para Minecraft 1.20.1 com Vanilla, Forge e Fabric. Gerenciamento completo (parar/reiniciar/configurar), NeoForge e outros loaders/versoes, backups, monitoramento, diagnostico de rede e atualizacoes serao implementados nas etapas seguintes. Os arquivos gerados aqui sao instancias reais, mas a etapa ainda nao e o gerenciador completo prometido.
