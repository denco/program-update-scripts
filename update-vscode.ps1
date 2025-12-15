# [CmdletBinding()]
[cultureinfo]::CurrentUICulture='en-US'

$TargetPath = "$($env:LOCALAPPDATA)\Programs"

$7Zip = "$($TargetPath)\7-Zip\7z.exe"

$vScanner = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"

$ToolName = "vscode"
$ToolUpdateDelayDays = -1
$TargetDir = "$($TargetPath)\$($ToolName)"
$BackupDir = "$($TargetDir).bak"
$ToolRepoBaseUrl = "https://github.com/microsoft/$($ToolName)"

Write-Output "check updates for: $($ToolName)"

$RemoteLatestTag = [System.Version]"$(git ls-remote --tags "$($ToolRepoBaseUrl).git" `
                        | Select-String -Pattern "alpha|beta|1\.999\.0|\{\}" -NotMatch `
                        | Sort-Object -erroraction 'SilentlyContinue' { [System.version]($_ -split '/')[2] } `
                        | Select-Object -Last 1
                    )".Trim().Split('/')[2]
exit
$CurrentVersion = "0.0.0.0"

$UpdateNotBefore = -1
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\VERSION )) {
    [string[]] $VersionFileContent = Get-Content "$($TargetDir)\VERSION"
    # get current version
    $CurrentVersion = [System.Version]$VersionFileContent[0].Trim()

    if ( $VersionFileContent.Length -gt 1 ) {
        $UpdateNotBefore = [int64]($VersionFileContent[1]).Trim()
    }
    if ( $VersionFileContent.Length -gt 2 ) {
        $postponedUpdateVersion = [System.Version]($VersionFileContent[2]).Trim()
    }
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "$($ToolName)" -ItemType "directory" -erroraction 'SilentlyContinue' > nul
}

$Now = [int64](Get-Date -AsUTC -UFormat "%s")
# check update is needed, but will be delayed
if ( $RemoteLatestTag -gt $CurrentVersion -And $UpdateNotBefore -eq -1 ) {
    $NotBefore = [int64](Get-Date -AsUTC -UFormat "%s") + (24 * 3600 * $ToolUpdateDelayDays)
    Write-Output "Update will be delayed till: $(Get-Date -AsUTC -UnixTimeSeconds $NotBefore -UFormat "%F %T")"
    Write-Output "$($CurrentVersion)`r`n$($NotBefore)`r`n$($RemoteLatestTag)" > "$($TargetDir)\VERSION"
}
elseif ( $RemoteLatestTag -eq $postponedUpdateVersion -And $Now -lt $UpdateNotBefore){
    Write-Output "Update to: $($RemoteLatestTag) is delayed till: $(Get-Date -AsUTC -UnixTimeSeconds $UpdateNotBefore -UFormat "%F %T")"
}
elseif ( $RemoteLatestTag -gt $postponedUpdateVersion -And $Now -lt $UpdateNotBefore){
    $NotBefore = [int64](Get-Date -AsUTC -UFormat "%s") + (24 * 3600 * $ToolUpdateDelayDays)
    Write-Output "Latest version: $($RemoteLatestTag) is greater then postponed: $($postponedUpdateVersion) update will be delayed till: $(Get-Date -AsUTC -UnixTimeSeconds $NotBefore -UFormat "%F %T")"
    Write-Output "$($CurrentVersion)`r`n$($NotBefore)`r`n$($RemoteLatestTag)" > "$($TargetDir)\VERSION"
}
# check update is needed and is allowed
elseif ( $RemoteLatestTag -gt $CurrentVersion -And $Now -gt $UpdateNotBefore ) {

    Write-Output "update needed to: $($RemoteLatestTag)"

    $TargetFileName = "VSCode-win32-x64-$($RemoteLatestTag).zip"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"
    $OldPath = Get-Location

    $DownloadBaseUrl ="https://update.code.visualstudio.com/$($RemoteLatestTag)/win32-x64-archive/stable"
    $Url ="$($DownloadBaseUrl)"
    $CheckSum = "$("$((Invoke-WebRequest -Uri "https://code.visualstudio.com/sha?build=stable").Content.Split("},{") `
                       | Select-String -Pattern "$($TargetFileName)" -SimpleMatch
                  )".Split(",") `
                  | Select-String -Pattern "sha" -SimpleMatch
                )".Split(":")[1].Replace("`"","")

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }

    if ((Get-FileHash $DownloadFullPath -Algorithm SHA256).Hash.ToLower() -eq "$($CheckSum.ToLower())") {
        Rename-Item $TargetDir $BackupDir `
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
        || Rename-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
