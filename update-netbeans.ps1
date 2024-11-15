# [CmdletBinding()]
[cultureinfo]::CurrentUICulture='en-US'


$TargetPath = "$($env:LOCALAPPDATA)\Programs"

$7Zip = "$($TargetPath)\7-Zip\7z.exe"

$vScanner = "$(Get-Childitem `
                –Path 'C:\ProgramData\Microsoft\Windows Defender\Platform' `
                -Include *MpCmdRun.exe* `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue `
            | Where-Object { $_.FullName -NotMatch 'X86' } `
            | Sort-Object LastWriteTime `
            | Select-Object -Last 1
            )"

# gpg
# gpg --receive-keys 7B037EEBE0F0DEDFEE65B6983703AC389A12A9D4
# gpg --receive-keys 8FE1C26F15E0320E740BAED84A2601CEDA9382F3

$gpg  = "$($TargetPath)\git\usr\bin\gpg.exe"

$TargetDir = "$($TargetPath)\netbeans"
$BackupDir = "$($TargetDir).bak"

Write-Output "check updates for: netbeans"

$RemoteLatestTag = "$(git ls-remote --tags "https://github.com/apache/netbeans.git" `
                        | Select-String -Pattern "-|{}|\." -NotMatch `
                        | Sort-Object -erroraction 'SilentlyContinue' { ("$_" -split '/')[2] } `
                        | Select-Object -Last 1
                    )".Trim().Split('/')[2]

$CurrentVersion = "0"
if ( Test-Path -Path $TargetDir ) {
    $CurrentVersion = ($(get-content "$($TargetDir)\etc\netbeans.conf"
                            | Where-Object {$_ -match "="}
                            | ConvertFrom-StringData
                        ).netbeans_default_userdir
                      ).Split("/")[1].Replace('"','')
    # netbeans_default_userdir="${DEFAULT_USERDIR_ROOT}/18"
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "netbeans" -ItemType "directory" > nul
}

# Write-Output "remote: >$($RemoteLatestTag)<"
# Write-Output "local : >$($CurrentVersion)<"

if ( [System.Version]"$($RemoteLatestTag).0.0" -gt [System.Version]"$($CurrentVersion).0.0" ) {
    Write-Output "update needed to: $($RemoteLatestTag)"

    $TargetFileName = "netbeans-$($RemoteLatestTag)-bin.zip"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"

    $Url ="https://dlcdn.apache.org/netbeans/netbeans/$($RemoteLatestTag)/$($TargetFileName)"
    # Write-Output "URL: $($Url)"

    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
    $ShaSum = (Invoke-WebRequest -Uri "$($Url).sha512").Content.Split(" ")[0]
    # Write-Output "ShaSum: $($ShaSum)"
    $ProgressPreference = 'Continue'

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Write-Output "download"
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }
    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
    Invoke-WebRequest -Uri "$($Url).asc" -OutFile "$($DownloadFullPath).asc"
    $ProgressPreference = 'Continue'

    if ((Get-FileHash $DownloadFullPath -Algorithm SHA512).Hash.ToLower() -eq "$($ShaSum)") {
        Move-Item $TargetDir $BackupDir `
            && Write-Output "check signature" `
            && & $gpg --verify "$($DownloadFullPath).asc" $DownloadFullPath >nul 2>&1 `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir).new" > nul `
            && Move-Item "$($TargetDir).new\netbeans" $TargetDir `
            && Write-Output "cleanup" `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path "$($DownloadFullPath).asc" -Force `
            && Remove-Item -Path "$($TargetDir).new" -Recurse -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)" `
        || Move-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
