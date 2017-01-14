Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'

trap {
    Write-Output "ERROR: $_"
    Write-Output (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Exit 1
}

# wrap the choco command (to make sure this script aborts when it fails).
function Start-Choco([string[]]$Arguments, [int[]]$SuccessExitCodes=@(0)) {
    for ($n = 0; $n -lt 10; ++$n) {
        if ($n) {
            # NB sometimes choco fails with "The package was not found with the source(s) listed."
            #    but normally its just really a transient "network" error.
            Write-Host "Retrying choco install..."
            Start-Sleep -Seconds 3
        }
        &C:\ProgramData\chocolatey\bin\choco.exe @Arguments `
            | Where-Object { $_ -NotMatch '^Progress: ' }
        if ($SuccessExitCodes -Contains $LASTEXITCODE) {
            return
        }
    }
    throw "$(@('choco')+$Arguments | ConvertTo-Json -Compress) failed with exit code $LASTEXITCODE"
}
function choco {
    Start-Choco $Args
}

# define the process privilege manipulation function.
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;

public class ProcessPrivileges
{
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool LookupPrivilegeValue(string host, string name, ref long luid);

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAllPrivileges, ref TOKEN_PRIVILEGES newState, int bufferLength, IntPtr previousState, IntPtr returnLength);

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr processHandle, int desiredAccess, ref IntPtr processToken);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct TOKEN_PRIVILEGES
    {
        public int PrivilegeCount;
        public long Luid;
        public int Attributes;
    }

    const int SE_PRIVILEGE_ENABLED     = 0x00000002;
    const int SE_PRIVILEGE_DISABLED    = 0x00000000;

    const int TOKEN_QUERY              = 0x00000008;
    const int TOKEN_ADJUST_PRIVILEGES  = 0x00000020;

    public static void EnablePrivilege(IntPtr processHandle, string privilegeName, bool enable)
    {
        var processToken = IntPtr.Zero;

        if (!OpenProcessToken(processHandle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref processToken))
        {
            throw new Win32Exception();
        }

        try
        {
            var privileges = new TOKEN_PRIVILEGES
            {
                PrivilegeCount = 1,
                Luid = 0,
                Attributes = enable ? SE_PRIVILEGE_ENABLED : SE_PRIVILEGE_DISABLED,
            };
            
            if (!LookupPrivilegeValue(null, privilegeName, ref privileges.Luid))
            {
                throw new Win32Exception();
            }

            if (!AdjustTokenPrivileges(processToken, false, ref privileges, 0, IntPtr.Zero, IntPtr.Zero))
            {
                throw new Win32Exception();
            }
        }
        finally
        {
            CloseHandle(processToken);
        }
    }
}
'@
function Enable-ProcessPrivilege {
    param(
        # see https://msdn.microsoft.com/en-us/library/bb530716(VS.85).aspx
        [string]$privilegeName,
        [int]$processId = $PID,
        [Switch][bool]$disable
    )
    $process = Get-Process -Id $processId
    try {
        [ProcessPrivileges]::EnablePrivilege(
            $process.Handle,
            $privilegeName,
            !$disable)
    } finally {
        $process.Close()
    }
}

# set keyboard layout.
# NB you can get the name from the list:
#      [Globalization.CultureInfo]::GetCultures('InstalledWin32Cultures') | Out-GridView
Set-WinUserLanguageList pt-PT -Force

# set the date format, number format, etc.
Set-Culture pt-PT

# set the welcome screen culture and keyboard layout.
# NB the .DEFAULT key is for the local SYSTEM account (S-1-5-18).
New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS | Out-Null
'Control Panel\International','Keyboard Layout' | ForEach-Object {
    Remove-Item -Path "HKU:.DEFAULT\$_" -Recurse -Force
    Copy-Item -Path "HKCU:$_" -Destination "HKU:.DEFAULT\$_" -Recurse -Force
}

# set the user lock screen culture.
Enable-ProcessPrivilege SeTakeOwnershipPrivilege
$accountSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$accountLocaleRegistryKeyName = "SOFTWARE\Microsoft\Windows\CurrentVersion\SystemProtectedUserData\$accountSid\AnyoneRead\LocaleInfo"
$key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($accountLocaleRegistryKeyName, 'ReadWriteSubTree', 'TakeOwnership')
$acl = $key.GetAccessControl('None')
$acl.SetOwner([Security.Principal.NTAccount]'Administrators')
$key.SetAccessControl($acl)
Enable-ProcessPrivilege SeTakeOwnershipPrivilege -Disable
$acl = $key.GetAccessControl()
$acl.SetAccessRule((New-Object Security.AccessControl.RegistryAccessRule('Administrators', 'FullControl', 'ContainerInherit', 'None', 'Allow')))
$key.SetAccessControl($acl)
$key.Close()
Set-ItemProperty `
    -Path "HKLM:$accountLocaleRegistryKeyName" `
    -Name Language `
    -Value (Get-ItemProperty -Path 'HKCU:Control Panel\International' -Name LocaleName).LocaleName
Set-ItemProperty `
    -Path "HKLM:$accountLocaleRegistryKeyName" `
    -Name LocaleName `
    -Value (Get-ItemProperty -Path 'HKCU:Control Panel\International' -Name LocaleName).LocaleName
Set-ItemProperty `
    -Path "HKLM:$accountLocaleRegistryKeyName" `
    -Name TimeFormat `
    -Value (Get-ItemProperty -Path 'HKCU:Control Panel\International' -Name sShortTime).sShortTime

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
New-Item $accountRegistryKeyPath | Out-Null
# NB we are resizing the same image for all the resolutions, but for better
#    results, you should use images with different resolutions.
Add-Type -AssemblyName System.Drawing
$accountImage = [System.Drawing.Image]::FromFile("c:\vagrant\vagrant.png")
40,96,200,240,448 | ForEach-Object {
    $p = "$accountPictureBasePath\Image$($_).jpg"
    $i = New-Object System.Drawing.Bitmap($_, $_)
    $g = [System.Drawing.Graphics]::FromImage($i)
    $g.DrawImage($accountImage, 0, 0, $_, $_)
    $i.Save($p)
    New-ItemProperty -Path $accountRegistryKeyPath -Name "Image$_" -Value $p -Force | Out-Null
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
