# [CmdletBinding()]
[cultureinfo]::CurrentUICulture='en-US'


$TargetPath = "$($env:LOCALAPPDATA)\Programs"

$7Zip = "$($TargetPath)\7-Zip\7z.exe"

$vScanner = "$(Get-Childitem –Path 'C:\ProgramData\Microsoft\Windows Defender\Platform' `
                             -Include *MpCmdRun.exe* -Exclude -File -Recurse -ErrorAction SilentlyContinue `
            | Where-Object { $_.FullName -NotMatch 'X86' } `
            | Sort-Object LastWriteTime -Descending `
            | Select-Object -Last 1)"

# gpg
# gpg --receive-keys C1E4CBA3AD78D3AFD894F9E0B7A66F03B59076A8
$gpg  = "$($TargetPath)\git\usr\bin\gpg.exe"

$TargetDir = "$($TargetPath)\keepassxc"
$BackupDir = "$($TargetDir).bak"

Write-Output "check updates for: keepassxc"


$RemoteLatestTag = "$(git ls-remote --tags "https://github.com/keepassxreboot/keepassxc.git" `
                        | Select-String -Pattern "-|{}|latest" -NotMatch `
                        | Sort-Object -erroraction 'SilentlyContinue' { ("$_" -split '/')[2] } `
                        | Select-Object -Last 1
                    )".Trim().Split('/')[2]

$CurrentVersion = "0.0.0"
if ( Test-Path -Path $TargetDir ) {
    $CurrentVersion = (get-content "$($TargetDir)\VERSION" -raw).Trim()
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "keepassxc" -ItemType "directory" > nul
    New-Item -Path "$($TargetPath)\keepassxc" -Name "config" -ItemType "directory" > nul
}

# Write-Output "remote: >$($RemoteLatestTag)<"
# Write-Output "local : >$($CurrentVersion)<"

if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion ) {
    Write-Output "update needed to: $($RemoteLatestTag)"

    $TargetFileName = "KeePassXC-$($RemoteLatestTag)-Win64-LegacyWindows.zip"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"


    $Url ="https://github.com/keepassxreboot/keepassxc/releases/download/$($RemoteLatestTag)/$($TargetFileName)"
    # Write-Output "URL: $($Url)"

    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
    $ShaSum = [System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -Uri "$($Url).DIGEST").Content).Split(" ")[0]
    # Write-Output "ShaSum: $($ShaSum)"
    $ProgressPreference = 'Continue'

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Write-Output "download"
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }
    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
    Invoke-WebRequest -Uri "$($Url).sig" -OutFile "$($DownloadFullPath).sig"
    $ProgressPreference = 'Continue'

    # # && Start-MpScan -ScanPath $DownloadFullPath `
    if ((Get-FileHash $DownloadFullPath -Algorithm SHA256).Hash.ToLower() -eq "$($ShaSum.ToLower())") {
        Move-Item $TargetDir $BackupDir `
            && Write-Output "check signature" `
            && & $gpg --verify "$($DownloadFullPath).sig" $DownloadFullPath >nul 2>&1 `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir).new" >nul `
            && Move-Item "$($TargetDir).new\*" $TargetDir `
            && Move-Item "$($TargetDir).bak\config" "$($TargetDir)\" `
            && Write-Output "$($RemoteLatestTag)" > "$($TargetDir)\VERSION" `
            && Write-Output "cleanup" `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path "$($DownloadFullPath).sig" -Force `
            && Remove-Item -Path "$($TargetDir).new" -Recurse -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)" `
        || Move-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
