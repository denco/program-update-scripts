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

$ToolName = "yed"
$TargetDir = "$($TargetPath)\$($ToolName)"
$BackupDir = "$($TargetDir).bak"
$ToolRepoBaseUrl = "https://www.yworks.com/resources/$($ToolName)/demo"

Write-Output "check updates for: $($ToolName)"

$RemoteLatestTag = "$((Invoke-WebRequest -Uri "https://www.yworks.com/products/yed/download#download").Content.Split('"').Split("<").Split(">") `
                            | Select-String -Pattern "Download yEd " -AllMatches
                        )".Split(' ')[2]

$CurrentVersion = "0.0.0"
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\VERSION )) {
        $CurrentVersion = (get-content "$($TargetDir)\VERSION" -raw).Trim()
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "$($ToolName)" -ItemType "directory" -erroraction 'SilentlyContinue' > nul
}

# https://www.yworks.com/resources/yed/demo/yEd-3.24.zip

if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion ) {
    Write-Output "update needed to: $($RemoteLatestTag)"

    $TargetFileName = "yEd-$($RemoteLatestTag).zip"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"
    $OldPath = Get-Location

    $DownloadBaseUrl ="$($ToolRepoBaseUrl)"
    $Url ="$($DownloadBaseUrl)/$($TargetFileName)"
    # $CheckSum = [System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -Uri "$($Url).sha256").Content).Split(" ")[0]

    if ( -not (Test-Path -Path $DownloadFullPath)  ) {
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri "$($Url)" -OutFile "$($DownloadFullPath)"
        $ProgressPreference = 'Continue'
    }

    # if ((Get-FileHash $DownloadFullPath -Algorithm SHA256).Hash.ToLower() -eq "$($CheckSum.ToLower())") {
    if (1 -eq 1) {
        Move-Item $TargetDir $BackupDir `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir).new" > nul `
            && Move-Item "$($TargetDir).new\*" $TargetDir `
            && Write-Output "$($RemoteLatestTag)" > "$($TargetDir)\VERSION" `
            && Copy-Item "$($BackupDir)\yed.bat" -Destination "$($TargetDir)" `
            && Copy-Item "$($BackupDir)\yed.lnk" -Destination "$($TargetDir)" `
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
