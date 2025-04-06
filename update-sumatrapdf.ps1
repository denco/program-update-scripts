# [CmdletBinding()]
[cultureinfo]::CurrentUICulture='en-US'

$TargetPath = "$($env:LOCALAPPDATA)\Programs"

$7Zip = "$($TargetPath)\7-Zip\7z.exe"

$vScanner = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"

$ToolName = "sumatrapdf"
$TargetDir = "$($TargetPath)\$($ToolName)"
$BackupDir = "$($TargetDir).bak"
$ToolRepoBaseUrl = "https://github.com/sumatrapdfreader/$($ToolName)"

Write-Output "check updates for: $($ToolName)"

$RemoteLatestTag = "$(git ls-remote --tags "$($ToolRepoBaseUrl).git" `
                        | Select-String -Pattern "rel" -SimpleMatch `
                        | Sort-Object -erroraction 'SilentlyContinue' { [System.version]($_ -split '/' -replace 'rel', '')[2] } `
                        | Select-Object -Last 1
                    )".Trim().Split('/')[2].Replace("rel","")

$CurrentVersion = "0.0.0"
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\VERSION )) {
    $CurrentVersion = (get-content "$($TargetDir)\VERSION" -raw).Trim()
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "$($ToolName)" -ItemType "directory" -erroraction 'SilentlyContinue' > nul
}

# Write-Output "remote: >$($RemoteLatestTag)<"
# Write-Output "local : >$($CurrentVersion)<"

if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion ) {
    Write-Output "update needed to: $($RemoteLatestTag)"

    $TargetFileName = "SumatraPDF-$($RemoteLatestTag)-64.zip"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"
    $OldPath = Get-Location

    $DownloadBaseUrl ="$($ToolRepoBaseUrl)/releases/download/$($RemoteLatestTag)"
    $DownloadBaseUrl ="https://www.sumatrapdfreader.org/dl/rel/$($RemoteLatestTag)"
    $Url ="$($DownloadBaseUrl)/$($TargetFileName)"
#     $CheckSum = [System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -Uri "$($Url).sha256").Content).Split(" ")[0]

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }

#     if ((Get-FileHash $DownloadFullPath -Algorithm SHA256).Hash.ToLower() -eq "$($CheckSum.ToLower())") {
    if (1 -eq 1) {
        Rename-Item $TargetDir $BackupDir `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir)" > nul `
            && Write-Output "$($RemoteLatestTag)" > "$($TargetDir)\VERSION" `
            && (Move-Item "$($BackupDir)\SumatraPDF-settings.txt" $TargetDir > nul 2>&1 || Write-Output "No settings file") `
            && Move-Item "$($TargetDir)\SumatraPDF*.exe" "$($TargetDir)\SumatraPDF.exe" `
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
