# [CmdletBinding()]
[cultureinfo]::CurrentUICulture = 'en-US'

$TargetPath = "$($env:LOCALAPPDATA)\Programs"

$7Zip = "$($TargetPath)\7-Zip\7z.exe"

$vScanner = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"

# gpg
# gpg --keyserver hkps://keys.openpgp.org --recv-keys 4ED778F539E3634C779C87C6D7062848A1AB005C
# gpg --keyserver hkps://keys.openpgp.org --recv-keys 141F07595B7B3FFE74309A937405533BE57C7D57
# gpg --keyserver hkps://keys.openpgp.org --recv-keys 74F12602B6F1C4E913FAA37AD3A89613643B6201
# gpg --keyserver hkps://keys.openpgp.org --recv-keys DD792F5973C6DE52C432CBDAC77ABFA00DDBF2B7
# gpg --keyserver hkps://keys.openpgp.org --recv-keys 8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600
# gpg --keyserver hkps://keys.openpgp.org --recv-keys C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8
# gpg --keyserver hkps://keys.openpgp.org --recv-keys 890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4
# gpg --keyserver hkps://keys.openpgp.org --recv-keys C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C
# gpg --keyserver hkps://keys.openpgp.org --recv-keys 108F52B48DB57BB0CC439B2997B01419BD92F80A
# gpg --keyserver hkps://keys.openpgp.org --recv-keys A363A499291CBBC940DD62E41F10027AF002F8B0
$gpg = "$($TargetPath)\git\usr\bin\gpg.exe"

function  Update-NodeJs {

    param (
        $NodeMajorVersion
    )

    $TargetDir = "$($TargetPath)\node\$($NodeMajorVersion)"
    $BackupDir = "$($TargetDir).bak"

    Write-Output "check updates for: node-V$($NodeMajorVersion)"

    $RemoteLatestTag = "$(git ls-remote --tags "https://github.com/nodejs/node.git" `
                            | Select-String -Pattern "{}" -NotMatch `
                            | Select-String -Pattern "v$($NodeMajorVersion)" -SimpleMatch `
                            | Sort-Object -erroraction 'SilentlyContinue' { [System.version]($_ -split 'v')[1] } `
                            | Select-Object -Last 1
                        )".Trim().Split("/")[2].Replace("v", "")

    try {
        $CurrentVersion = (& "$($TargetDir)\node.exe" --version).Trim().Replace("v", "")
    }
    catch {
        $CurrentVersion = "0.0.0"
        # create new empty dir as backup fallback
        New-Item -Path "$($TargetPath)" -Name "node" -ItemType "directory" -ErrorAction SilentlyContinue > nul
        New-Item -Path "$($TargetPath)\node" -Name "$($NodeMajorVersion)" -ItemType "directory" -ErrorAction SilentlyContinue > nul
    }

    # Write-Output "remote: >$($RemoteLatestTag)<"
    # Write-Output "local : >$($CurrentVersion)<"

    if ( [System.Version]$($RemoteLatestTag) -gt [System.Version]$($CurrentVersion) ) {
        Write-Output "update needed to: $($RemoteLatestTag)"

            $TargetFileName = "node-v$($RemoteLatestTag)-win-x64.7z"
            $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"

            $Url ="https://nodejs.org/dist/v$($RemoteLatestTag)"
            try {
                if ( -not (Test-Path -Path $DownloadFullPath)  ) {
                    $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
                    Write-Output "download"
                    Invoke-WebRequest -Uri "$($Url)/$($TargetFileName)" -OutFile $DownloadFullPath
                    $ProgressPreference = 'Continue'
                }

                $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
                Invoke-WebRequest -Uri "$($Url)/SHASUMS256.txt.asc" -OutFile "$($env:TEMP)\SHASUMS256.txt.asc"
                $ProgressPreference = 'Continue'

                Write-Output "check signature" `
                && & $gpg --verify "$($env:TEMP)\SHASUMS256.txt.asc"  >nul 2>&1 `
                || exit 1


                $ShaSum = (Select-String -Path "$($env:TEMP)\SHASUMS256.txt.asc" -Pattern "(.*)\s+$($TargetFileName)").Matches.Groups[1].Value.Trim()
                # Write-Output $ShaSum

        #         # && Start-MpScan -ScanPath $DownloadFullPath -ScanType CustomScan `
                if ((Get-FileHash $DownloadFullPath -Algorithm SHA256).Hash.ToLower() -eq "$($ShaSum)") {
                    # Write-Output "ok"
                    Move-Item $TargetDir $BackupDir `
                        && Write-Output "check malware" `
                        && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
                        && Write-Output "extract" `
                        && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir).new" > nul `
                        && Move-Item "$($TargetDir).new\*" $TargetDir `
                        && Write-Output "cleanup" `
                        && Remove-Item -Path $DownloadFullPath -Force `
                        && Remove-Item -Path "$($TargetDir).new" -Recurse -Force `
                        && Remove-Item -Path "$($env:TEMP)\SHASUMS256.txt.asc" -Force `
                        && Remove-Item -Path $BackupDir -Recurse -Force `
                        && Write-Output "updated to version: $($RemoteLatestTag)" `
                    || Move-Item $BackupDir $TargetDir
                }
            } catch {
                Write-Output "Something goes wrong by download of file: $($TargetFileName)!"
            }
    } else {
        Write-Output "Nothing to update."
    }
}

foreach ($MajorVersion in $args) {
    Update-NodeJs $MajorVersion
}
