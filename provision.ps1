Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'

trap {
    Write-Output "`nERROR: $_`n$($_.ScriptStackTrace)"
    Exit 1
}

# wrap the choco command (to make sure this script aborts when it fails).
function Start-Choco([string[]]$Arguments, [int[]]$SuccessExitCodes=@(0)) {
    &C:\ProgramData\chocolatey\bin\choco.exe @Arguments `
        | Where-Object { $_ -NotMatch '^Progress: ' }
    if ($SuccessExitCodes -NotContains $LASTEXITCODE) {
        throw "$(@('choco')+$Arguments | ConvertTo-Json -Compress) failed with exit code $LASTEXITCODE"
    }
}
function choco {
    Start-Choco $Args
}

# set keyboard layout.
# NB you can get the name from the list:
#      [Globalization.CultureInfo]::GetCultures('InstalledWin32Cultures') | Out-GridView
Set-WinUserLanguageList pt-PT -Force

# set the date format, number format, etc.
Set-Culture pt-PT

# set the timezone.
# tzutil /l lists all available timezone ids
& $env:windir\system32\tzutil /s "GMT Standard Time"

# show window content while dragging.
Set-ItemProperty -Path 'HKCU:Control Panel\Desktop' -Name DragFullWindows -Value 1

# show hidden files.
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Hidden -Value 1

# show protected operating system files.
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowSuperHidden -Value 1

# show file extensions.
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideFileExt -Value 0

# never combine the taskbar buttons.
#
# possibe values:
#   0: always combine and hide labels (default)
#   1: combine when taskbar is full
#   2: never combine
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel -Value 2

# display full path in the title bar.
New-Item -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState -Force `
    | New-ItemProperty -Name FullPath -Value 1 -PropertyType DWORD `
    | Out-Null

# set desktop background.
Copy-Item C:\vagrant\windows.png C:\Windows\Web\Wallpaper\Windows
Set-ItemProperty -Path 'HKCU:Control Panel\Desktop' -Name Wallpaper -Value C:\Windows\Web\Wallpaper\Windows\windows.png
Set-ItemProperty -Path 'HKCU:Control Panel\Desktop' -Name WallpaperStyle -Value 0
Set-ItemProperty -Path 'HKCU:Control Panel\Desktop' -Name TileWallpaper -Value 0
Set-ItemProperty -Path 'HKCU:Control Panel\Colors' -Name Background -Value '30 30 30'

# set lock screen background.
Copy-Item C:\vagrant\windows.png C:\Windows\Web\Screen
New-Item -Path HKLM:Software\Policies\Microsoft\Windows\Personalization -Force `
    | New-ItemProperty -Name LockScreenImage -Value C:\Windows\Web\Screen\windows.png `
    | New-ItemProperty -Name PersonalColors_Background -Value '#1e1e1e' `
    | New-ItemProperty -Name PersonalColors_Accent -Value '#007acc' `
    | Out-Null

# set account picture.
$accountSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$accountPictureBasePath = "C:\Users\Public\AccountPictures\$accountSid"
$accountRegistryKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\$accountSid"
$accountRegistryKeyPath = "HKLM:$accountRegistryKey"
# see https://powertoe.wordpress.com/2010/08/28/controlling-registry-acl-permissions-with-powershell/
$key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
    "SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\$accountSid",
    'ReadWriteSubTree',
    'ChangePermissions')
$acl = $key.GetAccessControl()
$acl.SetAccessRule((New-Object Security.AccessControl.RegistryAccessRule('Administrators', 'FullControl', 'Allow')))
$key.SetAccessControl($acl)
mkdir $accountPictureBasePath | Out-Null
$accountPicturePath = "$accountPictureBasePath\vagrant.png"
Copy-Item -Force C:\vagrant\vagrant.png $accountPicturePath
# NB we are using the same image for all the resolutions, but for better
#    results, you should use images with different resolutions.
40,96,200,240,448 | ForEach-Object {
    New-ItemProperty -Path $accountRegistryKeyPath -Name "Image$_" -Value $accountPicturePath -Force | Out-Null
}

# install classic shell.
New-Item -Path HKCU:Software\IvoSoft\ClassicStartMenu -Force `
    | New-ItemProperty -Name ShowedStyle2      -Value 1 -PropertyType DWORD `
    | Out-Null
New-Item -Path HKCU:Software\IvoSoft\ClassicStartMenu\Settings -Force `
    | New-ItemProperty -Name EnableStartButton -Value 1 -PropertyType DWORD `
    | New-ItemProperty -Name SkipMetro         -Value 1 -PropertyType DWORD `
    | Out-Null
choco install -y classic-shell --allow-empty-checksums -installArgs ADDLOCAL=ClassicStartMenu

# install Google Chrome and some useful extensions.
# see https://developer.chrome.com/extensions/external_extensions
choco install -y googlechrome
@(
    # JSON Formatter (https://chrome.google.com/webstore/detail/json-formatter/bcjindcccaagfpapjjmafapmmgkkhgoa).
    'bcjindcccaagfpapjjmafapmmgkkhgoa'
    # uBlock Origin (https://chrome.google.com/webstore/detail/ublock-origin/cjpalhdlnbpafiamejdnhcphjbkeiagm).
    'cjpalhdlnbpafiamejdnhcphjbkeiagm'
) | ForEach-Object {
    New-Item -Force -Path "HKLM:Software\Wow6432Node\Google\Chrome\Extensions\$_" `
        | Set-ItemProperty -Name update_url -Value 'https://clients2.google.com/service/update2/crx'
}

# replace notepad with notepad2.
choco install -y notepad2

# remove desktop shortcuts.
del C:\Users\Public\Desktop\* -Force
del "$env:USERPROFILE\Desktop\*" -Force

# load Chocolatey helper functions.
Import-Module C:\ProgramData\chocolatey\helpers\chocolateyInstaller.psm1

# add Services shortcut to the Desktop.
Install-ChocolateyShortcut `
  -ShortcutFilePath "$env:USERPROFILE\Desktop\Services.lnk" `
  -TargetPath "$env:windir\system32\services.msc" `
  -Description 'Windows Services'
