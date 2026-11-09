param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('menu','start','status','set-address','disable')]
    [string]$Action,
    [string]$ServerPath
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $PSScriptRoot
$AgentDirectory = Join-Path $Root 'services\playit'
$AgentPath = Join-Path $AgentDirectory 'playit.exe'
$ReleaseApi = 'https://api.github.com/repos/playit-cloud/playit-agent/releases/latest'
$DashboardUrl = 'https://playit.gg/account/setup/new-tunnel'

if ($ServerPath) {
    $ServerPath = [IO.Path]::GetFullPath($ServerPath)
    $ConfigPath = Join-Path $ServerPath 'azx-server.json'
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw 'Instancia AZX invalida: azx-server.json ausente.' }
    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} else { $Config = $null }

function Save-ServerConfig {
    $Config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}
function Ensure-ExternalSettings {
    if (-not $Config.externalAccess) {
        $Config | Add-Member -NotePropertyName externalAccess -NotePropertyValue ([pscustomobject]@{
            provider = 'playit'
            enabled = $false
            address = ''
        }) -Force
    }
    if (-not $Config.externalAccess.provider) { $Config.externalAccess.provider = 'playit' }
    if ($null -eq $Config.externalAccess.enabled) { $Config.externalAccess.enabled = $false }
    if ($null -eq $Config.externalAccess.address) { $Config.externalAccess.address = '' }
}
function Get-PlayitProcess {
    try {
        $FullPath = [IO.Path]::GetFullPath($AgentPath)
        return Get-CimInstance Win32_Process -Filter "Name='playit.exe'" -ErrorAction Stop |
            Where-Object { $_.ExecutablePath -and $_.ExecutablePath.Equals($FullPath,[StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
    } catch { return $null }
}
function Install-PlayitAgent {
    if (Test-Path -LiteralPath $AgentPath) {
        $Bytes = [IO.File]::ReadAllBytes($AgentPath)
        if ($Bytes.Length -gt 100000 -and $Bytes[0] -eq 0x4D -and $Bytes[1] -eq 0x5A) { return }
        Remove-Item -LiteralPath $AgentPath -Force
    }
    New-Item -ItemType Directory -Force -Path $AgentDirectory | Out-Null
    Write-Host 'Consultando a versao oficial do agente Playit...' -ForegroundColor Cyan
    $Release = Invoke-RestMethod -Uri $ReleaseApi -Headers @{ 'User-Agent' = 'AZX-Server'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 45
    $Asset = @($Release.assets | Where-Object {
        $_.name -match '(?i)windows' -and $_.name -match '(?i)(x86_64|amd64)' -and $_.name -match '(?i)\.exe$'
    } | Select-Object -First 1)
    if (-not $Asset.Count) {
        $Asset = @($Release.assets | Where-Object { $_.name -match '(?i)windows.*\.exe$' } | Select-Object -First 1)
    }
    if (-not $Asset.Count -or -not $Asset[0].browser_download_url) {
        throw 'Nao encontrei um executavel Windows x64 na ultima release oficial do Playit. Nenhum arquivo foi instalado.'
    }
    $TempPath = "$AgentPath.download"
    try {
        Write-Host "Baixando agente oficial: $($Asset[0].name)" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $Asset[0].browser_download_url -OutFile $TempPath -UseBasicParsing -TimeoutSec 180
        $Bytes = [IO.File]::ReadAllBytes($TempPath)
        if ($Bytes.Length -lt 100000 -or $Bytes[0] -ne 0x4D -or $Bytes[1] -ne 0x5A) {
            throw 'O download nao parece ser um executavel Windows valido.'
        }
        if ($Asset[0].digest -and $Asset[0].digest -match '^sha256:(.+)$') {
            $Actual = (Get-FileHash -LiteralPath $TempPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($Actual -ne $Matches[1].ToLowerInvariant()) { throw 'O SHA-256 do agente Playit nao confere. O download foi descartado.' }
        }
        Move-Item -LiteralPath $TempPath -Destination $AgentPath -Force
        Write-Host "Agente instalado: $($Release.tag_name)" -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    }
}
function Start-PlayitAgent {
    Install-PlayitAgent
    $Existing = Get-PlayitProcess
    if ($Existing) {
        Write-Host 'O agente Playit ja esta em execucao.' -ForegroundColor Green
        return
    }
    $Process = Start-Process -FilePath $AgentPath -WorkingDirectory $AgentDirectory -PassThru
    Start-Sleep -Seconds 2
    $Process.Refresh()
    if ($Process.HasExited) {
        throw "O agente Playit encerrou imediatamente (codigo $($Process.ExitCode)). Abra o agente manualmente para ver o erro."
    }
    Write-Host 'Agente Playit iniciado em uma janela separada.' -ForegroundColor Green
    Write-Host 'Na primeira execucao, siga o link/codigo mostrado nessa janela para vincular sua conta Playit.' -ForegroundColor Yellow
}
function Set-PublicAddress {
    $Address = (Read-Host 'Cole o endereco publico Minecraft exibido no painel Playit (ex.: exemplo.joinmc.link)').Trim()
    if ($Address -notmatch '^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::[0-9]{1,5})?$') {
        Write-Host 'Endereco invalido. Cole somente hostname ou hostname:porta.' -ForegroundColor Yellow
        return
    }
    if ($Address -match ':(\d+)$' -and [int]$Matches[1] -gt 65535) {
        Write-Host 'Porta invalida.' -ForegroundColor Yellow
        return
    }
    Ensure-ExternalSettings
    $Config.externalAccess.enabled = $true
    $Config.externalAccess.provider = 'playit'
    $Config.externalAccess.address = $Address
    Save-ServerConfig
    Write-Host "Endereco publico salvo: $Address" -ForegroundColor Green
}
function Show-Status {
    Ensure-ExternalSettings
    Write-Host 'AZX EXTERNAL ACCESS - PLAYIT' -ForegroundColor Cyan
    Write-Host ("Agente instalado: {0}" -f (Test-Path -LiteralPath $AgentPath))
    $Process = Get-PlayitProcess
    Write-Host ("Agente em execucao: {0}" -f [bool]$Process)
    if ($Config) {
        Write-Host ("Integracao habilitada: {0}" -f [bool]$Config.externalAccess.enabled)
        Write-Host ("Endereco publico: {0}" -f $(if ($Config.externalAccess.address) { $Config.externalAccess.address } else { 'ainda nao informado' }))
        Write-Host ("Porta local do Minecraft: {0}/TCP" -f $Config.port)
    }
}
function Disable-Integration {
    Ensure-ExternalSettings
    $Config.externalAccess.enabled = $false
    Save-ServerConfig
    Write-Host 'Integracao desativada para esta instancia. O agente global nao foi encerrado, pois pode atender outros servidores AZX.' -ForegroundColor Yellow
}
function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host "AZX EXTERNAL ACCESS - $($Config.name)" -ForegroundColor Cyan
        Write-Host '1. Habilitar Playit / instalar e iniciar agente'
        Write-Host '2. Salvar endereco publico do tunel'
        Write-Host '3. Ver status'
        Write-Host '4. Desativar integracao nesta instancia'
        Write-Host '0. Voltar'
        $Choice = Read-Host 'Opcao'
        try {
            switch ($Choice) {
                '1' {
                    Ensure-ExternalSettings
                    $Config.externalAccess.enabled = $true
                    $Config.externalAccess.provider = 'playit'
                    Save-ServerConfig
                    Start-PlayitAgent
                    Write-Host ''
                    Write-Host 'PROXIMOS PASSOS (somente na primeira configuracao):' -ForegroundColor Cyan
                    Write-Host '1. Vincule o agente a sua conta pelo link/codigo mostrado na janela do Playit.'
                    Write-Host '2. No painel, crie um tunel Minecraft Java apontando para 127.0.0.1 e a porta deste servidor.'
                    Write-Host '3. Copie o endereco publico gerado e use a opcao 2 para salva-lo no AZX.'
                    Start-Process $DashboardUrl
                }
                '2' { Set-PublicAddress }
                '3' { Show-Status }
                '4' { Disable-Integration }
                '0' { return }
                default { Write-Host 'Opcao invalida.' -ForegroundColor Yellow }
            }
        } catch { Write-Host "ERRO PLAYIT: $($_.Exception.Message)" -ForegroundColor Red }
        if ($Choice -ne '0') { Read-Host 'Pressione Enter para continuar' | Out-Null }
    }
}
switch ($Action) {
    'start' {
        if (-not $Config) { throw 'ServerPath e obrigatorio para iniciar a integracao.' }
        Ensure-ExternalSettings
        if (-not $Config.externalAccess.enabled) { Write-Host 'Playit desativado nesta instancia. Use a opcao External Access no AZX para habilitar.'; exit 0 }
        try { Start-PlayitAgent }
        catch {
            Write-Host "AZX: nao foi possivel iniciar o Playit: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host 'O servidor Minecraft continuara iniciando localmente.'
            exit 0
        }
    }
    'status' { Show-Status }
    'set-address' { Set-PublicAddress }
    'disable' { Disable-Integration }
    'menu' { if (-not $Config) { throw 'ServerPath e obrigatorio para abrir o menu.' }; Ensure-ExternalSettings; Show-Menu }
}