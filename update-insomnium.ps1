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

$TargetDir = "$($TargetPath)\insomnium"
$BackupDir = "$($TargetDir).bak"

Write-Output "check updates for: insomnium"


$RemoteLatestTag = "$(git ls-remote --tags "https://github.com/ArchGPT/insomnium.git" `
                        | Select-String -Pattern "alpha|beta|\{\}" -NotMatch `
                        | Select-String -Pattern "core@" -AllMatches `
                        | Select-Object -Last 1
                    )".Trim().Split('@')[1]

$CurrentVersion = "0.0.0"
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\VERSION )) {
    $CurrentVersion = (get-content "$($TargetDir)\VERSION" -raw).Trim()
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "insomnium" -ItemType "directory" -erroraction 'SilentlyContinue' > nul
}

# Write-Output "remote: >$($RemoteLatestTag)<"
# Write-Output "local : >$($CurrentVersion)<"

if ( [System.Version]$RemoteLatestTag.Split('-')[0] -gt [System.Version]$CurrentVersion.Split('-')[0] ) {
    Write-Output "update needed to: $($RemoteLatestTag)"

    $TargetFileName = "insomnium-$($RemoteLatestTag)-full.nupkg"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"
    $OldPath = Get-Location

    $BaseUrl ="https://github.com/ArchGPT/insomnium/releases/download/core%40$($RemoteLatestTag)"
    $Url ="$($BaseUrl)/$($TargetFileName)"
    $ShaSum = [System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -Uri "$($BaseUrl)/RELEASES").Content).Split(" ")[0]

    # Write-Output "OLD Path: $($OldPath)"
    # Write-Output "URL: $($Url)"
    # Write-Output "SHASUM: $($ShaSum)"

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }

    if ((Get-FileHash $DownloadFullPath -Algorithm SHA1).Hash.ToLower() -eq "$($ShaSum.ToLower())") {
        Move-Item $TargetDir $BackupDir `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir).new" > nul `
            && Set-Location $(join-path "$($TargetDir).new" 'lib') `
            && Move-Item 'net*' $TargetDir `
            && Write-Output "$($RemoteLatestTag)" > "$($TargetDir)\VERSION" `
            && Write-Output "cleanup" `
            && Set-Location $OldPath `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path "$($TargetDir).new" -Recurse -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)"
        || Move-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
