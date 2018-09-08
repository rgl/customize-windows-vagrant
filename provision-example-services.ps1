Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Output "ERROR: $_"
    Write-Output (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Exit 1
}

choco install -y --no-progress nssm carbon

function write-command($path) {
    Set-Content -Encoding ascii -Path $path -Value @'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Output "ERROR: $_"
    Write-Output (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Exit 1
}

function Write-Title($title) {
    Write-Output "#`n# $title`n#"
}

Write-Title 'whoami /all'
whoami /all

Write-Title 'Get-TimeZone'
Get-TimeZone

while ($true) {
    Write-Title "The current time is $(Get-Date)"
    Start-Sleep -Seconds (5*60)
}
'@
}


#
# create a windows service using the SYSTEM account.

$serviceName = 'example-system'
$serviceUsername = 'SYSTEM'
$serviceHome = "C:\example\$serviceName"
Write-Host "Creating the $serviceName service..."
nssm install $serviceName PowerShell
nssm set $serviceName AppParameters '-Command' $serviceHome\command.ps1
nssm set $serviceName AppDirectory $serviceHome
nssm set $serviceName Start SERVICE_DEMAND_START
nssm set $serviceName AppStdout $serviceHome\$serviceName-stdout.log
nssm set $serviceName AppStderr $serviceHome\$serviceName-stderr.log
mkdir $serviceHome -Force | Out-Null
Disable-AclInheritance $serviceHome
Grant-Permission $serviceHome $serviceUsername FullControl
Grant-Permission $serviceHome $env:USERNAME FullControl
Grant-Permission $serviceHome Administrators FullControl
write-command $serviceHome\command.ps1


#
# create a windows service using a managed service account.

$serviceName = 'example-managed'
$serviceUsername = "NT SERVICE\$serviceName"
$serviceHome = "C:\example\$serviceName"
Write-Host "Creating the $serviceName service..."
nssm install $serviceName PowerShell
nssm set $serviceName AppParameters '-Command' $serviceHome\command.ps1
nssm set $serviceName AppDirectory $serviceHome
nssm set $serviceName Start SERVICE_DEMAND_START
nssm set $serviceName AppStdout $serviceHome\$serviceName-stdout.log
nssm set $serviceName AppStderr $serviceHome\$serviceName-stderr.log
$result = sc.exe sidtype $serviceName unrestricted
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe sidtype failed with $result"
}
$result = sc.exe config $serviceName obj= $serviceUsername
if ($result -ne '[SC] ChangeServiceConfig SUCCESS') {
    throw "sc.exe config failed with $result"
}
mkdir $serviceHome -Force | Out-Null
Disable-AclInheritance $serviceHome
Grant-Permission $serviceHome $serviceUsername FullControl
Grant-Permission $serviceHome $env:USERNAME FullControl
Grant-Permission $serviceHome Administrators FullControl
write-command $serviceHome\command.ps1


#
# create a windows service using a local user account.

$serviceName = 'example-local'
$serviceUsername = $serviceName
$serviceHome = "C:\example\$serviceName"
$servicePassword = 'HeyH0Password'
$servicePasswordSecureString = ConvertTo-SecureString $servicePassword -AsPlainText -Force
$serviceCredential = New-Object `
    Management.Automation.PSCredential `
    -ArgumentList `
        $serviceUsername,
        $servicePasswordSecureString

Write-Host "Creating the local $serviceUsername local user account..."
New-LocalUser `
    -Name $serviceUsername `
    -FullName 'Example local user account' `
    -Password $servicePasswordSecureString `
    -PasswordNeverExpires `
    | Out-Null
Grant-Privilege $serviceUsername 'SeServiceLogonRight'

Write-Host "Creating the $serviceName service..."
nssm install $serviceName PowerShell
nssm set $serviceName AppParameters '-Command' $serviceHome\command.ps1
nssm set $serviceName AppDirectory $serviceHome
nssm set $serviceName Start SERVICE_DEMAND_START
nssm set $serviceName AppStdout $serviceHome\$serviceName-stdout.log
nssm set $serviceName AppStderr $serviceHome\$serviceName-stderr.log
$result = sc.exe config $serviceName obj= ".\$serviceUsername" password= $servicePassword
if ($result -ne '[SC] ChangeServiceConfig SUCCESS') {
    throw "sc.exe config failed with $result"
}
mkdir $serviceHome -Force | Out-Null
Disable-AclInheritance $serviceHome
Grant-Permission $serviceHome $serviceUsername FullControl
Grant-Permission $serviceHome $env:USERNAME FullControl
Grant-Permission $serviceHome Administrators FullControl
write-command $serviceHome\command.ps1
