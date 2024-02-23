# [CmdletBinding()]
[cultureinfo]::CurrentUICulture='en-US'

$TargetPath = "$($env:LOCALAPPDATA)\Programs"

# $7Zip = "$($TargetPath)\7-Zip\7z.exe"

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

# $gpg  = "$($TargetPath)\git\usr\bin\gpg.exe"

$TargetDir = "$($TargetPath)\7-Zip"
$BackupDir = "$($TargetDir).bak"

Write-Output "check updates for: 7-Zip"

$MainVersionURL = "https://sourceforge.net/projects/sevenzip/files/7-Zip/"

$ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
$RemoteLatestTag = "$((Invoke-WebRequest -Uri $MainVersionURL).Content.Split("`n") `
                   | Select-String -Pattern 'class="folder"' -SimpleMatch `
                   | Select-Object -First 1
                )".Split('"')[3] -replace "(\/[^\/]*){2}$", ""

$ProgressPreference = 'Continue'


$RemoteLatestTag = $RemoteLatestTag.Split("/")[-1]

$CurrentVersion = "0.0"
if ( Test-Path -Path $TargetDir ) {
    $CurrentVersion = "$(Get-Content "$($TargetDir)\readme.txt" -First 1)".Trim().Split(" ")[1]
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "7-Zip" -ItemType "directory" > nul
}

# Write-Output "remote: >$($RemoteLatestTag)<"
# Write-Output "local : >$($CurrentVersion)<"

if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion ) {
    Write-Output "update needed to: $($RemoteLatestTag)"

    $Arch = "x64"
    $TargetFileName = "7z$($RemoteLatestTag.Replace('.', ''))-$($Arch).msi"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"
    $OldPath = Get-Location

    $Url ="https://www.7-zip.org/a/$($TargetFileName)"

    # Write-Output ">$($DownloadFullPath)<"
    # Write-Output ">$($Url)<"

    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
    $ShaSum = ("$((Invoke-WebRequest -Uri "$($MainVersionURL)/$($RemoteLatestTag)/").Content.Split("`n") `
                | Select-String -Pattern "net.sf.files" -SimpleMatch)".split("=")[1].replace(";", "") `
                | ConvertFrom-Json
              ).$TargetFileName.sha1

    $ProgressPreference = 'Continue'

    if ( -not (Test-Path -Path $DownloadFullPath) ) {
        # download file
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }
#     # download signature
#     $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
#     Invoke-WebRequest -Uri "$($Url).asc" -OutFile "$($DownloadFullPath).asc"
#     $ProgressPreference = 'Continue'

    # Write-Output ">$($ShaSum)<"

    if ((Get-FileHash $DownloadFullPath -Algorithm SHA1).Hash.ToLower() -eq "$($ShaSum)") {
        Move-Item $TargetDir $BackupDir `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath >nul `
            && Write-Output "extract" `
            && Start-Process -NoNewWindow msiexec.exe -ArgumentList "/a $($DownloadFullPath) /qb TARGETDIR=$($TargetDir).new" -Wait `
            && Set-Location $(join-path "$($TargetDir).new" 'Files') `
            && Move-Item '7*' $TargetDir `
            && Write-Output "cleanup" `
            && Set-Location $OldPath `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Remove-Item -Path "$($TargetDir).new" -Recurse -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)" `
        || Move-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
