param([Parameter(Mandatory=$true)][string]$ServerPath,[ValidateSet('status','diagnostics','watch')][string]$Mode='status',[int]$RefreshSeconds=3)
$ErrorActionPreference='Stop'
$ServerPath=[IO.Path]::GetFullPath($ServerPath)
$ConfigPath=Join-Path $ServerPath 'azx-server.json'
$PropertiesPath=Join-Path $ServerPath 'server.properties'
if(!(Test-Path -LiteralPath $ConfigPath) -or !(Test-Path -LiteralPath $PropertiesPath)){Write-Host 'Instancia AZX invalida.' -ForegroundColor Red;exit 2}
$Config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
function Get-ServerPort {
 $Port=[int]$Config.port
 foreach($Line in Get-Content -LiteralPath $PropertiesPath){if($Line -match '^\s*server-port=(\d+)\s*$'){$Port=[int]$Matches[1];break}}
 return $Port
}
function Test-TcpPort([string]$HostName,[int]$Port,[int]$Timeout=1000){
 $Client=[Net.Sockets.TcpClient]::new();$Timer=[Diagnostics.Stopwatch]::StartNew()
 try{$Task=$Client.ConnectAsync($HostName,$Port);if(!$Task.Wait($Timeout) -or !$Client.Connected){return @{Open=$false;Ms=$null}};$Timer.Stop();return @{Open=$true;Ms=$Timer.ElapsedMilliseconds}}
 catch{return @{Open=$false;Ms=$null}}finally{$Client.Dispose()}
}
function Write-VarInt($Stream,[int]$Value) {
 while(($Value -band [int]0xFFFFFF80) -ne 0){$Stream.WriteByte([byte](($Value -band 0x7F) -bor 0x80));$Value=($Value -shr 7)}
 $Stream.WriteByte([byte]$Value)
}
function Read-VarInt($Stream) {
 $Value=0;$Position=0
 while($true){$B=$Stream.ReadByte();if($B -lt 0){throw 'Conexao encerrada durante leitura do status.'};$Value=$Value -bor (($B -band 0x7F) -shl $Position);if(($B -band 0x80) -eq 0){break};$Position+=7;if($Position -ge 35){throw 'VarInt invalido.'}}
 return $Value
}
function Get-MinecraftStatus([int]$Port) {
 $Client=[Net.Sockets.TcpClient]::new()
 try {
  $Task=$Client.ConnectAsync('127.0.0.1',$Port)
  if(!$Task.Wait(1200) -or !$Client.Connected){return $null}
  $Stream=$Client.GetStream();$Stream.ReadTimeout=1800;$Stream.WriteTimeout=1800
  $Payload=[IO.MemoryStream]::new()
  Write-VarInt $Payload 0
  Write-VarInt $Payload 760
  $HostBytes=[Text.Encoding]::UTF8.GetBytes('127.0.0.1')
  Write-VarInt $Payload $HostBytes.Length
  $Payload.Write($HostBytes,0,$HostBytes.Length)
  $Payload.WriteByte([byte](($Port -shr 8) -band 255));$Payload.WriteByte([byte]($Port -band 255))
  Write-VarInt $Payload 1
  $Data=$Payload.ToArray();$Payload.Dispose()
  Write-VarInt $Stream $Data.Length;$Stream.Write($Data,0,$Data.Length)
  Write-VarInt $Stream 1;$Stream.WriteByte(0);$Stream.Flush()
  $PacketLength=Read-VarInt $Stream
  if($PacketLength -gt 1048576 -or $PacketLength -lt 1){throw 'Resposta de status invalida.'}
  $PacketId=Read-VarInt $Stream
  if($PacketId -ne 0){throw 'ID de pacote de status inesperado.'}
  $JsonLength=Read-VarInt $Stream
  if($JsonLength -lt 1 -or $JsonLength -gt $PacketLength){throw 'JSON de status invalido.'}
  $Bytes=New-Object byte[] $JsonLength
  $Offset=0
  while($Offset -lt $JsonLength){$Read=$Stream.Read($Bytes,$Offset,$JsonLength-$Offset);if($Read -le 0){throw 'Resposta de status incompleta.'};$Offset+=$Read}
  return ([Text.Encoding]::UTF8.GetString($Bytes) | ConvertFrom-Json)
 } catch {return $null} finally {$Client.Dispose()}
}
function Get-ServerProcess {
 try {
  $Listeners=@(Get-NetTCPConnection -LocalPort (Get-ServerPort) -State Listen -ErrorAction Stop | Select-Object -ExpandProperty OwningProcess -Unique)
  foreach($ProcessId in $Listeners){$P=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue;if($P -and $P.ProcessName -match '^java(w)?
function Get-RecentLogIssues {
 $Log=Join-Path $ServerPath 'logs\latest.log'
 if(!(Test-Path $Log)){return @('Ainda nao existe logs/latest.log.')}
 $Lines=@(Get-Content -LiteralPath $Log -Tail 250 -ErrorAction SilentlyContinue)
 return @($Lines | Where-Object {$_ -match '(?i)\b(ERROR|FATAL|Exception|Crash|Failed to load|Could not)\b'} | Select-Object -Last 8)
}
function Show-Status {
 $Port=Get-ServerPort;$Tcp=Test-TcpPort '127.0.0.1' $Port;$Process=Get-ServerProcess
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host " AZX SERVER - $($Config.name)" -ForegroundColor Cyan
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host ("Minecraft: {0} | Loader: {1}" -f $Config.minecraftVersion,$Config.loader)
 Write-Host ("Endereco local: 127.0.0.1:{0}/TCP" -f $Port)
 if($Tcp.Open){Write-Host ("STATUS: ONLINE (porta TCP respondeu em {0} ms)" -f $Tcp.Ms) -ForegroundColor Green;$Mc=Get-MinecraftStatus $Port;if($Mc -and $Mc.players){Write-Host ("Jogadores: {0}/{1}" -f $Mc.players.online,$Mc.players.max);if($Mc.version.name){Write-Host "Versao reportada: $($Mc.version.name)"}}}else{Write-Host 'STATUS: OFFLINE ou porta nao esta aceitando conexoes' -ForegroundColor Red}
 if($Process){$Process.Refresh();$Memory=[Math]::Round($Process.WorkingSet64/1GB,2);$Cpu=[Math]::Round($Process.CPU,1);$Uptime=(Get-Date)-$Process.StartTime;Write-Host ("Java PID {0} | RAM {1} GB | CPU acumulada {2}s" -f $Process.Id,$Memory,$Cpu) -ForegroundColor Green;Write-Host ("Tempo ligado: {0}d {1:00}h {2:00}m" -f [int]$Uptime.TotalDays,$Uptime.Hours,$Uptime.Minutes)}else{Write-Host 'Processo Java desta instancia: nao identificado.' -ForegroundColor Yellow}
 try{$Drive=[IO.Path]::GetPathRoot($ServerPath).TrimEnd('\').TrimEnd(':');$Disk=Get-PSDrive -Name $Drive -ErrorAction Stop;$Free=[Math]::Round($Disk.Free/1GB,1);Write-Host ("Espaco livre na unidade {0}: {1} GB" -f $Drive,$Free)}catch{}
 $Issues=Get-RecentLogIssues;Write-Host '';Write-Host 'ULTIMOS AVISOS/ERROS DO LOG' -ForegroundColor Cyan
 if($Issues.Count -eq 0){Write-Host 'Nenhum erro evidente nas ultimas 250 linhas.' -ForegroundColor Green}else{foreach($Issue in $Issues){Write-Host $Issue -ForegroundColor Yellow}}
 Write-Host '';Write-Host 'O teste confirma apenas a porta TCP neste PC; nao confirma acesso pela internet.'
}
function Show-Diagnostics {
 $Port=Get-ServerPort;$Tcp=Test-TcpPort '127.0.0.1' $Port;$Process=Get-ServerProcess
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host " AZX - DIAGNOSTICO: $($Config.name)" -ForegroundColor Cyan
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host '';Write-Host '[1] Processo do servidor'
 if($Process){Write-Host "Java ativo: PID $($Process.Id)" -ForegroundColor Green}else{Write-Host 'Java desta instancia nao identificado.' -ForegroundColor Yellow}
 Write-Host '';Write-Host "[2] Porta TCP local $Port"
 if($Tcp.Open){Write-Host "Conexao local OK ($($Tcp.Ms) ms)." -ForegroundColor Green}else{Write-Host 'Sem resposta local. Verifique se o servidor iniciou e a porta.' -ForegroundColor Red}
 Write-Host '';Write-Host '[3] Enderecos IPv4 da rede local'
 try{$Addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {$_.IPAddress -notlike '127.*' -and $_.AddressState -eq 'Preferred'} | Select-Object -ExpandProperty IPAddress -Unique);if($Addresses.Count){foreach($Address in $Addresses){Write-Host "LAN: $Address" -ForegroundColor Green}}else{Write-Host 'Nenhum IPv4 local encontrado.' -ForegroundColor Yellow}}catch{Write-Host 'Nao foi possivel consultar enderecos IPv4.' -ForegroundColor Yellow}
 Write-Host '';Write-Host '[4] Firewall do Windows'
 try{$Profiles=Get-NetFirewallProfile -ErrorAction Stop;foreach($Profile in $Profiles){Write-Host ("{0}: firewall {1}" -f $Profile.Name,$(if($Profile.Enabled){'ATIVO'}else{'desativado'}))};Write-Host "Confirme uma regra de entrada TCP para a porta $Port."}catch{Write-Host 'Confira manualmente as regras de entrada do Firewall.' -ForegroundColor Yellow}
 Write-Host '';Write-Host '[5] Rede externa'
 Write-Host "Porta do jogo: $Port/TCP. Encaminhe somente essa porta para o IPv4 LAN."
 Write-Host 'Nunca encaminhe a porta RCON nem compartilhe azx-rcon.txt.'
 Write-Host 'CGNAT pode impedir conexoes diretas; consulte seu provedor.'
 Write-Host 'Este diagnostico nao testa internet externa nem confirma CGNAT automaticamente.'
 Write-Host '';Write-Host '[6] Erros recentes do log'
 $Issues=Get-RecentLogIssues;if($Issues.Count -eq 0){Write-Host 'Nenhum erro evidente.' -ForegroundColor Green}else{foreach($Issue in $Issues){Write-Host $Issue -ForegroundColor Yellow}}
}
if($Mode -eq 'watch'){if($RefreshSeconds -lt 1 -or $RefreshSeconds -gt 60){$RefreshSeconds=3};while($true){Clear-Host;Show-Status;Write-Host '';Write-Host "Atualizando a cada $RefreshSeconds segundos. Ctrl+C para sair.";Start-Sleep -Seconds $RefreshSeconds}}
elseif($Mode -eq 'diagnostics'){Show-Diagnostics}else{Show-Status}
){return $P}}
 } catch {}
 try {
  $Matches=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop | Where-Object {$_.CommandLine -and $_.CommandLine.IndexOf($ServerPath,[StringComparison]::OrdinalIgnoreCase) -ge 0})
  if($Matches.Count){return (Get-Process -Id $Matches[0].ProcessId -ErrorAction SilentlyContinue)}
 } catch {}
 return $null
}
function Get-RecentLogIssues {
 $Log=Join-Path $ServerPath 'logs\latest.log'
 if(!(Test-Path $Log)){return @('Ainda nao existe logs/latest.log.')}
 $Lines=@(Get-Content -LiteralPath $Log -Tail 250 -ErrorAction SilentlyContinue)
 return @($Lines | Where-Object {$_ -match '(?i)\b(ERROR|FATAL|Exception|Crash|Failed to load|Could not)\b'} | Select-Object -Last 8)
}
function Show-Status {
 $Port=Get-ServerPort;$Tcp=Test-TcpPort '127.0.0.1' $Port;$Process=Get-ServerProcess
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host " AZX SERVER - $($Config.name)" -ForegroundColor Cyan
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host ("Minecraft: {0} | Loader: {1}" -f $Config.minecraftVersion,$Config.loader)
 Write-Host ("Endereco local: 127.0.0.1:{0}/TCP" -f $Port)
 if($Tcp.Open){Write-Host ("STATUS: ONLINE (porta TCP respondeu em {0} ms)" -f $Tcp.Ms) -ForegroundColor Green;$Mc=Get-MinecraftStatus $Port;if($Mc -and $Mc.players){Write-Host ("Jogadores: {0}/{1}" -f $Mc.players.online,$Mc.players.max);if($Mc.version.name){Write-Host "Versao reportada: $($Mc.version.name)"}}}else{Write-Host 'STATUS: OFFLINE ou porta nao esta aceitando conexoes' -ForegroundColor Red}
 if($Process){$Process.Refresh();$Memory=[Math]::Round($Process.WorkingSet64/1GB,2);$Cpu=[Math]::Round($Process.CPU,1);$Uptime=(Get-Date)-$Process.StartTime;Write-Host ("Java PID {0} | RAM {1} GB | CPU acumulada {2}s" -f $Process.Id,$Memory,$Cpu) -ForegroundColor Green;Write-Host ("Tempo ligado: {0}d {1:00}h {2:00}m" -f [int]$Uptime.TotalDays,$Uptime.Hours,$Uptime.Minutes)}else{Write-Host 'Processo Java desta instancia: nao identificado.' -ForegroundColor Yellow}
 try{$Drive=[IO.Path]::GetPathRoot($ServerPath).TrimEnd('\').TrimEnd(':');$Disk=Get-PSDrive -Name $Drive -ErrorAction Stop;$Free=[Math]::Round($Disk.Free/1GB,1);Write-Host ("Espaco livre na unidade {0}: {1} GB" -f $Drive,$Free)}catch{}
 $Issues=Get-RecentLogIssues;Write-Host '';Write-Host 'ULTIMOS AVISOS/ERROS DO LOG' -ForegroundColor Cyan
 if($Issues.Count -eq 0){Write-Host 'Nenhum erro evidente nas ultimas 250 linhas.' -ForegroundColor Green}else{foreach($Issue in $Issues){Write-Host $Issue -ForegroundColor Yellow}}
 Write-Host '';Write-Host 'O teste confirma apenas a porta TCP neste PC; nao confirma acesso pela internet.'
}
function Show-Diagnostics {
 $Port=Get-ServerPort;$Tcp=Test-TcpPort '127.0.0.1' $Port;$Process=Get-ServerProcess
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host " AZX - DIAGNOSTICO: $($Config.name)" -ForegroundColor Cyan
 Write-Host '============================================================' -ForegroundColor DarkCyan
 Write-Host '';Write-Host '[1] Processo do servidor'
 if($Process){Write-Host "Java ativo: PID $($Process.Id)" -ForegroundColor Green}else{Write-Host 'Java desta instancia nao identificado.' -ForegroundColor Yellow}
 Write-Host '';Write-Host "[2] Porta TCP local $Port"
 if($Tcp.Open){Write-Host "Conexao local OK ($($Tcp.Ms) ms)." -ForegroundColor Green}else{Write-Host 'Sem resposta local. Verifique se o servidor iniciou e a porta.' -ForegroundColor Red}
 Write-Host '';Write-Host '[3] Enderecos IPv4 da rede local'
 try{$Addresses=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {$_.IPAddress -notlike '127.*' -and $_.AddressState -eq 'Preferred'} | Select-Object -ExpandProperty IPAddress -Unique);if($Addresses.Count){foreach($Address in $Addresses){Write-Host "LAN: $Address" -ForegroundColor Green}}else{Write-Host 'Nenhum IPv4 local encontrado.' -ForegroundColor Yellow}}catch{Write-Host 'Nao foi possivel consultar enderecos IPv4.' -ForegroundColor Yellow}
 Write-Host '';Write-Host '[4] Firewall do Windows'
 try{$Profiles=Get-NetFirewallProfile -ErrorAction Stop;foreach($Profile in $Profiles){Write-Host ("{0}: firewall {1}" -f $Profile.Name,$(if($Profile.Enabled){'ATIVO'}else{'desativado'}))};Write-Host "Confirme uma regra de entrada TCP para a porta $Port."}catch{Write-Host 'Confira manualmente as regras de entrada do Firewall.' -ForegroundColor Yellow}
 Write-Host '';Write-Host '[5] Rede externa'
 Write-Host "Porta do jogo: $Port/TCP. Encaminhe somente essa porta para o IPv4 LAN."
 Write-Host 'Nunca encaminhe a porta RCON nem compartilhe azx-rcon.txt.'
 Write-Host 'CGNAT pode impedir conexoes diretas; consulte seu provedor.'
 Write-Host 'Este diagnostico nao testa internet externa nem confirma CGNAT automaticamente.'
 Write-Host '';Write-Host '[6] Erros recentes do log'
 $Issues=Get-RecentLogIssues;if($Issues.Count -eq 0){Write-Host 'Nenhum erro evidente.' -ForegroundColor Green}else{foreach($Issue in $Issues){Write-Host $Issue -ForegroundColor Yellow}}
}
if($Mode -eq 'watch'){if($RefreshSeconds -lt 1 -or $RefreshSeconds -gt 60){$RefreshSeconds=3};while($true){Clear-Host;Show-Status;Write-Host '';Write-Host "Atualizando a cada $RefreshSeconds segundos. Ctrl+C para sair.";Start-Sleep -Seconds $RefreshSeconds}}
elseif($Mode -eq 'diagnostics'){Show-Diagnostics}else{Show-Status}
