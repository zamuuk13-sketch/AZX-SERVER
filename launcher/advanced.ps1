param(
 [Parameter(Mandatory=$true)][string]$ServerPath,
 [ValidateSet('menu','backup','list','verify','restore','cleanup')][string]$Action='menu'
)
$ErrorActionPreference='Stop'
$ServerPath=[IO.Path]::GetFullPath($ServerPath)
$ConfigPath=Join-Path $ServerPath 'azx-server.json'
if(!(Test-Path -LiteralPath $ConfigPath)){throw 'Instancia AZX invalida: azx-server.json ausente.'}
$Config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$BackupRoot=Join-Path $ServerPath 'backups'
$ManifestName='azx-backup-manifest.json'
function Test-ServerStopped {
 $Port=[int]$Config.port
 try {
  $Listeners=@(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)
  if($Listeners.Count){throw 'A porta do servidor esta em escuta. Desligue o Minecraft normalmente antes desta operacao.'}
 } catch {
  if($_.Exception.Message -like 'A porta do servidor*'){throw}
 }
 try {
  $Processes=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction Stop | Where-Object {$_.CommandLine -and $_.CommandLine.IndexOf($ServerPath,[StringComparison]::OrdinalIgnoreCase) -ge 0})
  if($Processes.Count){throw 'Foi encontrado um processo Java associado a esta instancia. Desligue o servidor normalmente.'}
 } catch {
  if($_.Exception.Message -like 'Foi encontrado*'){throw}
 }
}
function Get-BackupFiles([string]$Path) {
 $Excluded=@('backups','monitor-data')
 return @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force | Where-Object {
  $Relative=$_.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\')
  $First=$Relative.Split('\')[0]
  $First -notin $Excluded -and $Relative -ne $ManifestName -and $_.FullName -notmatch '[\\/]\.azx-restore-'
 })
}
function New-AzxBackup {
 Test-ServerStopped
 New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
 $Stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
 $Name=('{0}-{1}.zip' -f ($Config.name -replace '[^A-Za-z0-9_-]','_'),$Stamp)
 $Destination=Join-Path $BackupRoot $Name
 $Temp=Join-Path ([IO.Path]::GetTempPath()) ('AZX-BACKUP-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $Temp | Out-Null
 try {
  $Files=Get-BackupFiles $ServerPath
  if(!$Files.Count){throw 'Nenhum arquivo da instancia foi encontrado para backup.'}
  $Entries=@()
  foreach($File in $Files){
   $Relative=$File.FullName.Substring($ServerPath.TrimEnd('\').Length).TrimStart('\')
   $Target=Join-Path $Temp $Relative
   $Parent=Split-Path -Parent $Target
   New-Item -ItemType Directory -Force -Path $Parent | Out-Null
   Copy-Item -LiteralPath $File.FullName -Destination $Target
   $Entries+=@{path=($Relative -replace '\\','/');sha256=(Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash.ToLowerInvariant();length=$File.Length}
  }
  $Manifest=[ordered]@{format='AZXBACKUP1';createdAt=(Get-Date).ToString('o');serverName=$Config.name;minecraftVersion=$Config.minecraftVersion;loader=$Config.loader;files=$Entries}
  $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Temp $ManifestName) -Encoding UTF8
  Compress-Archive -Path (Join-Path $Temp '*') -DestinationPath $Destination -CompressionLevel Optimal
  if(!(Test-Path -LiteralPath $Destination) -or (Get-Item $Destination).Length -lt 100){throw 'O arquivo ZIP nao foi criado corretamente.'}
  Write-Host "Backup criado: $Destination" -ForegroundColor Green
  Write-Host ("Arquivos incluidos: {0}" -f $Entries.Count)
  Write-Host 'Guarde uma copia fora deste computador. O ZIP pode conter configuracoes e credenciais RCON; mantenha-o privado.'
  return $Destination
 } finally {Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
}
function Get-BackupList {
 if(!(Test-Path $BackupRoot)){return @()}
 return @(Get-ChildItem -LiteralPath $BackupRoot -Filter '*.zip' -File | Sort-Object LastWriteTime -Descending)
}
function Select-Backup {
 $Items=Get-BackupList
 if(!$Items.Count){Write-Host 'Nenhum backup encontrado.' -ForegroundColor Yellow;return $null}
 for($i=0;$i -lt $Items.Count;$i++){Write-Host ("{0}. {1} | {2:N2} MB | {3}" -f ($i+1),$Items[$i].Name,($Items[$i].Length/1MB),$Items[$i].LastWriteTime)}
 $Pick=Read-Host 'Numero do backup (Enter cancela)';$N=0
 if([int]::TryParse($Pick,[ref]$N) -and $N -ge 1 -and $N -le $Items.Count){return $Items[$N-1]}
 return $null
}
function Test-BackupArchive([string]$Archive,[string]$Destination) {
 Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
 $ManifestPath=Join-Path $Destination $ManifestName
 if(!(Test-Path -LiteralPath $ManifestPath)){throw 'Backup sem manifesto AZX. Arquivo nao reconhecido.'}
 $Manifest=Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
 if($Manifest.format -ne 'AZXBACKUP1' -or !$Manifest.files){throw 'Manifesto do backup invalido.'}
 foreach($Entry in $Manifest.files){
  $Relative=([string]$Entry.path).Replace('/','\')
  if([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|\\)\.\.(\\|$)'){throw 'O backup contem um caminho inseguro.'}
  $Candidate=[IO.Path]::GetFullPath((Join-Path $Destination $Relative))
  $Prefix=$Destination.TrimEnd('\')+'\'
  if(!$Candidate.StartsWith($Prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Caminho fora da pasta temporaria detectado.'}
  if(!(Test-Path -LiteralPath $Candidate -PathType Leaf)){throw "Arquivo ausente no backup: $Relative"}
  $Hash=(Get-FileHash -LiteralPath $Candidate -Algorithm SHA256).Hash.ToLowerInvariant()
  if($Hash -ne ([string]$Entry.sha256).ToLowerInvariant()){throw "Falha SHA-256: $Relative"}
 }
 return $Manifest
}
function Invoke-Verify {
 $Item=Select-Backup;if(!$Item){return}
 $Temp=Join-Path ([IO.Path]::GetTempPath()) ('AZX-VERIFY-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $Temp | Out-Null
 try{$Manifest=Test-BackupArchive $Item.FullName $Temp;Write-Host ("BACKUP INTEGRO | {0} arquivos | criado em {1}" -f $Manifest.files.Count,$Manifest.createdAt) -ForegroundColor Green}
 catch{Write-Host "BACKUP INVALIDO: $($_.Exception.Message)" -ForegroundColor Red}
 finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
}
function Invoke-Restore {
 Test-ServerStopped
 $Item=Select-Backup;if(!$Item){return}
 Write-Host 'ATENCAO: restaurar substitui os arquivos atuais da instancia pelo conteudo do backup.' -ForegroundColor Yellow
 Write-Host 'Uma copia de seguranca do estado atual sera criada antes da restauracao.'
 if((Read-Host 'Digite RESTAURAR para confirmar') -cne 'RESTAURAR'){Write-Host 'Restauracao cancelada.';return}
 $Temp=Join-Path ([IO.Path]::GetTempPath()) ('AZX-RESTORE-'+[guid]::NewGuid().ToString('N'))
 $Stage=Join-Path $Temp 'staged'
 New-Item -ItemType Directory -Path $Stage -Force | Out-Null
 try {
  $Manifest=Test-BackupArchive $Item.FullName $Stage
  $StageConfig=Join-Path $Stage 'azx-server.json'
  if(!(Test-Path $StageConfig)){throw 'Backup nao contem azx-server.json.'}
  $StageSettings=Get-Content $StageConfig -Raw | ConvertFrom-Json
  if($StageSettings.name -ne $Config.name){throw 'Este backup pertence a outra instancia AZX.'}
  $SafetyBackup=New-AzxBackup
  $Keep=Join-Path $Temp 'preserved-backups'
  if(Test-Path $BackupRoot){Move-Item -LiteralPath $BackupRoot -Destination $Keep}
  try {
   Get-ChildItem -LiteralPath $ServerPath -Force | Where-Object {$_.Name -ne 'backups'} | Remove-Item -Recurse -Force
   Get-ChildItem -LiteralPath $Stage -Force | Where-Object {$_.Name -ne $ManifestName} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $ServerPath -Recurse -Force}
   Move-Item -LiteralPath $Keep -Destination $BackupRoot
  } catch {
   Write-Host 'Falha ao aplicar o backup. Restaurando a copia de seguranca automatica...' -ForegroundColor Red
   try {
    $Rollback=Join-Path $Temp 'rollback'
    New-Item -ItemType Directory -Force -Path $Rollback | Out-Null
    $SafetyPath=Join-Path $Keep ([IO.Path]::GetFileName($SafetyBackup))
    $RollbackManifest=Test-BackupArchive $SafetyPath $Rollback
    Get-ChildItem -LiteralPath $ServerPath -Force | Where-Object {$_.Name -ne 'backups'} | Remove-Item -Recurse -Force
    Get-ChildItem -LiteralPath $Rollback -Force | Where-Object {$_.Name -ne $ManifestName} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $ServerPath -Recurse -Force}
    if(Test-Path $Keep){Move-Item -LiteralPath $Keep -Destination $BackupRoot}
    throw 'A restauracao falhou; o estado anterior foi recuperado pelo backup automatico.'
   } catch {throw "Falha na restauracao e no rollback: $($_.Exception.Message)"}
  }
  Write-Host ("Restauracao concluida: {0} ({1} arquivos verificados)." -f $Item.Name,$Manifest.files.Count) -ForegroundColor Green
  Write-Host 'Revise os arquivos e execute start.bat manualmente quando estiver pronto.'
 } finally {Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
}
function Invoke-Cleanup {
 Test-ServerStopped
 $Days=0
 if(!( [int]::TryParse((Read-Host 'Remover logs e crash-reports com mais de quantos dias? (1-3650)'),[ref]$Days) -and $Days -ge 1 -and $Days -le 3650)){Write-Host 'Quantidade invalida.' -ForegroundColor Yellow;return}
 $Cutoff=(Get-Date).AddDays(-$Days)
 $Targets=@((Join-Path $ServerPath 'logs'),(Join-Path $ServerPath 'crash-reports'))
 $Old=@()
 foreach($Target in $Targets){if(Test-Path $Target){$Old+=@(Get-ChildItem -LiteralPath $Target -File -Recurse -Force | Where-Object {$_.LastWriteTime -lt $Cutoff})}}
 Write-Host ("Arquivos antigos encontrados: {0}" -f $Old.Count)
 if(!$Old.Count){return}
 if((Read-Host 'Digite LIMPAR para excluir somente esses arquivos') -cne 'LIMPAR'){Write-Host 'Limpeza cancelada.';return}
 $Old | Remove-Item -Force
 Write-Host ("Removidos: {0}" -f $Old.Count) -ForegroundColor Green
}
function Show-Menu {
 while($true){
  Clear-Host
  Write-Host "AZX ADVANCED - $($Config.name)" -ForegroundColor Cyan
  Write-Host '1. Criar backup completo'
  Write-Host '2. Listar backups'
  Write-Host '3. Verificar integridade SHA-256'
  Write-Host '4. Restaurar backup'
  Write-Host '5. Limpar logs antigos'
  Write-Host '0. Voltar'
  $Choice=Read-Host 'Opcao'
  switch($Choice){
   '1' {try{[void](New-AzxBackup)}catch{Write-Host $_ -ForegroundColor Red}}
   '2' {$Items=Get-BackupList;if(!$Items.Count){Write-Host 'Nenhum backup encontrado.' -ForegroundColor Yellow}else{foreach($I in $Items){Write-Host ("{0} | {1:N2} MB | {2}" -f $I.Name,($I.Length/1MB),$I.LastWriteTime)}}}
   '3' {Invoke-Verify}
   '4' {try{Invoke-Restore}catch{Write-Host "Restauracao interrompida: $($_.Exception.Message)" -ForegroundColor Red}}
   '5' {try{Invoke-Cleanup}catch{Write-Host $_ -ForegroundColor Red}}
   '0' {return}
   default {Write-Host 'Opcao invalida.' -ForegroundColor Yellow}
  }
  if($Choice -ne '0'){Read-Host 'Enter para continuar'|Out-Null}
 }
}
switch($Action){
 'backup' {New-AzxBackup}
 'list' {Get-BackupList | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize}
 'verify' {Invoke-Verify}
 'restore' {Invoke-Restore}
 'cleanup' {Invoke-Cleanup}
 default {Show-Menu}
}