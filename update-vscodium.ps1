# [CmdletBinding()]
[cultureinfo]::CurrentUICulture='en-US'

$TargetPath = "$($env:LOCALAPPDATA)\Programs"

$7Zip = "$($TargetPath)\7-Zip\7z.exe"

$vScanner = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"

$ToolName = "vscodium"
$ToolUpdateDelayDays = 3
$TargetDir = "$($TargetPath)\$($ToolName)"
$BackupDir = "$($TargetDir).bak"
$ToolRepoBaseUrl = "https://github.com/VSCodium/$($ToolName)"

Write-Output "check updates for: $($ToolName)"

$RemoteLatestTag = "$(git ls-remote --tags "$($ToolRepoBaseUrl).git" `
                        | Select-String -Pattern "alpha|beta|\{\}" -NotMatch `
                        | Select-Object -Last 1
                    )".Trim().Split('/')[2]

$CurrentVersion = "0.0.0.0"
$UpdateNotBefore = -1
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\VERSION )) {
    [string[]] $VersionFileContent = Get-Content "$($TargetDir)\VERSION"
    # get current version
    $CurrentVersion = $VersionFileContent[0].Trim()

    if ( $VersionFileContent.Length -gt 1 ) {
        $UpdateNotBefore = [int64]($VersionFileContent[1]).Trim()
    }
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "$($ToolName)" -ItemType "directory" -erroraction 'SilentlyContinue' > nul
}

$Now = [int64](Get-Date -AsUTC -UFormat "%s")
# check update is needed, but will be delayed
if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion -And $UpdateNotBefore -eq -1 ) {
    $NotBefore = [int64](Get-Date -AsUTC -UFormat "%s") + (24 * 3600 * $ToolUpdateDelayDays)
    Write-Output "Update will be delayed till: $(Get-Date -AsUTC -UnixTimeSeconds $NotBefore -UFormat "%F %T")"
    Write-Output "$($CurrentVersion)`r`n$($NotBefore)" > "$($TargetDir)\VERSION"
}
# check update is needed and is allowed
elseif ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion -And $Now -gt $UpdateNotBefore ) {
    Write-Output "update needed to: $($RemoteLatestTag)"

    $TargetFileName = "VSCodium-win32-x64-$($RemoteLatestTag).zip"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"
    $OldPath = Get-Location

    $DownloadBaseUrl ="$($ToolRepoBaseUrl)/releases/download/$($RemoteLatestTag)"
    $Url ="$($DownloadBaseUrl)/$($TargetFileName)"
    $CheckSum = [System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -Uri "$($Url).sha256").Content).Split(" ")[0]

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }

    if ((Get-FileHash $DownloadFullPath -Algorithm SHA256).Hash.ToLower() -eq "$($CheckSum.ToLower())") {
        Move-Item $TargetDir $BackupDir `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir)" > nul `
            && Write-Output "$($RemoteLatestTag)" > "$($TargetDir)\VERSION" `
            && Write-Output "cleanup" `
            && Set-Location $OldPath `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)"
        || Move-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
