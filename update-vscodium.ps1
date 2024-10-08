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
            | Sort-Object LastWriteTime -Descending `
            | Select-Object -Last 1
            )"

$ToolName = "vscodium"
$TargetDir = "$($TargetPath)\$($ToolName)"
$BackupDir = "$($TargetDir).bak"
$ToolRepoBaseUrl = "https://github.com/VSCodium/$($ToolName)"

Write-Output "check updates for: $($ToolName)"

$RemoteLatestTag = "$(git ls-remote --tags "$($ToolRepoBaseUrl).git" `
                        | Select-String -Pattern "alpha|beta|\{\}" -NotMatch `
                        | Select-Object -Last 1
                    )".Trim().Split('/')[2]

$CurrentVersion = "0.0.0.0"
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\VERSION )) {
    $CurrentVersion = (get-content "$($TargetDir)\VERSION" -raw).Trim()
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "$($ToolName)" -ItemType "directory" -erroraction 'SilentlyContinue' > nul
}


if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion ) {
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
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath >nul `
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
