$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ServersRoot = Join-Path $Root 'servers'
$ManifestUrl = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
$SupportedMinecraft = '1.20.1'
$ForgeVersion = '47.2.0'
New-Item -ItemType Directory -Force -Path $ServersRoot | Out-Null

function Write-Title {
    Clear-Host
    Write-Host '==================================================' -ForegroundColor DarkCyan
    Write-Host '                 AZX SERVER' -ForegroundColor Cyan
    Write-Host '            SERVER CREATOR - ETAPA 1' -ForegroundColor Gray
    Write-Host '==================================================' -ForegroundColor DarkCyan
    Write-Host ''
}
function Ask-Number([string]$Label, [int]$Default, [int]$Min, [int]$Max) {
    while ($true) {
        $Answer = Read-Host "$Label [$Default]"
        if ([string]::IsNullOrWhiteSpace($Answer)) { return $Default }
        $Number = 0
        if ([int]::TryParse($Answer, [ref]$Number) -and $Number -ge $Min -and $Number -le $Max) { return $Number }
        Write-Host "Digite um numero entre $Min e $Max." -ForegroundColor Yellow
    }
}
function Get-JavaInfo {
    $Java = Get-Command java -ErrorAction SilentlyContinue
    if (-not $Java) { return $null }
    $Output = (& java -version 2>&1 | Out-String)
    $Match = [regex]::Match($Output, 'version "(\d+)(?:\.(\d+))?')
    if (-not $Match.Success) { $Match = [regex]::Match($Output, 'openjdk (\d+)(?:\.(\d+))?') }
    if (-not $Match.Success) { return $null }
    $Major = [int]$Match.Groups[1].Value
    if ($Major -eq 1 -and $Match.Groups[2].Success) { $Major = [int]$Match.Groups[2].Value }
    return @{ Major = $Major; Output = $Output; Path = $Java.Source }
}
function Invoke-AzxDownload([string]$Url, [string]$Destination) {
    Write-Host "Baixando: $([IO.Path]::GetFileName($Destination))" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 180
    if (-not (Test-Path $Destination) -or (Get-Item $Destination).Length -lt 1024) { throw "O download nao foi concluido corretamente: $Destination" }
}
function Get-VanillaServerMetadata([string]$Version) {
    Write-Host 'Consultando catalogo oficial do Minecraft...' -ForegroundColor DarkGray
    $Manifest = Invoke-RestMethod -Uri $ManifestUrl -TimeoutSec 45
    $Entry = $Manifest.versions | Where-Object { $_.id -eq $Version -and $_.type -eq 'release' } | Select-Object -First 1
    if (-not $Entry) { throw "A versao $Version nao foi encontrada no catalogo oficial." }
    $Metadata = Invoke-RestMethod -Uri $Entry.url -TimeoutSec 45
    if (-not $Metadata.downloads.server.url) { throw "Mojang nao disponibilizou um server.jar para $Version." }
    return $Metadata.downloads.server
}
function New-ServerProperties([string]$Path, [string]$Name, [int]$Port, [bool]$OnlineMode, [int]$Players, [int]$ViewDistance, [string]$Motd) {
    $OnlineValue = if ($OnlineMode) { 'true' } else { 'false' }
    $SafeMotd = $Motd -replace '[\r\n=]', ' '
    $Lines = @(
        "motd=$SafeMotd"
        "server-port=$Port"
        'server-ip='
        "online-mode=$OnlineValue"
        "max-players=$Players"
        "view-distance=$ViewDistance"
        'simulation-distance=6'
        'level-name=world'
        'gamemode=survival'
        'difficulty=normal'
        'spawn-protection=0'
        'enable-command-block=false'
        'enable-status=true'
        'white-list=false'
        'pvp=true'
        'max-world-size=29999984'
    )
    Set-Content -LiteralPath $Path -Value $Lines -Encoding ASCII
}
function New-InstanceFiles([string]$Folder, [string]$Name, [string]$Loader, [string]$Version, [int]$Port, [bool]$OnlineMode, [int]$Players, [int]$ViewDistance, [int]$MinRam, [int]$MaxRam) {
    foreach ($Directory in @('mods','config','world','logs','crash-reports','libraries')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Folder $Directory) | Out-Null
    }
    New-ServerProperties -Path (Join-Path $Folder 'server.properties') -Name $Name -Port $Port -OnlineMode $OnlineMode -Players $Players -ViewDistance $ViewDistance -Motd "$Name | AZX Server"
    Set-Content -LiteralPath (Join-Path $Folder 'eula.txt') -Value 'eula=false' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Folder 'mods\LEIA.txt') -Value "Coloque aqui somente mods de servidor compativeis com Minecraft $Version e $Loader. Mods de cliente podem impedir a inicializacao." -Encoding UTF8
    $Settings = [ordered]@{
        schemaVersion = 1
        name = $Name
        minecraftVersion = $Version
        loader = $Loader
        loaderVersion = if ($Loader -eq 'Forge') { $ForgeVersion } else { 'latest-at-creation' }
        port = $Port
        serverIp = ''
        onlineMode = $OnlineMode
        maxPlayers = $Players
        viewDistance = $ViewDistance
        minRamGB = $MinRam
        maxRamGB = $MaxRam
        createdAt = (Get-Date).ToString('o')
        stage = 1
    }
    $Settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Folder 'azx-server.json') -Encoding UTF8
    $Readme = @"
AZX SERVER - $Name

Minecraft: $Version
Software: $Loader
Porta: $Port
RAM: minimo $MinRam GB / maximo $MaxRam GB

PRIMEIROS PASSOS
1. Leia o arquivo eula.txt.
2. Se concordar com o EULA oficial do Minecraft, altere eula=false para eula=true.
3. Execute start.bat.
4. O mundo sera gerado pelo proprio servidor no primeiro boot.

MODS
Coloque em mods somente arquivos .jar feitos para Minecraft $Version e para o loader $Loader.
Os jogadores normalmente precisam instalar os mesmos mods no cliente.
OptiFine e um mod de cliente e nao deve ser instalado como componente do servidor.

REDE
O servidor escuta na porta TCP $Port. Para amigos fora da sua rede, sera necessario encaminhar essa porta TCP no roteador.
IP publico nao garante acesso: CGNAT ou firewall podem bloquear conexoes.

SEGURANCA
Online mode: $OnlineMode
Se online-mode estiver false, nomes podem ser falsificados. Use apenas em ambiente privado e com pessoas confiaveis.
O AZX nao aceita o EULA automaticamente.
"@
    Set-Content -LiteralPath (Join-Path $Folder 'LEIA-PRIMEIRO.txt') -Value $Readme -Encoding UTF8
}
function New-StartBat([string]$Folder, [string]$Loader, [int]$MinRam, [int]$MaxRam) {
    $Lines = @(
        '@echo off'
        'setlocal'
        'cd /d "%~dp0"'
        'title AZX SERVER - Minecraft'
        'echo.'
        'echo ==============================================='
        'echo              AZX SERVER'
        'echo ==============================================='
        'where java >nul 2>nul'
        'if errorlevel 1 ('
        '  echo ERRO: Java nao foi encontrado no PATH.'
        '  echo Instale Java 17 x64 para Minecraft 1.20.1.'
        '  echo https://adoptium.net/temurin/releases/?version=17'
        '  pause'
        '  exit /b 1'
        ')'
        'findstr /r /i "^eula=true$" eula.txt >nul'
        'if errorlevel 1 ('
        '  echo O EULA ainda nao foi aceito.'
        '  echo Leia https://aka.ms/MinecraftEULA'
        '  echo Se concordar, edite eula.txt e altere para eula=true.'
        '  start notepad.exe "%~dp0eula.txt"'
        '  pause'
        '  exit /b 1'
        ')'
    )
    if ($Loader -eq 'Forge') {
        $Lines += @(
            'if not exist "run.bat" ('
            '  echo ERRO: run.bat do Forge nao foi encontrado. A instalacao pode estar incompleta.'
            '  pause'
            '  exit /b 1'
            ')'
            'echo Iniciando servidor Forge...'
            'call run.bat nogui'
        )
    } elseif ($Loader -eq 'Fabric') {
        $Lines += @(
            'if not exist "fabric-server-launch.jar" ('
            '  echo ERRO: fabric-server-launch.jar nao foi encontrado.'
            '  pause'
            '  exit /b 1'
            ')'
            "echo Iniciando servidor Fabric... RAM: $MinRam GB - $MaxRam GB"
            ('java -Xms{0}G -Xmx{1}G -jar fabric-server-launch.jar nogui' -f $MinRam,$MaxRam)
        )
    } else {
        $Lines += @(
            'if not exist "server.jar" ('
            '  echo ERRO: server.jar nao foi encontrado.'
            '  pause'
            '  exit /b 1'
            ')'
            "echo Iniciando servidor Vanilla... RAM: $MinRam GB - $MaxRam GB"
            ('java -Xms{0}G -Xmx{1}G -jar server.jar nogui' -f $MinRam,$MaxRam)
        )
    }
    $Lines += @('echo.','echo O processo do servidor foi encerrado.','pause','endlocal')
    Set-Content -LiteralPath (Join-Path $Folder 'start.bat') -Value $Lines -Encoding ASCII
}
function Install-ManagementFiles([string]$Folder) {
    $ConfigPath = Join-Path $Folder 'azx-server.json'
    $PropertiesPath = Join-Path $Folder 'server.properties'
    if (-not (Test-Path $ConfigPath) -or -not (Test-Path $PropertiesPath)) { return }
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if (-not $Config.rconPort) {
        $Port = [int]$Config.port
        $Config | Add-Member -NotePropertyName rconPort -NotePropertyValue $(if($Port -le 55535){$Port+10000}else{$Port-10000}) -Force
    }
    $RconFile = Join-Path $Folder 'azx-rcon.txt'
    if (-not (Test-Path $RconFile)) {
        $Bytes = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($Bytes)
        $Password = [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','X').Replace('/','Y')
        Set-Content -LiteralPath $RconFile -Value $Password -Encoding ASCII
    } else { $Password = (Get-Content -LiteralPath $RconFile -Raw).Trim() }
    $Map = [ordered]@{}
    foreach ($Line in Get-Content -LiteralPath $PropertiesPath) {
        if ($Line -match '^\s*([^#\s][^=]*)=(.*)
    Write-Title
    Write-Host 'CRIAR NOVO SERVIDOR' -ForegroundColor Green
    Write-Host 'Etapa 1 suporta Minecraft 1.20.1.' -ForegroundColor Gray
    Write-Host ''
    $JavaInfo = Get-JavaInfo
    if (-not $JavaInfo -or $JavaInfo.Major -lt 17) {
        Write-Host 'Java 17 ou superior nao foi encontrado.' -ForegroundColor Red
        if ($JavaInfo) { Write-Host $JavaInfo.Output }
        Write-Host 'Instale Java 17 x64 e abra o AZX novamente:' -ForegroundColor Yellow
        Write-Host 'https://adoptium.net/temurin/releases/?version=17' -ForegroundColor Cyan
        return
    }
    Write-Host "Java detectado: versao $($JavaInfo.Major)" -ForegroundColor Green
    $Name = Read-Host 'Nome do servidor'
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = 'MeuServidor' }
    $Name = ($Name -replace '[<>:"/\\|?*]', '-').Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -in @('.', '..')) { Write-Host 'Nome invalido.' -ForegroundColor Red; return }
    if ($Name.Length -gt 48) { $Name = $Name.Substring(0,48).Trim() }
    $Folder = Join-Path $ServersRoot $Name
    if (Test-Path -LiteralPath $Folder) { Write-Host 'Ja existe um servidor com esse nome. Nenhum arquivo foi alterado.' -ForegroundColor Red; return }
    Write-Host ''
    Write-Host 'Minecraft:'
    Write-Host '1.20.1 (versao suportada nesta etapa)'
    $Version = Read-Host 'Versao [1.20.1]'
    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $SupportedMinecraft }
    if ($Version -ne $SupportedMinecraft) { Write-Host 'Nesta etapa, o criador esta validado para Minecraft 1.20.1.' -ForegroundColor Yellow; return }
    Write-Host ''
    Write-Host 'SOFTWARE DO SERVIDOR'
    Write-Host '1. Vanilla - sem mods'
    Write-Host '2. Forge 47.2.0 - mods Forge'
    Write-Host '3. Fabric - mods Fabric'
    $LoaderChoice = Read-Host 'Escolha [2]'
    if ([string]::IsNullOrWhiteSpace($LoaderChoice)) { $LoaderChoice = '2' }
    switch ($LoaderChoice) {
        '1' { $Loader = 'Vanilla' }
        '2' { $Loader = 'Forge' }
        '3' { $Loader = 'Fabric' }
        default { Write-Host 'Opcao invalida.' -ForegroundColor Red; return }
    }
    Write-Host ''
    Write-Host '1. Exigir autenticacao oficial (recomendado)'
    Write-Host '2. Permitir clientes sem autenticacao oficial (maior risco)'
    $AuthChoice = Read-Host 'Autenticacao [1]'
    if ([string]::IsNullOrWhiteSpace($AuthChoice)) { $AuthChoice = '1' }
    if ($AuthChoice -notin @('1','2')) { Write-Host 'Opcao invalida.' -ForegroundColor Red; return }
    $OnlineMode = ($AuthChoice -eq '1')
    $Port = Ask-Number 'Porta TCP' 25565 1 65535
    $Players = Ask-Number 'Maximo de jogadores' 10 1 100
    $ViewDistance = Ask-Number 'Distancia de visao' 6 2 16
    $MinRam = Ask-Number 'RAM inicial em GB' 2 1 64
    $MaxRam = Ask-Number 'RAM maxima em GB' ([Math]::Max(4,$MinRam)) $MinRam 64
    Write-Host ''
    Write-Host 'RESUMO DA INSTALACAO' -ForegroundColor Cyan
    Write-Host "Nome: $Name"
    Write-Host "Minecraft: $Version"
    Write-Host "Software: $Loader"
    Write-Host "Porta TCP: $Port"
    Write-Host "Jogadores: $Players"
    Write-Host "RAM: $MinRam-$MaxRam GB"
    Write-Host "Autenticacao oficial: $OnlineMode"
    $Confirm = Read-Host 'Criar este servidor? (S/N)'
    if ($Confirm -notmatch '^(s|sim)$') { Write-Host 'Criacao cancelada.'; return }
    New-Item -ItemType Directory -Path $Folder | Out-Null
    try {
        New-InstanceFiles -Folder $Folder -Name $Name -Loader $Loader -Version $Version -Port $Port -OnlineMode $OnlineMode -Players $Players -ViewDistance $ViewDistance -MinRam $MinRam -MaxRam $MaxRam
        if ($Loader -eq 'Vanilla') {
            $ServerDownload = Get-VanillaServerMetadata -Version $Version
            $ServerJar = Join-Path $Folder 'server.jar'
            Invoke-AzxDownload -Url $ServerDownload.url -Destination $ServerJar
            $Hash = (Get-FileHash -LiteralPath $ServerJar -Algorithm SHA1).Hash.ToLowerInvariant()
            if ($Hash -ne $ServerDownload.sha1.ToLowerInvariant()) { Remove-Item -LiteralPath $ServerJar -Force; throw 'A verificacao SHA-1 do server.jar falhou. O arquivo foi removido.' }
        } elseif ($Loader -eq 'Forge') {
            $ForgeCoordinate = "$Version-$ForgeVersion"
            $Installer = Join-Path $Folder "forge-$ForgeCoordinate-installer.jar"
            $ForgeUrl = "https://maven.minecraftforge.net/net/minecraftforge/forge/$ForgeCoordinate/forge-$ForgeCoordinate-installer.jar"
            Invoke-AzxDownload -Url $ForgeUrl -Destination $Installer
            Write-Host 'Instalando Forge no modo servidor...' -ForegroundColor Cyan
            Push-Location $Folder
            try {
                & java -jar $Installer --installServer
                if ($LASTEXITCODE -ne 0) { throw "O instalador Forge retornou codigo $LASTEXITCODE." }
            } finally { Pop-Location }
            Remove-Item -LiteralPath $Installer -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path (Join-Path $Folder 'run.bat'))) { throw 'Forge terminou sem gerar run.bat. Verifique a conexao e os logs do instalador.' }
            Set-Content -LiteralPath (Join-Path $Folder 'user_jvm_args.txt') -Value @("-Xms$($MinRam)G","-Xmx$($MaxRam)G") -Encoding ASCII
        } elseif ($Loader -eq 'Fabric') {
            Write-Host 'Consultando versoes oficiais do Fabric...' -ForegroundColor DarkGray
            $LoaderList = Invoke-RestMethod -Uri "https://meta.fabricmc.net/v2/versions/loader/$Version" -TimeoutSec 45
            $InstallerList = Invoke-RestMethod -Uri 'https://meta.fabricmc.net/v2/versions/installer' -TimeoutSec 45
            $FabricLoaderVersion = $LoaderList[0].loader.version
            $FabricInstallerVersion = $InstallerList[0].version
            if (-not $FabricLoaderVersion -or -not $FabricInstallerVersion) { throw 'Nao foi possivel obter as versoes oficiais do Fabric.' }
            $FabricUrl = "https://meta.fabricmc.net/v2/versions/loader/$Version/$FabricLoaderVersion/$FabricInstallerVersion/server/jar"
            Invoke-AzxDownload -Url $FabricUrl -Destination (Join-Path $Folder 'fabric-server-launch.jar')
            $SettingsPath = Join-Path $Folder 'azx-server.json'
            $Settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
            $Settings.loaderVersion = $FabricLoaderVersion
            $Settings.installerVersion = $FabricInstallerVersion
            $Settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
        }
        New-StartBat -Folder $Folder -Loader $Loader -MinRam $MinRam -MaxRam $MaxRam
        Install-ManagementFiles -Folder $Folder
        Write-Host ''
        Write-Host 'SERVIDOR CRIADO COM SUCESSO!' -ForegroundColor Green
        Write-Host "Pasta: $Folder"
        Write-Host 'Antes do primeiro boot: leia e aceite manualmente o EULA, se concordar.'
        Write-Host 'O mundo real sera gerado pelo Minecraft quando o servidor iniciar pela primeira vez.'
        if (-not $OnlineMode) { Write-Host 'ATENCAO: online-mode=false permite falsificacao de nomes. Proteja o servidor.' -ForegroundColor Yellow }
        Invoke-Item $Folder
    } catch {
        Write-Host ''
        Write-Host "FALHA NA CRIACAO: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "A pasta foi mantida para diagnostico: $Folder" -ForegroundColor Yellow
        Write-Host 'Confira sua internet, espaco em disco e os arquivos baixados. Nao inicie uma instalacao incompleta.'
    }
}
function Show-Servers {
    $Items = @(Get-ChildItem -LiteralPath $ServersRoot -Directory -ErrorAction SilentlyContinue)
    if ($Items.Count -eq 0) { Write-Host 'Nenhum servidor criado ainda.' -ForegroundColor Yellow; return }
    Write-Host 'SERVIDORES AZX' -ForegroundColor Cyan
    foreach ($Item in $Items) {
        $ConfigPath = Join-Path $Item.FullName 'azx-server.json'
        if (Test-Path $ConfigPath) {
            try {
                $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
                Write-Host ("- {0} | Minecraft {1} | {2} | porta {3}" -f $Item.Name,$Config.minecraftVersion,$Config.loader,$Config.port)
            } catch { Write-Host "- $($Item.Name) | configuracao nao reconhecida" }
        } else { Write-Host "- $($Item.Name)" }
    }
}
function Show-Java {
    $Info = Get-JavaInfo
    if ($Info) { Write-Host "Java $($Info.Major) encontrado em $($Info.Path)" -ForegroundColor Green; Write-Host $Info.Output }
    else { Write-Host 'Java nao encontrado. Para Minecraft 1.20.1, instale Java 17 x64:' -ForegroundColor Red; Write-Host 'https://adoptium.net/temurin/releases/?version=17' -ForegroundColor Cyan }
}
while ($true) {
    Write-Title
    Write-Host '1. Criar servidor'
    Write-Host '2. Listar servidores criados'
    Write-Host '3. Verificar Java'
    Write-Host '4. Abrir pasta SERVERS'
    Write-Host '5. Gerenciar servidor'
    Write-Host '6. Sair'
    Write-Host ''
    $Choice = Read-Host 'Opcao'
    switch ($Choice) {
        '1' { Write-Title; New-AzxServer; Write-Host ''; Read-Host 'Pressione Enter para voltar' | Out-Null }
        '2' { Write-Title; Show-Servers; Write-Host ''; Read-Host 'Pressione Enter para voltar' | Out-Null }
        '3' { Write-Title; Show-Java; Write-Host ''; Read-Host 'Pressione Enter para voltar' | Out-Null }
        '4' { Invoke-Item $ServersRoot }
        '5' { Write-Title; Select-ServerForManagement; Read-Host 'Pressione Enter para voltar' | Out-Null }
        '6' { return }
        default { Write-Host 'Opcao invalida.' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }
}
) { $Map[$Matches[1]] = $Matches[2] }
    }
    $Map['enable-rcon'] = 'true'
    $Map['rcon.port'] = "$($Config.rconPort)"
    $Map['rcon.password'] = $Password
    Copy-Item -LiteralPath $PropertiesPath -Destination "$PropertiesPath.azx-backup" -Force
    $Lines = foreach ($Key in $Map.Keys) { "$Key=$($Map[$Key])" }
    Set-Content -LiteralPath $PropertiesPath -Value $Lines -Encoding ASCII
    $Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    foreach ($Action in @('configure','stop','restart','reset')) {
        $Bat = @(
            '@echo off'
            'setlocal'
            'cd /d "%~dp0"'
            'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\launcher\server-manager.ps1" -ServerPath "%~dp0." -Action ' + $Action
            'if errorlevel 1 echo O AZX Manager encontrou um erro. Consulte a mensagem acima.'
            'pause'
            'endlocal'
        )
        Set-Content -LiteralPath (Join-Path $Folder "$Action.bat") -Value $Bat -Encoding ASCII
    }
}
function Select-ServerForManagement {
    $Items = @(Get-ChildItem -LiteralPath $ServersRoot -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'azx-server.json') })
    if ($Items.Count -eq 0) { Write-Host 'Nenhuma instancia AZX encontrada.' -ForegroundColor Yellow; return }
    for ($i=0; $i -lt $Items.Count; $i++) { Write-Host "$($i+1). $($Items[$i].Name)" }
    $Pick = Read-Host 'Escolha o servidor (Enter cancela)'
    $N = 0
    if ([int]::TryParse($Pick,[ref]$N) -and $N -ge 1 -and $N -le $Items.Count) {
        Install-ManagementFiles -Folder $Items[$N-1].FullName
        Invoke-Item (Join-Path $Items[$N-1].FullName 'configure.bat')
    }
}
function New-AzxServer {
    Write-Title
    Write-Host 'CRIAR NOVO SERVIDOR' -ForegroundColor Green
    Write-Host 'Etapa 1 suporta Minecraft 1.20.1.' -ForegroundColor Gray
    Write-Host ''
    $JavaInfo = Get-JavaInfo
    if (-not $JavaInfo -or $JavaInfo.Major -lt 17) {
        Write-Host 'Java 17 ou superior nao foi encontrado.' -ForegroundColor Red
        if ($JavaInfo) { Write-Host $JavaInfo.Output }
        Write-Host 'Instale Java 17 x64 e abra o AZX novamente:' -ForegroundColor Yellow
        Write-Host 'https://adoptium.net/temurin/releases/?version=17' -ForegroundColor Cyan
        return
    }
    Write-Host "Java detectado: versao $($JavaInfo.Major)" -ForegroundColor Green
    $Name = Read-Host 'Nome do servidor'
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = 'MeuServidor' }
    $Name = ($Name -replace '[<>:"/\\|?*]', '-').Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -in @('.', '..')) { Write-Host 'Nome invalido.' -ForegroundColor Red; return }
    if ($Name.Length -gt 48) { $Name = $Name.Substring(0,48).Trim() }
    $Folder = Join-Path $ServersRoot $Name
    if (Test-Path -LiteralPath $Folder) { Write-Host 'Ja existe um servidor com esse nome. Nenhum arquivo foi alterado.' -ForegroundColor Red; return }
    Write-Host ''
    Write-Host 'Minecraft:'
    Write-Host '1.20.1 (versao suportada nesta etapa)'
    $Version = Read-Host 'Versao [1.20.1]'
    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $SupportedMinecraft }
    if ($Version -ne $SupportedMinecraft) { Write-Host 'Nesta etapa, o criador esta validado para Minecraft 1.20.1.' -ForegroundColor Yellow; return }
    Write-Host ''
    Write-Host 'SOFTWARE DO SERVIDOR'
    Write-Host '1. Vanilla - sem mods'
    Write-Host '2. Forge 47.2.0 - mods Forge'
    Write-Host '3. Fabric - mods Fabric'
    $LoaderChoice = Read-Host 'Escolha [2]'
    if ([string]::IsNullOrWhiteSpace($LoaderChoice)) { $LoaderChoice = '2' }
    switch ($LoaderChoice) {
        '1' { $Loader = 'Vanilla' }
        '2' { $Loader = 'Forge' }
        '3' { $Loader = 'Fabric' }
        default { Write-Host 'Opcao invalida.' -ForegroundColor Red; return }
    }
    Write-Host ''
    Write-Host '1. Exigir autenticacao oficial (recomendado)'
    Write-Host '2. Permitir clientes sem autenticacao oficial (maior risco)'
    $AuthChoice = Read-Host 'Autenticacao [1]'
    if ([string]::IsNullOrWhiteSpace($AuthChoice)) { $AuthChoice = '1' }
    if ($AuthChoice -notin @('1','2')) { Write-Host 'Opcao invalida.' -ForegroundColor Red; return }
    $OnlineMode = ($AuthChoice -eq '1')
    $Port = Ask-Number 'Porta TCP' 25565 1 65535
    $Players = Ask-Number 'Maximo de jogadores' 10 1 100
    $ViewDistance = Ask-Number 'Distancia de visao' 6 2 16
    $MinRam = Ask-Number 'RAM inicial em GB' 2 1 64
    $MaxRam = Ask-Number 'RAM maxima em GB' ([Math]::Max(4,$MinRam)) $MinRam 64
    Write-Host ''
    Write-Host 'RESUMO DA INSTALACAO' -ForegroundColor Cyan
    Write-Host "Nome: $Name"
    Write-Host "Minecraft: $Version"
    Write-Host "Software: $Loader"
    Write-Host "Porta TCP: $Port"
    Write-Host "Jogadores: $Players"
    Write-Host "RAM: $MinRam-$MaxRam GB"
    Write-Host "Autenticacao oficial: $OnlineMode"
    $Confirm = Read-Host 'Criar este servidor? (S/N)'
    if ($Confirm -notmatch '^(s|sim)$') { Write-Host 'Criacao cancelada.'; return }
    New-Item -ItemType Directory -Path $Folder | Out-Null
    try {
        New-InstanceFiles -Folder $Folder -Name $Name -Loader $Loader -Version $Version -Port $Port -OnlineMode $OnlineMode -Players $Players -ViewDistance $ViewDistance -MinRam $MinRam -MaxRam $MaxRam
        if ($Loader -eq 'Vanilla') {
            $ServerDownload = Get-VanillaServerMetadata -Version $Version
            $ServerJar = Join-Path $Folder 'server.jar'
            Invoke-AzxDownload -Url $ServerDownload.url -Destination $ServerJar
            $Hash = (Get-FileHash -LiteralPath $ServerJar -Algorithm SHA1).Hash.ToLowerInvariant()
            if ($Hash -ne $ServerDownload.sha1.ToLowerInvariant()) { Remove-Item -LiteralPath $ServerJar -Force; throw 'A verificacao SHA-1 do server.jar falhou. O arquivo foi removido.' }
        } elseif ($Loader -eq 'Forge') {
            $ForgeCoordinate = "$Version-$ForgeVersion"
            $Installer = Join-Path $Folder "forge-$ForgeCoordinate-installer.jar"
            $ForgeUrl = "https://maven.minecraftforge.net/net/minecraftforge/forge/$ForgeCoordinate/forge-$ForgeCoordinate-installer.jar"
            Invoke-AzxDownload -Url $ForgeUrl -Destination $Installer
            Write-Host 'Instalando Forge no modo servidor...' -ForegroundColor Cyan
            Push-Location $Folder
            try {
                & java -jar $Installer --installServer
                if ($LASTEXITCODE -ne 0) { throw "O instalador Forge retornou codigo $LASTEXITCODE." }
            } finally { Pop-Location }
            Remove-Item -LiteralPath $Installer -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path (Join-Path $Folder 'run.bat'))) { throw 'Forge terminou sem gerar run.bat. Verifique a conexao e os logs do instalador.' }
            Set-Content -LiteralPath (Join-Path $Folder 'user_jvm_args.txt') -Value @("-Xms$($MinRam)G","-Xmx$($MaxRam)G") -Encoding ASCII
        } elseif ($Loader -eq 'Fabric') {
            Write-Host 'Consultando versoes oficiais do Fabric...' -ForegroundColor DarkGray
            $LoaderList = Invoke-RestMethod -Uri "https://meta.fabricmc.net/v2/versions/loader/$Version" -TimeoutSec 45
            $InstallerList = Invoke-RestMethod -Uri 'https://meta.fabricmc.net/v2/versions/installer' -TimeoutSec 45
            $FabricLoaderVersion = $LoaderList[0].loader.version
            $FabricInstallerVersion = $InstallerList[0].version
            if (-not $FabricLoaderVersion -or -not $FabricInstallerVersion) { throw 'Nao foi possivel obter as versoes oficiais do Fabric.' }
            $FabricUrl = "https://meta.fabricmc.net/v2/versions/loader/$Version/$FabricLoaderVersion/$FabricInstallerVersion/server/jar"
            Invoke-AzxDownload -Url $FabricUrl -Destination (Join-Path $Folder 'fabric-server-launch.jar')
            $SettingsPath = Join-Path $Folder 'azx-server.json'
            $Settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
            $Settings.loaderVersion = $FabricLoaderVersion
            $Settings.installerVersion = $FabricInstallerVersion
            $Settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
        }
        New-StartBat -Folder $Folder -Loader $Loader -MinRam $MinRam -MaxRam $MaxRam
        Write-Host ''
        Write-Host 'SERVIDOR CRIADO COM SUCESSO!' -ForegroundColor Green
        Write-Host "Pasta: $Folder"
        Write-Host 'Antes do primeiro boot: leia e aceite manualmente o EULA, se concordar.'
        Write-Host 'O mundo real sera gerado pelo Minecraft quando o servidor iniciar pela primeira vez.'
        if (-not $OnlineMode) { Write-Host 'ATENCAO: online-mode=false permite falsificacao de nomes. Proteja o servidor.' -ForegroundColor Yellow }
        Invoke-Item $Folder
    } catch {
        Write-Host ''
        Write-Host "FALHA NA CRIACAO: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "A pasta foi mantida para diagnostico: $Folder" -ForegroundColor Yellow
        Write-Host 'Confira sua internet, espaco em disco e os arquivos baixados. Nao inicie uma instalacao incompleta.'
    }
}
function Show-Servers {
    $Items = @(Get-ChildItem -LiteralPath $ServersRoot -Directory -ErrorAction SilentlyContinue)
    if ($Items.Count -eq 0) { Write-Host 'Nenhum servidor criado ainda.' -ForegroundColor Yellow; return }
    Write-Host 'SERVIDORES AZX' -ForegroundColor Cyan
    foreach ($Item in $Items) {
        $ConfigPath = Join-Path $Item.FullName 'azx-server.json'
        if (Test-Path $ConfigPath) {
            try {
                $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
                Write-Host ("- {0} | Minecraft {1} | {2} | porta {3}" -f $Item.Name,$Config.minecraftVersion,$Config.loader,$Config.port)
            } catch { Write-Host "- $($Item.Name) | configuracao nao reconhecida" }
        } else { Write-Host "- $($Item.Name)" }
    }
}
function Show-Java {
    $Info = Get-JavaInfo
    if ($Info) { Write-Host "Java $($Info.Major) encontrado em $($Info.Path)" -ForegroundColor Green; Write-Host $Info.Output }
    else { Write-Host 'Java nao encontrado. Para Minecraft 1.20.1, instale Java 17 x64:' -ForegroundColor Red; Write-Host 'https://adoptium.net/temurin/releases/?version=17' -ForegroundColor Cyan }
}
while ($true) {
    Write-Title
    Write-Host '1. Criar servidor'
    Write-Host '2. Listar servidores criados'
    Write-Host '3. Verificar Java'
    Write-Host '4. Abrir pasta SERVERS'
    Write-Host '5. Gerenciar servidor'
    Write-Host '6. Sair'
    Write-Host ''
    $Choice = Read-Host 'Opcao'
    switch ($Choice) {
        '1' { Write-Title; New-AzxServer; Write-Host ''; Read-Host 'Pressione Enter para voltar' | Out-Null }
        '2' { Write-Title; Show-Servers; Write-Host ''; Read-Host 'Pressione Enter para voltar' | Out-Null }
        '3' { Write-Title; Show-Java; Write-Host ''; Read-Host 'Pressione Enter para voltar' | Out-Null }
        '4' { Invoke-Item $ServersRoot }
        '5' { Write-Title; Select-ServerForManagement; Read-Host 'Pressione Enter para voltar' | Out-Null }
        '6' { return }
        default { Write-Host 'Opcao invalida.' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }
}
