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


# gpg keys: https://downloads.apache.org/maven/KEYS
# gpg
# curl -s https://downloads.apache.org/maven/KEYS | gpg --import

$gpg  = "$($TargetPath)\git\usr\bin\gpg.exe"

$ToolName = "maven"
$TargetDir = "$($TargetPath)\$($ToolName)"
$BackupDir = "$($TargetDir).bak"
$ToolRepoBaseUrl = "https://github.com/apache/$($ToolName)"

Write-Output "check updates for: $($ToolName)"

$RemoteLatestTag = "$(git ls-remote --tags "$($ToolRepoBaseUrl).git" `
                        | Select-String -Pattern "alpha|beta|\{\}" -NotMatch `
                        | Select-String -Pattern "maven-" -SimpleMatch `
                        | Select-Object -Last 1
                    )".Trim().Split("/")[2].Split("-")[1]

$CurrentVersion = "0.0.0"
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\VERSION )) {
    $CurrentVersion = (get-content "$($TargetDir)\VERSION" -raw).Trim()
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "$($ToolName)" -ItemType "directory" -erroraction 'SilentlyContinue' > nul
    Write-Output "$($CurrentVersion)" > "$($TargetDir)\VERSION" `
}

if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion ) {
    Write-Output "update needed to: $($RemoteLatestTag)"
    # https://dlcdn.apache.org/maven/maven-3/3.9.6/binaries/apache-maven-3.9.6-bin.zip
    $TargetFileName = "apache-maven-$($RemoteLatestTag)-bin.zip"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"
    $OldPath = Get-Location

    $DownloadBaseUrl ="https://dlcdn.apache.org/maven/maven-$($RemoteLatestTag.Split('.')[0])/$($RemoteLatestTag)/binaries"
    $Url ="$($DownloadBaseUrl)/$($TargetFileName)"


    $CheckSum = (Invoke-WebRequest -Uri "$($Url).sha512").Content

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }
    # download signature
    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
    Invoke-WebRequest -Uri "$($Url).asc" -OutFile "$($DownloadFullPath).asc"
    $ProgressPreference = 'Continue'

    if ((Get-FileHash $DownloadFullPath -Algorithm SHA512).Hash.ToLower() -eq "$($CheckSum.ToLower())") {
        Move-Item $TargetDir $BackupDir `
            && Write-Output "check signature" `
            && & $gpg --verify "$($DownloadFullPath).asc" $DownloadFullPath >nul 2>&1 `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir)\.." > nul `
            && Move-Item "$($TargetDir)\..\apache-maven*" $TargetDir `
            && Write-Output "$($RemoteLatestTag)" > "$($TargetDir)\VERSION" `
            && Write-Output "cleanup" `
            && Set-Location $OldPath `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path "$($DownloadFullPath).asc" -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)"
        || Move-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
