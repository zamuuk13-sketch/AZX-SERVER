param([Parameter(Mandatory=$true)][string]$Folder)
$ErrorActionPreference='Stop'
$Folder=[IO.Path]::GetFullPath($Folder)
$ConfigPath=Join-Path $Folder 'azx-server.json'
$PropertiesPath=Join-Path $Folder 'server.properties'
if(!(Test-Path $ConfigPath) -or !(Test-Path $PropertiesPath)){throw 'Pasta nao e uma instancia AZX valida.'}
$Config=Get-Content $ConfigPath -Raw | ConvertFrom-Json
$GamePort=[int]$Config.port
if(!$Config.rconPort){$Config | Add-Member -NotePropertyName rconPort -NotePropertyValue $(if($GamePort -le 55535){$GamePort+10000}else{$GamePort-10000}) -Force}
$RconFile=Join-Path $Folder 'azx-rcon.txt'
if(!(Test-Path $RconFile)){
    $Bytes=New-Object byte[] 32
    $Rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try{$Rng.GetBytes($Bytes)}finally{$Rng.Dispose()}
    $Password=[Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','X').Replace('/','Y')
    Set-Content -LiteralPath $RconFile -Value $Password -Encoding ASCII
}else{$Password=(Get-Content -LiteralPath $RconFile -Raw).Trim()}
$Map=[ordered]@{}
foreach($Line in Get-Content -LiteralPath $PropertiesPath){
    if($Line -match '^\s*([^#\s][^=]*)=(.*)$'){$Map[$Matches[1]]=$Matches[2]}
}
$Map['enable-rcon']='true'
$Map['rcon.port']="$($Config.rconPort)"
$Map['rcon.password']=$Password
$Map['broadcast-rcon-to-ops']='false'
Copy-Item -LiteralPath $PropertiesPath -Destination "$PropertiesPath.azx-backup" -Force
$Lines=foreach($Key in $Map.Keys){"$Key=$($Map[$Key])"}
Set-Content -LiteralPath $PropertiesPath -Value $Lines -Encoding ASCII
$Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
foreach($Action in @('configure','stop','restart','reset')){
    $Bat=@(
        '@echo off'
        'setlocal'
        'cd /d "%~dp0"'
        ('powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\launcher\server-manager.ps1" -ServerPath "%~dp0." -Action ' + $Action)
        'if errorlevel 1 echo O AZX Manager encontrou um erro. Consulte a mensagem acima.'
        'pause'
        'endlocal'
    )
    Set-Content -LiteralPath (Join-Path $Folder "$Action.bat") -Value $Bat -Encoding ASCII
}
foreach($Tool in @(@{Name='status';Mode='status'},@{Name='diagnostico';Mode='diagnostics'},@{Name='monitorar';Mode='watch'})){
    $Bat=@('@echo off','setlocal','cd /d "%~dp0"',('powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\launcher\monitor.ps1" -ServerPath "%~dp0." -Mode '+$Tool.Mode),'if errorlevel 1 echo O monitor AZX encontrou um erro.','pause','endlocal')
    Set-Content -LiteralPath (Join-Path $Folder ($Tool.Name+'.bat')) -Value $Bat -Encoding ASCII
}
$AdvancedBat=@('@echo off','setlocal','cd /d "%~dp0"','powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\launcher\advanced.ps1" -ServerPath "%~dp0." -Action menu','if errorlevel 1 echo O AZX Advanced encontrou um erro.','pause','endlocal')
Set-Content -LiteralPath (Join-Path $Folder 'advanced.bat') -Value $AdvancedBat -Encoding ASCII
$HelpPath=Join-Path $Folder 'LEIA-PRIMEIRO.txt'
$ManagementHelp=@'

AZX MANAGER (ETAPA 2)
- configure.bat: alterar configuracoes do servidor.
- stop.bat: desligar salvando o mundo via RCON.
- restart.bat: desligar corretamente e iniciar novamente.
- reset.bat: restaurar configuracoes comuns sem apagar o mundo.
Mantenha azx-rcon.txt privado e nunca encaminhe a porta RCON para a internet.
'@
$MonitoringHelp=@'

AZX MONITORAMENTO (ETAPA 4)
- status.bat: painel de status, conexao TCP, jogadores, processo Java, memoria e eventos/logs.
- monitorar.bat: painel ao vivo; registra historico CSV em monitor-data\\historico.csv (Ctrl+C encerra).
- diagnostico.bat: verificacoes locais de rede, IPv4, firewall e logs. TPS/MSPT requer plugin/mod proprio.
O teste TCP e local; nao garante acesso externo nem detecta CGNAT.
'@
if(Test-Path $HelpPath){
    $Existing=Get-Content $HelpPath -Raw
    if($Existing -notmatch 'AZX MANAGER'){Add-Content -LiteralPath $HelpPath -Value $ManagementHelp -Encoding UTF8}
    if($Existing -notmatch 'ETAPA 3'){Add-Content -LiteralPath $HelpPath -Value $MonitoringHelp -Encoding UTF8}
}
$AdvancedHelp=@'

AZX ADVANCED (ETAPA 5)
- advanced.bat: backups completos ZIP, listagem, verificacao SHA-256, restauracao e limpeza de logs antigos.
- Backup/restauracao exigem o servidor desligado. A restauracao cria uma copia automatica do estado atual antes de substituir os arquivos.
- Backups incluem configuracoes e podem conter a senha RCON. Mantenha os arquivos ZIP privados e copie-os para outro disco.
'@
if(Test-Path $HelpPath){$Existing=Get-Content $HelpPath -Raw;if($Existing -notmatch 'AZX ADVANCED'){Add-Content -LiteralPath $HelpPath -Value $AdvancedHelp -Encoding UTF8}}
Write-Host 'Arquivos de gerenciamento, monitoramento e AZX Advanced instalados.' -ForegroundColor Green
