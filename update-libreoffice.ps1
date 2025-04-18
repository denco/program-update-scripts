# [CmdletBinding()]
[cultureinfo]::CurrentUICulture='en-US'


$TargetPath = "$($env:LOCALAPPDATA)\Programs"

# $7Zip = "$($TargetPath)\7-Zip\7z.exe"

$vScanner = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"

# gpg
# gpg --receive-keys C2839ECAD9408FBE9531C3E9F434A1EFAFEEAEA3
$gpg  = "$($TargetPath)\git\usr\bin\gpg.exe"

$TargetDir = "$($TargetPath)\libreoffice"
$BackupDir = "$($TargetDir).bak"

Write-Output "check updates for: libreoffice"

# $MainVersionURL = "https://download.documentfoundation.org/libreoffice/src/"
$MainVersionURL = "https://download.documentfoundation.org/libreoffice/stable/"

$ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
$MainVersion = "$((Invoke-WebRequest -Uri "$($MainVersionURL)?C=M;O=A").Content.Split("`n") `
                    | Select-string -Pattern "top" -AllMatches -Context 0,1 `
                    | Select-Object -Last 1
                )".Split('href')[1].Split('"')[1].Replace('/', '')
$ProgressPreference = 'Continue'

# write-Output "$($MainVersion)"

$ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.

# $RemoteLatestTag = $($((Invoke-WebRequest -Uri "$($MainVersionURL)$($MainVersion)/?C=M;O=A").Content.Split("`n") `
#                         | Select-string -Pattern "top" -AllMatches -Context 0,1)[1] -split('"')
#                        )[3] -replace "[\D|\.]*$", "" -replace "libreoffice-", ""

$RemoteLatestTag = "$(git ls-remote --tags "https://github.com/LibreOffice/core.git" `
                      | Select-String -Pattern "/libreoffice-$($MainVersion)(\.\d+)$" `
                      | Select-Object -Last 1
                    )".Trim().Split('/')[2].Split('-')[1]

$ProgressPreference = 'Continue'

$CurrentVersion = "0.0.0"
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\VERSION )) {
    $CurrentVersion = (get-content "$($TargetDir)\VERSION" -raw).Trim()
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "libreoffice" -ItemType "directory" > nul
}

if ( [System.Version]"$($RemoteLatestTag)" -gt [System.Version]"$($CurrentVersion)" ) {
    Write-Output "update needed to: $($RemoteLatestTag)"

    $Platform = "Win"
    $Arch = "x86_64"
    $TargetFileName = "LibreOffice_$($MainVersion)_$($Platform)_$($Arch.replace('_', '-')).msi"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"

    $Url ="https://download.documentfoundation.org/libreoffice/stable/$($MainVersion)/$($Platform.ToLower())/$($Arch)/$($TargetFileName)"

    # Write-Output ">$($Url)<"

    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
    $Sha256Sum = (Invoke-WebRequest -Uri "$($Url).sha256").Content.Trim().split(' ')[0]
    $ProgressPreference = 'Continue'

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        # download file
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }
    # download signature
    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
    Invoke-WebRequest -Uri "$($Url).asc" -OutFile "$($DownloadFullPath).asc"
    $ProgressPreference = 'Continue'

    # Write-Output ">$($Sha256Sum)<"

    if ((Get-FileHash $DownloadFullPath).Hash.ToLower() -eq "$($Sha256Sum)") {
        # Write-Output "ok"
            # && Start-MpScan -ScanPath $DownloadFullPath -ScanType CustomScan `
        Rename-Item $TargetDir $BackupDir `
            && Write-Output "check signature" `
            && & $gpg --verify "$($DownloadFullPath).asc" $DownloadFullPath >nul 2>&1 `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && Start-Process -NoNewWindow msiexec.exe -ArgumentList "/a $($DownloadFullPath) /qb TARGETDIR=$($TargetDir)" -Wait `
            && Write-Output "$($RemoteLatestTag)" > "$($TargetDir)\VERSION" `
            && Write-Output "cleanup" `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path "$($DownloadFullPath).asc" -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)" `
        || Rename-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
