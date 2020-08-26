Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Output "ERROR: $_"
    Write-Output (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Exit 1
}

# wrap the choco command (to make sure this script aborts when it fails).
function Start-Choco([string[]]$Arguments, [int[]]$SuccessExitCodes=@(0)) {
    $command, $commandArguments = $Arguments
    if ($command -eq 'install') {
        $Arguments = @($command, '--no-progress') + $commandArguments
    }
    for ($n = 0; $n -lt 10; ++$n) {
        if ($n) {
            # NB sometimes choco fails with "The package was not found with the source(s) listed."
            #    but normally its just really a transient "network" error.
            Write-Host "Retrying choco install..."
            Start-Sleep -Seconds 3
        }
        &C:\ProgramData\chocolatey\bin\choco.exe @Arguments
        if ($SuccessExitCodes -Contains $LASTEXITCODE) {
            return
        }
    }
    throw "$(@('choco')+$Arguments | ConvertTo-Json -Compress) failed with exit code $LASTEXITCODE"
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

# set the welcome screen culture and keyboard layout.
# NB the .DEFAULT key is for the local SYSTEM account (S-1-5-18).
New-PSDrive HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
'Control Panel\International','Keyboard Layout' | ForEach-Object {
    Remove-Item -Path "HKU:.DEFAULT\$_" -Recurse -Force
    Copy-Item -Path "HKCU:$_" -Destination "HKU:.DEFAULT\$_" -Recurse -Force
}
Remove-PSDrive HKU

# set the timezone.
# use Get-TimeZone -ListAvailable to list the available timezone ids.
Set-TimeZone -Id 'GMT Standard Time'

# show window content while dragging.
Set-ItemProperty -Path 'HKCU:Control Panel\Desktop' -Name DragFullWindows -Value 1

# show hidden files.
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name Hidden -Value 1

# show protected operating system files.
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowSuperHidden -Value 1

# show file extensions.
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HideFileExt -Value 0

# cleanup the taskbar by removing the existing buttons and unpinning all applications; once the user logs on.
# NB the shell executes these RunOnce commands about ~10s after the user logs on.
[IO.File]::WriteAllText(
    "$env:TEMP\ConfigureTaskbar.ps1",
@'
# unpin all applications.
# NB this can only be done in a logged on session.
$pinnedTaskbarPath = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
(New-Object -Com Shell.Application).NameSpace($pinnedTaskbarPath).Items() `
    | ForEach-Object {
        $unpinVerb = $_.Verbs() | Where-Object { $_.Name -eq 'Unpin from tas&kbar' }
        if ($unpinVerb) {
            $unpinVerb.DoIt()
        } else {
            $shortcut = (New-Object -Com WScript.Shell).CreateShortcut($_.Path)
            if (!$shortcut.TargetPath -and ($shortcut.IconLocation -eq '%windir%\explorer.exe,0')) {
                Remove-Item -Force $_.Path
            }
        }
    }
Get-Item HKCU:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband `
    | Set-ItemProperty -Name Favorites -Value 0xff `
    | Set-ItemProperty -Name FavoritesResolve -Value 0xff `
    | Set-ItemProperty -Name FavoritesVersion -Value 3 `
    | Set-ItemProperty -Name FavoritesChanges -Value 1 `
    | Set-ItemProperty -Name FavoritesRemovedChanges -Value 1

# hide the search button.
Set-ItemProperty -Path HKCU:SOFTWARE\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -Value 0

# hide the task view button.
Set-ItemProperty -Path HKCU:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowTaskViewButton -Value 0

# never combine the taskbar buttons.
# possibe values:
#   0: always combine and hide labels (default)
#   1: combine when taskbar is full
#   2: never combine
Set-ItemProperty -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name TaskbarGlomLevel -Value 2

# restart explorer to apply the changed settings.
(Get-Process explorer).Kill()
'@)
New-Item -Path HKCU:Software\Microsoft\Windows\CurrentVersion\RunOnce -Force `
    | New-ItemProperty -Name ConfigureTaskbar -Value 'PowerShell -WindowStyle Hidden -File "%TEMP%\ConfigureTaskbar.ps1"' -PropertyType ExpandString `
    | Out-Null

# set default Explorer location to This PC.
Set-ItemProperty -Path HKCU:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name LaunchTo -Value 1

# display full path in the title bar.
New-Item -Path HKCU:Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState -Force `
    | New-ItemProperty -Name FullPath -Value 1 -PropertyType DWORD `
    | Out-Null

# set desktop background.
#Copy-Item C:\vagrant\windows.png C:\Windows\Web\Wallpaper\Windows
#Set-ItemProperty -Path 'HKCU:Control Panel\Desktop' -Name Wallpaper -Value C:\Windows\Web\Wallpaper\Windows\windows.png
#Set-ItemProperty -Path 'HKCU:Control Panel\Desktop' -Name WallpaperStyle -Value 0
#Set-ItemProperty -Path 'HKCU:Control Panel\Desktop' -Name TileWallpaper -Value 0
#Set-ItemProperty -Path 'HKCU:Control Panel\Colors' -Name Background -Value '30 30 30'
# TODO sync this with https://github.com/rgl/openssh-server-windows-vagrant/blob/932d2885a172aab69547d2c70c55099975ad18f4/provision-common.ps1#L34
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class WallpaperInterop
{
    [DllImport("User32.dll", CharSet=CharSet.Unicode)]
    public static extern int SystemParametersInfo(
        Int32 uAction,
        Int32 uParam,
        String lpvParam,
        Int32 fuWinIni);

    [DllImport("User32.dll", CharSet=CharSet.Unicode)]
    public static extern bool SetSysColors(
        int cElements,
        int[] lpaElements,
        int[] lpaRgbValues);
}
'@
function Set-Wallpaper {
    param (
        [Parameter(Mandatory = $True)]
        [string]$Path,
        [Parameter(Mandatory = $True)]
        [ValidateSet(
            'Fill',
            'Fit',
            'Stretch',
            'Tile',
            'Center',
            'Span')]
        [string]$Style,
        [Parameter(Mandatory = $True)]
        [int]$BackgroundColor
    )

    $wallpaperStyle = switch ($Style) {
        'Fill' { '10' }
        'Fit' { '6' }
        'Stretch' { '2' }
        'Span' { '22' }
        default { '0' }
    }

    New-ItemProperty `
        -Path 'HKCU:\Control Panel\Desktop' `
        -Name WallpaperStyle `
        -PropertyType String `
        -Value $wallpaperStyle `
        -Force `
        | Out-Null
    New-ItemProperty `
        -Path 'HKCU:\Control Panel\Desktop' `
        -Name TileWallpaper `
        -PropertyType String `
        -Value "$(if ($Style -eq 'Tile') {'1'} else {'0'})" `
        -Force `
        | Out-Null

    $COLOR_BACKGROUND = 1
    [WallpaperInterop]::SetSysColors(
        1,
        @($COLOR_BACKGROUND),
        @($BackgroundColor)) `
        | Out-Null

    $SPI_SETDESKWALLPAPER = 0x0014
    $SPIF_UPDATEINIFILE = 0x01
    $SPIF_SENDCHANGE = 0x02
    [WallpaperInterop]::SystemParametersInfo(
        $SPI_SETDESKWALLPAPER,
        0,
        $Path,
        $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE) `
        | Out-Null
}
Add-Type -AssemblyName System.Drawing
$wallpaperPath = 'C:\vagrant\windows.png'
$wallpaperImage = [System.Drawing.Image]::FromFile($wallpaperPath)
$wallpaperBackgroundPixel = $wallpaperImage.GetPixel(0, 0)
$wallpaperBackgroundColor = ([int]$wallpaperBackgroundPixel.R) -bor
                            ([int]$wallpaperBackgroundPixel.G -shl 8) -bor
                            ([int]$wallpaperBackgroundPixel.B -shl 16)
$wallpaperImage.Dispose()
Set-Wallpaper `
    -Path $wallpaperPath `
    -Style 'Center' `
    -BackgroundColor $wallpaperBackgroundColor

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
$accountRegistryKeyPath = "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\$accountSid"
mkdir $accountPictureBasePath | Out-Null
New-Item $accountRegistryKeyPath | Out-Null
# NB we are resizing the same image for all the resolutions, but for better
#    results, you should use images with different resolutions.
Add-Type -AssemblyName System.Drawing
$accountImage = [System.Drawing.Image]::FromFile("c:\vagrant\vagrant.png")
32,40,48,96,192,240,448 | ForEach-Object {
    $p = "$accountPictureBasePath\Image$($_).jpg"
    $i = New-Object System.Drawing.Bitmap($_, $_)
    $g = [System.Drawing.Graphics]::FromImage($i)
    $g.DrawImage($accountImage, 0, 0, $_, $_)
    $i.Save($p)
    New-ItemProperty -Path $accountRegistryKeyPath -Name "Image$_" -Value $p -Force | Out-Null
}

# enable audio.
Set-Service Audiosrv -StartupType Automatic
Start-Service Audiosrv

# install Google Chrome.
# see https://www.chromium.org/administrators/configuring-other-preferences
choco install -y googlechrome
$chromeLocation = 'C:\Program Files (x86)\Google\Chrome\Application'
cp -Force c:\vagrant\GoogleChrome-external_extensions.json (Get-Item "$chromeLocation\*\default_apps\external_extensions.json").FullName
cp -Force c:\vagrant\GoogleChrome-master_preferences.json "$chromeLocation\master_preferences"
cp -Force c:\vagrant\GoogleChrome-master_bookmarks.html "$chromeLocation\master_bookmarks.html"

# set default applications.
choco install -y SetDefaultBrowser
SetDefaultBrowser HKLM "Google Chrome"

# replace notepad with notepad2.
choco install -y notepad2

# remove desktop shortcuts.
del C:\Users\Public\Desktop\* -Force
del "$env:USERPROFILE\Desktop\*" -Force

# load Chocolatey helper functions.
Import-Module C:\ProgramData\chocolatey\helpers\chocolateyInstaller.psm1

# add shortcuts to the Desktop.
Install-ChocolateyShortcut `
    -ShortcutFilePath "$env:USERPROFILE\Desktop\Services.lnk" `
    -TargetPath "$env:windir\system32\services.msc" `
    -Description 'Windows Services'
[IO.File]::WriteAllText("$env:USERPROFILE\Desktop\customize-windows-vagrant.url", @"
[InternetShortcut]
URL=https://github.com/rgl/customize-windows-vagrant
"@)
