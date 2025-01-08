# [CmdletBinding()]
[cultureinfo]::CurrentUICulture='en-US'


$TargetPath = "$($env:LOCALAPPDATA)\Programs"

$7Zip = "$($TargetPath)\7-Zip\7z.exe"

$vScanner = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"

$TargetDir = "$($TargetPath)\beekeeper"
$BackupDir = "$($TargetDir).bak"

Write-Output "check updates for: beekeeper studio"

##old# $excludePattern = "-|{}|latest|v7\.7\.0|v7\.8\.0|v7\.8\.1"
$excludePattern = "-|{}|latest|v7\.[7|8]\.[0|1]"
$RemoteLatestTag = "$(git ls-remote --tags "https://github.com/beekeeper-studio/beekeeper-studio.git" `
                        | Select-String -Pattern $excludePattern -NotMatch `
                        | Sort-Object -erroraction 'SilentlyContinue' { [System.version]($_ -split 'v')[1] } `
                        | Select-Object -Last 1
                    )".Trim().Split('v')[1]

$CurrentVersion = "0.0.0"
if (( Test-Path -Path $TargetDir) -And (Test-Path -Path $TargetDir\VERSION )) {
    $CurrentVersion = (get-content "$($TargetDir)\VERSION" -raw).Trim()
} else {
    # create new empty dir as backup fallback
    New-Item -Path "$($TargetPath)" -Name "beekeeper" -ItemType "directory" -erroraction 'SilentlyContinue' > nul
}

# Write-Output "remote: >$($RemoteLatestTag)<"
# Write-Output "local : >$($CurrentVersion)<"

if ( [System.Version]$RemoteLatestTag -gt [System.Version]$CurrentVersion ) {
    Write-Output "update needed to: $($RemoteLatestTag)"


    $TargetFileName = "Beekeeper-Studio-Setup-$($RemoteLatestTag).exe"
    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"
    $OldPath = Get-Location

    $BaseUrl = "https://github.com/beekeeper-studio/beekeeper-studio/releases/download/v$($RemoteLatestTag)"
    $Url ="$($BaseUrl)/$($TargetFileName)"

    try {
        $Sha512SumEncoded = "$([System.Text.Encoding]::UTF8.GetString(
                                                            (Invoke-WebRequest -Uri "$($BaseUrl)/latest.yml").Content
                                                            ).Split("`n") `
                    | Select-String -Pattern 'sha512:' -AllMatches `
                    | Select-Object -Last 1)".Split(" ")[1].Trim()

        # Write-Output "OLD Path: $($OldPath)"
        # Write-Output "URL: $($Url)"
        # Write-Output "SHA: $($Sha512SumEncoded)"
        $ShaSum = [System.BitConverter]::ToString([System.Convert]::FromBase64String($Sha512SumEncoded)).Replace("-", "").ToLower()
        # write-Output "Decoded: $($ShaSum)"

        if ( -not (Test-Path -Path $DownloadFullPath)  ) {

                $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
                Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
                $ProgressPreference = 'Continue'
        }
    } catch {
            Write-Host "Something goes wrong by download!" -ForegroundColor red
            exit 1
    }

    if ((Get-FileHash $DownloadFullPath -Algorithm SHA512).Hash.ToLower() -eq "$($ShaSum)") {
            # && Start-MpScan -ScanPath $DownloadFullPath -ScanType CustomScan `
        Move-Item $TargetDir $BackupDir `
            && Write-Output "check malware" `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && Write-Output "extract" `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir).new" > nul `
            && Set-Location $(join-path "$($TargetDir).new" '$PLUGINSDIR') `
            && & $7Zip x "app-64.7z" -o"$($TargetDir)" > nul `
            && Write-Output "$($RemoteLatestTag)" > "$($TargetDir)\VERSION" `
            && Write-Output "cleanup" `
            && Set-Location $OldPath `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path "$($TargetDir).new" -Recurse -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Write-Output "updated to version: $($RemoteLatestTag)" `
        || Move-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
