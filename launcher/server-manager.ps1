param([Parameter(Mandatory=$true)][string]$ServerPath,[ValidateSet('configure','stop','restart','reset')][string]$Action='configure')
$ErrorActionPreference='Stop'
$ServerPath=[IO.Path]::GetFullPath($ServerPath)
$ConfigPath=Join-Path $ServerPath 'azx-server.json'
$PropertiesPath=Join-Path $ServerPath 'server.properties'
if (!(Test-Path $ConfigPath) -or !(Test-Path $PropertiesPath)) { Write-Host 'Instancia AZX invalida.' -ForegroundColor Red; exit 2 }
$Config=Get-Content $ConfigPath -Raw | ConvertFrom-Json
$RconFile=Join-Path $ServerPath 'azx-rcon.txt'
if (!(Test-Path $RconFile)) {
  $Bytes=New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($Bytes)
  $Password=[Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','X').Replace('/','Y')
  Set-Content $RconFile $Password -Encoding ASCII
} else { $Password=(Get-Content $RconFile -Raw).Trim() }
$RconPort=[int]$Config.rconPort
if ($RconPort -lt 1 -or $RconPort -gt 65535) { $RconPort=[Math]::Min(65535,([int]$Config.port+10000)); $Config | Add-Member -NotePropertyName rconPort -NotePropertyValue $RconPort -Force; $Config | ConvertTo-Json -Depth 8 | Set-Content $ConfigPath -Encoding UTF8 }
function Get-Props {
  $Map=[ordered]@{}
  foreach($Line in Get-Content $PropertiesPath) { if($Line -match '^\s*([^#\s][^=]*)=(.*)$') { $Map[$Matches[1]]=$Matches[2] } }
  return $Map
}
function Save-Props($Map) {
  Copy-Item $PropertiesPath "$PropertiesPath.azx-backup" -Force
  $Lines=foreach($Key in $Map.Keys) { "$Key=$($Map[$Key])" }
  Set-Content $PropertiesPath $Lines -Encoding ASCII
}
function Test-Rcon {
  $C=[Net.Sockets.TcpClient]::new()
  try { $T=$C.ConnectAsync('127.0.0.1',$RconPort); return ($T.Wait(500) -and $C.Connected) } catch { return $false } finally { $C.Dispose() }
}
function Invoke-Rcon([string]$Command) {
  $C=[Net.Sockets.TcpClient]::new(); $C.ReceiveTimeout=3000; $C.SendTimeout=3000
  try {
    $C.Connect('127.0.0.1',$RconPort); $S=$C.GetStream(); $W=[IO.BinaryWriter]::new($S); $R=[IO.BinaryReader]::new($S)
    function Send-Packet($W,[int]$Id,[int]$Type,[string]$Text) {
      $B=[Text.Encoding]::UTF8.GetBytes($Text); $W.Write([int](10+$B.Length)); $W.Write($Id); $W.Write($Type); $W.Write($B); $W.Write([byte]0); $W.Write([byte]0); $W.Flush()
    }
    function Receive-Packet($R) {
      $L=$R.ReadInt32(); if($L -lt 10 -or $L -gt 65536) { throw 'Pacote RCON invalido.' }
      $Id=$R.ReadInt32(); $Type=$R.ReadInt32(); $B=$R.ReadBytes($L-10); [void]$R.ReadBytes(2)
      return @{Id=$Id;Type=$Type;Text=[Text.Encoding]::UTF8.GetString($B)}
    }
    Send-Packet $W 11 3 $Password
    $Auth=Receive-Packet $R
    if($Auth.Id -eq -1) { throw 'Senha RCON recusada.' }
    Send-Packet $W 12 2 $Command
    return (Receive-Packet $R).Text
  } finally { $C.Dispose() }
}
function Save-Config { $Config | ConvertTo-Json -Depth 8 | Set-Content $ConfigPath -Encoding UTF8 }
function Configure-Menu {
 while($true) {
  Clear-Host; Write-Host "AZX MANAGER - $($Config.name)" -ForegroundColor Cyan
  Write-Host 'Alteracoes em server.properties exigem reinicio.'
  Write-Host '1. MOTD/nome exibido  2. Maximo de jogadores  3. Distancia de visao'
  Write-Host '4. Porta TCP          5. Autenticacao           6. Dificuldade'
  Write-Host '7. Modo de jogo       8. Alternar whitelist      9. Adicionar OP (ligado)'
  Write-Host '10. Adicionar whitelist (ligado)  11. Ver configuracoes  0. Voltar'
  $Choice=Read-Host 'Opcao'; $P=Get-Props
  switch($Choice) {
   '1' { $V=Read-Host 'Novo MOTD'; if($V){$P['motd']=$V -replace '[\r\n=]',' ';Save-Props $P;Write-Host 'Salvo.' -ForegroundColor Green} }
   '2' { $V=0;if([int]::TryParse((Read-Host 'Maximo (1-1000)'),[ref]$V) -and $V -ge 1 -and $V -le 1000){$P['max-players']="$V";$Config.maxPlayers=$V;Save-Props $P;Save-Config;Write-Host 'Salvo.' -ForegroundColor Green}else{Write-Host 'Valor invalido.' -ForegroundColor Yellow} }
   '3' { $V=0;if([int]::TryParse((Read-Host 'Distancia (2-32)'),[ref]$V) -and $V -ge 2 -and $V -le 32){$P['view-distance']="$V";$Config.viewDistance=$V;Save-Props $P;Save-Config;Write-Host 'Salvo.' -ForegroundColor Green}else{Write-Host 'Valor invalido.' -ForegroundColor Yellow} }
   '4' { $V=0;if([int]::TryParse((Read-Host 'Porta TCP (1-65535)'),[ref]$V) -and $V -ge 1 -and $V -le 65535){$P['server-port']="$V";$Config.port=$V;Save-Props $P;Save-Config;Write-Host 'Porta salva. Atualize o roteador se necessario.' -ForegroundColor Green}else{Write-Host 'Valor invalido.' -ForegroundColor Yellow} }
   '5' { Write-Host '1. Autenticacao oficial (recomendado)  2. Offline (risco de falsificacao)';$V=Read-Host 'Escolha';if($V -in @('1','2')){$P['online-mode']=if($V -eq '1'){'true'}else{'false'};$Config.onlineMode=($V -eq '1');Save-Props $P;Save-Config;Write-Host 'Salvo.' -ForegroundColor Green} }
   '6' { $V=(Read-Host 'peaceful/easy/normal/hard').ToLowerInvariant();if($V -in @('peaceful','easy','normal','hard')){$P['difficulty']=$V;Save-Props $P;Write-Host 'Salvo.' -ForegroundColor Green}else{Write-Host 'Valor invalido.' -ForegroundColor Yellow} }
   '7' { $V=(Read-Host 'survival/creative/adventure/spectator').ToLowerInvariant();if($V -in @('survival','creative','adventure','spectator')){$P['gamemode']=$V;Save-Props $P;Write-Host 'Salvo.' -ForegroundColor Green}else{Write-Host 'Valor invalido.' -ForegroundColor Yellow} }
   '8' { $P['white-list']=if($P['white-list'] -eq 'true'){'false'}else{'true'};Save-Props $P;if(Test-Rcon){try{[void](Invoke-Rcon $(if($P['white-list'] -eq 'true'){'whitelist on'}else{'whitelist off'}))}catch{Write-Host $_ -ForegroundColor Yellow}};Write-Host "Whitelist: $($P['white-list'])" -ForegroundColor Green }
   '9' { $N=Read-Host 'Nick exato';if($N -match '^[A-Za-z0-9_]{1,16}$' -and (Test-Rcon)){Write-Host (Invoke-Rcon "op $N")}else{Write-Host 'Servidor desligado ou nick invalido.' -ForegroundColor Yellow} }
   '10' { $N=Read-Host 'Nick exato';if($N -match '^[A-Za-z0-9_]{1,16}$' -and (Test-Rcon)){Write-Host (Invoke-Rcon "whitelist add $N")}else{Write-Host 'Servidor desligado ou nick invalido.' -ForegroundColor Yellow} }
   '11' { foreach($K in @('motd','server-port','online-mode','max-players','view-distance','difficulty','gamemode','white-list')){Write-Host "$K = $($P[$K])"} }
   '0' { return }
   default { Write-Host 'Opcao invalida.' -ForegroundColor Yellow }
  }
  if($Choice -ne '0'){Read-Host 'Enter para continuar'|Out-Null}
 }
}
switch($Action) {
 'configure' { Configure-Menu }
 'stop' {
  if(!(Test-Rcon)){Write-Host 'Servidor nao esta ativo ou RCON indisponivel.' -ForegroundColor Yellow;exit 0}
  try{[void](Invoke-Rcon 'stop');Write-Host 'Comando stop enviado. O Minecraft salvara o mundo antes de encerrar.' -ForegroundColor Green}catch{Write-Host "Falha no RCON: $_" -ForegroundColor Red;exit 3}
 }
 'restart' {
  if(Test-Rcon){try{[void](Invoke-Rcon 'stop')}catch{Write-Host $_ -ForegroundColor Red;exit 3};$End=(Get-Date).AddSeconds(60);while((Get-Date) -lt $End -and (Test-Rcon)){Start-Sleep 2};if(Test-Rcon){Write-Host 'Timeout: servidor nao desligou; reinicio cancelado.' -ForegroundColor Red;exit 4}}
  if((Get-Content (Join-Path $ServerPath 'eula.txt') -Raw) -notmatch '(?im)^\s*eula=true\s*$'){Write-Host 'EULA nao aceito. Reinicio cancelado.' -ForegroundColor Red;exit 5}
  Start-Process -FilePath $env:ComSpec -ArgumentList @('/c','"' + (Join-Path $ServerPath 'start.bat') + '"') -WorkingDirectory $ServerPath
  Write-Host 'Inicializacao solicitada em nova janela.' -ForegroundColor Green
 }
 'reset' {
  Write-Host 'Restaura configuracoes padrao. Mundo, mods e configs de mods serao preservados.' -ForegroundColor Yellow
  if((Read-Host 'Confirmar? (S/N)') -match '^(s|sim)$'){$P=Get-Props;$P['motd']="$($Config.name) | AZX Server";$P['server-port']="$($Config.port)";$P['online-mode']=if($Config.onlineMode){'true'}else{'false'};$P['max-players']="$($Config.maxPlayers)";$P['view-distance']="$($Config.viewDistance)";$P['difficulty']='normal';$P['gamemode']='survival';$P['white-list']='false';Save-Props $P;Write-Host 'Configuracoes restauradas. Mundo preservado.' -ForegroundColor Green}
 }
}
