$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ServersRoot = Join-Path $Root 'servers'
New-Item -ItemType Directory -Force -Path $ServersRoot | Out-Null
function Ask-Number($label,$default,$min,$max) {
  while ($true) {
    $answer = Read-Host "$label [$default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return [int]$default }
    $number = 0
    if ([int]::TryParse($answer,[ref]$number) -and $number -ge $min -and $number -le $max) { return $number }
    Write-Host "Digite um numero entre $min e $max." -ForegroundColor Yellow
  }
}
function New-AzxServer {
  Clear-Host
  Write-Host '=== NOVO SERVIDOR AZX ===' -ForegroundColor Green
  $name = Read-Host 'Nome do servidor'
  if ([string]::IsNullOrWhiteSpace($name)) { $name = 'MeuServidor' }
  $name = ($name -replace '[<>:"/\\|?*]','-').Trim()
  $folder = Join-Path $ServersRoot $name
  if (Test-Path $folder) { Write-Host 'Essa pasta ja existe.' -ForegroundColor Red; return }
  Write-Host '1. Forge 1.20.1 (mods)'
  Write-Host '2. Vanilla 1.20.1'
  $loader = Read-Host 'Software [1]'
  if ([string]::IsNullOrWhiteSpace($loader)) { $loader = '1' }
  if ($loader -notin @('1','2')) { Write-Host 'Opcao invalida.'; return }
  Write-Host '1. Exigir contas oficiais (recomendado)'
  Write-Host '2. Permitir clientes sem autenticacao oficial'
  $auth = Read-Host 'Autenticacao [1]'
  if ([string]::IsNullOrWhiteSpace($auth)) { $auth = '1' }
  $online = if ($auth -eq '2') { 'false' } else { 'true' }
  $players = Ask-Number 'Maximo de jogadores' 5 1 100
  $view = Ask-Number 'Distancia de visao' 6 2 16
  $minRam = Ask-Number 'RAM inicial em GB' 1 1 8
  $maxRam = Ask-Number 'RAM maxima em GB' 2 1 12
  if ($maxRam -lt $minRam) { $maxRam = $minRam }
  $mods = Join-Path $folder 'mods'
  New-Item -ItemType Directory -Force -Path $folder,$mods,(Join-Path $folder 'config'),(Join-Path $folder 'world') | Out-Null
  $properties = @("motd=$name - AZX Server",'server-port=25565','server-ip=',"online-mode=$online","max-players=$players","view-distance=$view",'simulation-distance=4','enable-command-block=false','spawn-protection=0')
  Set-Content -Path (Join-Path $folder 'server.properties') -Value $properties -Encoding ASCII
  Set-Content -Path (Join-Path $folder 'eula.txt') -Value 'eula=false' -Encoding ASCII
  $settings = @{name=$name;minecraft='1.20.1';loader=$(if($loader -eq '1'){'Forge'}else{'Vanilla'});forgeVersion='47.2.0';onlineMode=($online -eq 'true');minRamGB=$minRam;maxRamGB=$maxRam;port=25565} | ConvertTo-Json
  Set-Content -Path (Join-Path $folder 'azx-server.json') -Value $settings -Encoding UTF8
  Set-Content -Path (Join-Path $mods 'LEIA.txt') -Value 'Coloque aqui os mods .jar compativeis com o servidor.' -Encoding UTF8
  if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Host 'Java 17 nao encontrado. Instale: https://adoptium.net/temurin/releases/?version=17' -ForegroundColor Red
    return
  }
  $version = (& java -version 2>&1 | Out-String)
  if ($version -notmatch 'version "17\.' -and $version -notmatch 'openjdk 17\.') {
    Write-Host 'Minecraft 1.20.1 requer Java 17. Versao detectada:' -ForegroundColor Red
    Write-Host $version
    return
  }
  if ($loader -eq '1') {
    $forgeVersion = '1.20.1-47.2.0'
    $installer = Join-Path $folder "forge-$forgeVersion-installer.jar"
    $url = "https://maven.minecraftforge.net/net/minecraftforge/forge/$forgeVersion/forge-$forgeVersion-installer.jar"
    Write-Host 'Baixando instalador oficial do Forge...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $installer
    Push-Location $folder
    try {
      & java -jar $installer --installServer
      if ($LASTEXITCODE -ne 0) { throw "Instalador Forge falhou: codigo $LASTEXITCODE" }
    } finally { Pop-Location }
    Remove-Item $installer -Force -ErrorAction SilentlyContinue
    $jvmArgs = [string]::Join([Environment]::NewLine,@('-Xms' + $minRam + 'G','-Xmx' + $maxRam + 'G'))
    Set-Content -Path (Join-Path $folder 'user_jvm_args.txt') -Value $jvmArgs -Encoding ASCII
  } else {
    Write-Host 'Baixe o server.jar oficial de Minecraft.net e coloque-o nesta pasta.' -ForegroundColor Yellow
  }
  $start = @(
    '@echo off','cd /d "%~dp0"','title AZX Server',
    'findstr /i "eula=true" eula.txt >nul',
    'if errorlevel 1 (','  echo Leia e aceite o EULA em eula.txt antes de iniciar.','  notepad eula.txt','  pause','  exit /b 1',')',
    'if exist "run.bat" (','  call run.bat',') else if exist "server.jar" (',
    ('  java -Xms' + $minRam + 'G -Xmx' + $maxRam + 'G -jar server.jar nogui'),
    ') else (','  echo Inicializador nao encontrado.','  pause',')','pause'
  )
  Set-Content -Path (Join-Path $folder 'start.bat') -Value $start -Encoding ASCII
  Set-Content -Path (Join-Path $folder 'stop.bat') -Value @('@echo off','echo Digite stop no console do servidor para desligar corretamente.','pause') -Encoding ASCII
  Write-Host "Servidor preparado em: $folder" -ForegroundColor Green
  Write-Host 'O EULA continua desativado. Leia e aceite manualmente antes de iniciar.'
  Invoke-Item $folder
}
function Open-ServerFolder {
  $items = @(Get-ChildItem $ServersRoot -Directory -ErrorAction SilentlyContinue)
  if ($items.Count -eq 0) { Write-Host 'Nenhum servidor criado.'; return }
  for ($i=0; $i -lt $items.Count; $i++) { Write-Host "$($i+1). $($items[$i].Name)" }
  $pick = Read-Host 'Numero para abrir (Enter cancela)'
  $n = 0
  if ([int]::TryParse($pick,[ref]$n) -and $n -ge 1 -and $n -le $items.Count) { Invoke-Item $items[$n-1].FullName }
}
while ($true) {
  Clear-Host
  Write-Host '========== AZX SERVER ==========' -ForegroundColor Yellow
  Write-Host '1. Criar servidor'
  Write-Host '2. Abrir pasta dos servidores'
  Write-Host '3. Verificar Java'
  Write-Host '4. Sair'
  $choice = Read-Host 'Opcao'
  switch ($choice) {
    '1' { New-AzxServer; Read-Host 'Pressione Enter para voltar' | Out-Null }
    '2' { Open-ServerFolder; Read-Host 'Pressione Enter para voltar' | Out-Null }
    '3' { if (Get-Command java -ErrorAction SilentlyContinue) { & java -version } else { Write-Host 'Java nao encontrado.' -ForegroundColor Red }; Read-Host 'Enter' | Out-Null }
    '4' { return }
    default { Write-Host 'Opcao invalida.'; Start-Sleep -Seconds 1 }
  }
}
