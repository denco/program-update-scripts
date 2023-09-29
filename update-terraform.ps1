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

# # gpg
# # gpg --receive-keys C874011F0AB405110D02105534365D9472D7468F
$gpg  = "$($TargetPath)\git\usr\bin\gpg.exe"

$TargetFile = "$($TargetPath)\bin\terraform.exe"
$BackupFile = "$($TargetFile).bak"

Write-Output "check updates for: terraform"


$ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
$RemoteLatestTag = "$(git ls-remote --tags https://github.com/hashicorp/terraform.git `
                      | Select-String -Pattern "-|{}" -NotMatch `
                      | Select-Object -Last 1
                    )".Trim().Split('/')[2].Replace('v', '')
$ProgressPreference = 'Continue'

try {
    $CurrentVersion = "$(& $TargetFile --version)".Split(' ')[1].Replace('v','')
} catch {
    New-Item -Path "$($TargetPath)\bin" -Name "terraform.exe" -ItemType "file" >nul 2>&1
    $CurrentVersion = "0.0.0"
}

# Write-Output "remote: >$($RemoteLatestTag)<"
# Write-Output "local : >$($CurrentVersion)<"

if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion ) {
    Write-Output "update needed to: $($RemoteLatestTag)"

    $TargetFileName = "terraform_$($RemoteLatestTag)_windows_amd64.zip"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"

    $ShaSumFile = "terraform_$($RemoteLatestTag)_SHA256SUMS"
    $DownloadFullPathShaSumFile = "$($env:TEMP)\$($ShaSumFile)"

    $ShaSumSignatureFile = "$($ShaSumFile).sig"
    $DownloadFullPathShaSumSignatureFile = "$($env:TEMP)\$($ShaSumSignatureFile)"

    $BaseUrl ="https://releases.hashicorp.com/terraform/$($RemoteLatestTag)"
    $Url ="$($BaseUrl)/$($TargetFileName)"

    # Write-Output ">$($DownloadFullPath)<"
    # Write-Output ">$($Url)<"

    if ( -not (Test-Path -Path $DownloadFullPath) ) {
        # download file
        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }

    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
    Invoke-WebRequest -Uri "$($BaseUrl)/$($ShaSumFile)" -OutFile $DownloadFullPathShaSumFile
    Invoke-WebRequest -Uri "$($BaseUrl)/$($ShaSumSignatureFile)" -OutFile $DownloadFullPathShaSumSignatureFile
    $ProgressPreference = 'Continue'

    Write-Output "check signature" `
        && gpg --verify $DownloadFullPathShaSumSignatureFile $DownloadFullPathShaSumFile >nul 2>&1 `
    || exit 0

    $Sha256Sum = "$((Get-Content $DownloadFullPathShaSumFile).Split("`n") `
      | Select-String -Pattern $TargetFileName -SimpleMatch
    )".Trim().split(' ')[0]

    if ((Get-FileHash $DownloadFullPath).Hash.ToLower() -eq "$($Sha256Sum)") {
        Move-Item $TargetFile $BackupFile `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath >nul `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" "terraform.exe" -y -o"$($TargetPath)\bin" > nul `
            && Remove-Item -Path $BackupFile -Force `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path $DownloadFullPathShaSumFile -Force `
            && Remove-Item -Path $DownloadFullPathShaSumSignatureFile -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)" `
        || Move-Item $BackupFile $TargetFile
    }
} else {
    Write-Output "Nothing to update."
}
