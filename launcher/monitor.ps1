param(
 [Parameter(Mandatory=$true)][string]$ServerPath,
 [ValidateSet('status','diagnostics','watch')][string]$Mode='status',
 [ValidateRange(1,60)][int]$RefreshSeconds=3
)
$ErrorActionPreference='Stop'
$ServerPath=[IO.Path]::GetFullPath($ServerPath)
$ConfigPath=Join-Path $ServerPath 'azx-server.json'
$PropertiesPath=Join-Path $ServerPath 'server.properties'
if(!(Test-Path -LiteralPath $ConfigPath) -or !(Test-Path -LiteralPath $PropertiesPath)){Write-Host 'Instancia AZX invalida: arquivos ausentes.' -ForegroundColor Red;exit 2}
$Config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$HistoryDir=Join-Path $ServerPath 'monitor-data'
$HistoryFile=Join-Path $HistoryDir 'historico.csv'
function Get-ServerPort {
 $Port=[int]$Config.port
 foreach($Line in Get-Content -LiteralPath $PropertiesPath){if($Line -match '^\s*server-port=(\d+)\s*$'){$Port=[int]$Matches[1];break}}
 if($Port -lt 1 -or $Port -gt 65535){throw 'Porta TCP invalida na configuracao.'}
 return $Port
}
function Test-TcpPort([int]$Port,[int]$Timeout=900) {
 $Client=[Net.Sockets.TcpClient]::new();$Timer=[Diagnostics.Stopwatch]::StartNew()
 try{$Task=$Client.ConnectAsync('127.0.0.1',$Port);if(!$Task.Wait($Timeout) -or !$Client.Connected){return @{Open=$false;Ms=$null}};$Timer.Stop();return @{Open=$true;Ms=$Timer.ElapsedMilliseconds}}
 catch{return @{Open=$false;Ms=$null}}finally{$Client.Dispose()}
}
function Write-VarInt($Stream,[int]$Value){
 while(($Value -band [int]0xFFFFFF80) -ne 0){$Stream.WriteByte([byte](($Value -band 0x7F) -bor 0x80));$Value=$Value -shr 7}
 $Stream.WriteByte([byte]$Value)
}
function Read-VarInt($Stream){
 $Value=0;$Position=0
 while($true){$B=$Stream.ReadByte();if($B -lt 0){throw 'Resposta encerrada.'};$Value=$Value -bor (($B -band 0x7F) -shl $Position);if(($B -band 0x80) -eq 0){break};$Position+=7;if($Position -ge 35){throw 'VarInt invalido.'}}
 return $Value
}
function Get-MinecraftStatus([int]$Port){
 $Client=[Net.Sockets.TcpClient]::new()
 try{
  $Task=$Client.ConnectAsync('127.0.0.1',$Port);if(!$Task.Wait(1000) -or !$Client.Connected){return $null}
  $Stream=$Client.GetStream();$Stream.ReadTimeout=1500;$Stream.WriteTimeout=1500
  $Payload=[IO.MemoryStream]::new()
  Write-VarInt $Payload 0
  Write-VarInt $Payload 763
  $HostBytes=[Text.Encoding]::UTF8.GetBytes('127.0.0.1')
  Write-VarInt $Payload $HostBytes.Length;$Payload.Write($HostBytes,0,$HostBytes.Length)
  $Payload.WriteByte([byte](($Port -shr 8) -band 255));$Payload.WriteByte([byte]($Port -band 255))
  Write-VarInt $Payload 1
  $Data=$Payload.ToArray();$Payload.Dispose()
  Write-VarInt $Stream $Data.Length;$Stream.Write($Data,0,$Data.Length)
  Write-VarInt $Stream 1;$Stream.WriteByte(0);$Stream.Flush()
  $PacketLength=Read-VarInt $Stream
  if($PacketLength -lt 1 -or $PacketLength -gt 1048576){return $null}
  if((Read-VarInt $Stream) -ne 0){return $null}
  $JsonLength=Read-VarInt $Stream
  if($JsonLength -lt 1 -or $JsonLength -gt $PacketLength){return $null}
  $Bytes=New-Object byte[] $JsonLength;$Offset=0
  while($Offset -lt $JsonLength){$Read=$Stream.Read($Bytes,$Offset,$JsonLength-$Offset);if($Read -le 0){return $null};$Offset+=$Read}
  return ([Text.Encoding]::UTF8.GetString($Bytes) | ConvertFrom-Json)
 }catch{return $null}finally{$Client.Dispose()}
}
function Get-ServerProcess([int]$Port){
 try{
  $Ids=@(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -ExpandProperty OwningProcess -Unique)
  foreach($ProcessId in $Ids){$P=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue;if($P -and $P.ProcessName -match '^java(w)?$'){return $P}}
 }catch{}
 try{
  $Found=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop | Where-Object {$_.CommandLine -and $_.CommandLine.IndexOf($ServerPath,[StringComparison]::OrdinalIgnoreCase) -ge 0})
  if($Found.Count){return (Get-Process -Id $Found[0].ProcessId -ErrorAction SilentlyContinue)}
 }catch{}
 return $null
}
function Get-LogSummary {
 $Log=Join-Path $ServerPath 'logs\latest.log'
 if(!(Test-Path -LiteralPath $Log)){return @{Errors=@('Log ainda nao foi criado.');Recent=@()}}
 $Lines=@(Get-Content -LiteralPath $Log -Tail 500 -ErrorAction SilentlyContinue)
 $Errors=@($Lines | Where-Object {$_ -match '(?i)\b(ERROR|FATAL|Exception|Crash|Failed to load|Could not)\b'} | Select-Object -Last 6)
 $Recent=@($Lines | Where-Object {$_ -match '(?i)(joined the game|left the game|Done \()'} | Select-Object -Last 5)
 return @{Errors=$Errors;Recent=$Recent}
}
function Get-Snapshot {
 $Port=Get-ServerPort;$Tcp=Test-TcpPort $Port;$Mc=$null
 if($Tcp.Open){$Mc=Get-MinecraftStatus $Port}
 $Process=Get-ServerProcess $Port
 $MemoryGB=$null;$CpuSeconds=$null;$UptimeSeconds=$null
 if($Process){
  $Process.Refresh()
  $MemoryGB=[Math]::Round($Process.WorkingSet64/1GB,3)
  if($Process.CPU -ne $null){$CpuSeconds=[Math]::Round($Process.CPU,2)}
  try{$UptimeSeconds=[int]((Get-Date)-$Process.StartTime).TotalSeconds}catch{}
 }
 $Drive=[IO.Path]::GetPathRoot($ServerPath).Substring(0,1)
 $Disk=Get-PSDrive -Name $Drive -ErrorAction SilentlyContinue
 $FreeGB=$null;if($Disk){$FreeGB=[Math]::Round($Disk.Free/1GB,2)}
 $Online=($null -ne $Mc)
 $Players=0;$MaxPlayers=[int]$Config.maxPlayers;$Version=$Config.minecraftVersion
 if($Mc){
  if($Mc.players){$Players=[int]$Mc.players.online;$MaxPlayers=[int]$Mc.players.max}
  if($Mc.version.name){$Version=[string]$Mc.version.name}
 }
 return [pscustomobject]@{
  Time=(Get-Date).ToString('s');Online=$Online;TcpMs=$Tcp.Ms;Players=$Players;MaxPlayers=$MaxPlayers
  Version=$Version;ProcessId=$(if($Process){$Process.Id}else{$null});MemoryGB=$MemoryGB
  CpuSeconds=$CpuSeconds;UptimeSeconds=$UptimeSeconds;DiskFreeGB=$FreeGB
  PlayerSample=$(if($Mc -and $Mc.players -and $Mc.players.sample){(@($Mc.players.sample | ForEach-Object {$_.name}) -join ', ')}else{''})
 }
}
function Save-History($Snapshot){
 if(!(Test-Path $HistoryDir)){New-Item -ItemType Directory -Path $HistoryDir -Force | Out-Null}
 $Snapshot | Export-Csv -LiteralPath $HistoryFile -NoTypeInformation -Encoding UTF8 -Append
}
function Show-Snapshot($Snapshot){
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host " AZX MONITOR - $($Config.name)" -ForegroundColor Cyan
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host ("Atualizado: {0} | Minecraft: {1}" -f $Snapshot.Time,$Snapshot.Version)
 if($Snapshot.Online){Write-Host ("SERVIDOR ONLINE | TCP local: {0} ms" -f $Snapshot.TcpMs) -ForegroundColor Green}else{Write-Host 'SERVIDOR OFFLINE / sem resposta do protocolo Minecraft' -ForegroundColor Red}
 Write-Host ("Jogadores: {0}/{1}" -f $Snapshot.Players,$Snapshot.MaxPlayers)
 if($Snapshot.PlayerSample){Write-Host "Amostra de jogadores: $($Snapshot.PlayerSample)"}
 if($null -ne $Snapshot.ProcessId){
  Write-Host ("Java PID: {0} | RAM do processo: {1} GB | CPU acumulada: {2}s" -f $Snapshot.ProcessId,$Snapshot.MemoryGB,$Snapshot.CpuSeconds) -ForegroundColor Green
  if($null -ne $Snapshot.UptimeSeconds){$Span=[TimeSpan]::FromSeconds($Snapshot.UptimeSeconds);Write-Host ("Uptime: {0}d {1:00}h {2:00}m" -f [int]$Span.TotalDays,$Span.Hours,$Span.Minutes)}
 }else{Write-Host 'Processo Java: nao identificado.' -ForegroundColor Yellow}
 if($null -ne $Snapshot.DiskFreeGB){Write-Host "Espaco livre em disco: $($Snapshot.DiskFreeGB) GB"}
 Write-Host 'TPS/MSPT: nao disponivel no servidor vanilla sem plugin/mod de metricas.' -ForegroundColor DarkGray
}
function Show-Status {
 $S=Get-Snapshot;Show-Snapshot $S
 $Log=Get-LogSummary
 Write-Host '';Write-Host 'EVENTOS RECENTES' -ForegroundColor Cyan
 if($Log.Recent.Count){foreach($Line in $Log.Recent){Write-Host $Line -ForegroundColor Gray}}else{Write-Host 'Nenhum evento recente encontrado.'}
 Write-Host '';Write-Host 'ERROS RECENTES' -ForegroundColor Cyan
 if($Log.Errors.Count){foreach($Line in $Log.Errors){Write-Host $Line -ForegroundColor Yellow}}else{Write-Host 'Nenhum erro evidente no trecho analisado.' -ForegroundColor Green}
}
function Show-Diagnostics {
 $S=Get-Snapshot;$Port=Get-ServerPort
 Show-Snapshot $S
 Write-Host '';Write-Host 'DIAGNOSTICO DE REDE' -ForegroundColor Cyan
 try{$Addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {$_.IPAddress -notlike '127.*' -and $_.AddressState -eq 'Preferred'} | Select-Object -ExpandProperty IPAddress -Unique);foreach($Address in $Addresses){Write-Host "IPv4 LAN: $Address" -ForegroundColor Green}}catch{Write-Host 'Nao foi possivel consultar IPv4 LAN.' -ForegroundColor Yellow}
 try{$Profiles=Get-NetFirewallProfile -ErrorAction Stop;foreach($Profile in $Profiles){Write-Host ("Firewall {0}: {1}" -f $Profile.Name,$(if($Profile.Enabled){'ativo'}else{'desativado'}))}}catch{Write-Host 'Firewall: consulta indisponivel.'}
 Write-Host "Porta do jogo: $Port/TCP. Verifique regra de entrada e encaminhamento no roteador."
 Write-Host 'O AZX nao verifica CGNAT nem confirma acesso a partir da internet.'
 Write-Host 'Nao encaminhe RCON; o protocolo nao e criptografado.'
}
if($Mode -eq 'watch'){
 while($true){
  Clear-Host;$S=Get-Snapshot;Show-Snapshot $S;Save-History $S
  Write-Host '';Write-Host "Historico CSV: $HistoryFile" -ForegroundColor DarkGray
  Write-Host "Atualizacao a cada $RefreshSeconds segundos. Ctrl+C para sair."
  Start-Sleep -Seconds $RefreshSeconds
 }
}elseif($Mode -eq 'diagnostics'){Show-Diagnostics}else{Show-Status}
