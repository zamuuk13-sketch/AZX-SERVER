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
Write-Host 'Arquivos de gerenciamento AZX instalados.' -ForegroundColor Green
