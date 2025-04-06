[CmdletBinding()]

$TargetPath = "$($env:LOCALAPPDATA)\Programs"

$7Zip = "$($TargetPath)\7-Zip\7z.exe"

$vScanner = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"

$TargetDir = "$($TargetPath)\dbeaver"
$BackupDir = "$($TargetDir).bak"

Write-Output "check updates for: dbeaver"

$RemoteLatestTag = "$(git ls-remote --tags "https://github.com/dbeaver/dbeaver.git" `
                        | Sort-Object -erroraction 'SilentlyContinue' { [System.version]($_ -split '/')[2] } `
                        | Select-Object -Last 1
                    )".Trim().Split('/')[2]

$CurrentVersion = "0.0.0"
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\.eclipseproduct )) {
    $CurrentVersion = (Convertfrom-Stringdata (get-content "$($TargetDir)\.eclipseproduct" -raw))."version"
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "dbeaver" -ItemType "directory" > nul 2>&1
}

# Write-Output "remote: >$($RemoteLatestTag)<"
# Write-Output "local : >$($CurrentVersion)<"

if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion ) {
    Write-Output "update needed to: $($RemoteLatestTag)"
#
    $TargetFileName = "dbeaver-ce-$($RemoteLatestTag)-win32.win32.x86_64.zip"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"

    $Url ="https://github.com/dbeaver/dbeaver/releases/download/$($RemoteLatestTag)/$($TargetFileName)"

    $Sha256Sum = (Invoke-WebRequest -Uri "https://dbeaver.io/files/$($RemoteLatestTag)/checksum/$($TargetFileName).sha256").Content
    $Sha256Sum = [System.Text.Encoding]::UTF8.GetString($Sha256Sum).Trim()

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Write-Output "download"
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }
    # Write-Output ">$($Sha256Sum)<"

    if ((Get-FileHash $DownloadFullPath).Hash.ToLower() -eq "$($Sha256Sum)") {
        # Write-Output "ok"
        Rename-Item $TargetDir $BackupDir `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir).new" >nul `
            && Move-Item "$($TargetDir).new\dbeaver" $TargetDir `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path "$($TargetDir).new" -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)" `
        || Rename-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
