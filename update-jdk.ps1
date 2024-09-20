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

# gpg
# gpg --receive-keys 3B04D753C9050D9A5D343F39843C48A565F8F04B
$gpg  = "$($TargetPath)\git\usr\bin\gpg.exe"

function  Update-Jdk {

    param (
        $JdkMajorVersion
    )

    $TargetDir = "$($TargetPath)\jdk\$($JdkMajorVersion)"
    $BackupDir = "$($TargetDir).bak"

    Write-Output "check updates for: jdk$($JdkMajorVersion)"

    $RemoteLatestTag = "$(git ls-remote --tags "https://github.com/adoptium/temurin$($JdkMajorVersion)-binaries.git" `
                            | Select-String -Pattern "jdk8u|-beta" -NotMatch `
                            | Sort-Object -erroraction 'SilentlyContinue' { [System.version]($_ -split '-')[3] } `
                            | Select-Object -Last 1
                        )".Trim().Split('/')[2].Split('-')[1]

    $JavaBinDir = "$($TargetDir)\bin"

    $CurrentVersion = "0.0.0"
    if ( Test-Path -Path $JavaBinDir ) {
        $CurrentVersion = (Convertfrom-Stringdata (get-content "$($TargetDir)\release" -raw))."SEMANTIC_VERSION".Replace('"', '')
    } else {
        # create new empty dir as backup fallback
        New-Item -Path "$($TargetPath)" -Name "jdk" -ItemType "directory" -ErrorAction SilentlyContinue
        New-Item -Path "$($TargetPath)\jdk" -Name "$($JdkMajorVersion)" -ItemType "directory" -ErrorAction SilentlyContinue
    }

    $RemoteVersion = "$(($RemoteLatestTag -replace '\+.+$', '').Replace("+", ".")).0.0" -replace '^(\d+\.\d+\.\d+).+$', '$1'
    $LocalVersion = "$(($CurrentVersion -replace '\+.+$', '').Replace("+", ".")).0.0" -replace '^(\d+\.\d+\.\d+).+$', '$1'

    if ( [System.Version]$($RemoteVersion) -gt [System.Version]$($LocalVersion) ) {
        Write-Output "update needed to: $($RemoteLatestTag)"

        $TargetFileName = "OpenJDK$($JdkMajorVersion)U-jdk_x64_windows_hotspot_$($RemoteLatestTag -replace '\+(\d)?\.?\d?', '_$1').zip"
        $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"

        $Url ="https://github.com/adoptium/temurin$($JdkMajorVersion)-binaries/releases/download/jdk-$($RemoteLatestTag)/$($TargetFileName)"

        try {
            # download check sum
            $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
            $Sha256Sum = [System.Text.Encoding]::UTF8.GetString((Invoke-WebRequest -Uri "$($Url).sha256.txt").Content).Split(" ")[0]
            $ProgressPreference = 'Continue'

            # download package file
            if ( -not (Test-Path -Path $DownloadFullPath)  ) {
                $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
                Write-Output "download"
                Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
                $ProgressPreference = 'Continue'
            }

            # download signature
            $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
            Invoke-WebRequest -Uri "$($Url).sig" -OutFile "$($DownloadFullPath).sig"
            $ProgressPreference = 'Continue'
        } catch {
            Write-Output "Something goes wrong by download of file: $($TargetFileName)!"
        }

            # && Start-MpScan -ScanPath $DownloadFullPath -ScanType CustomScan `
            if ((Get-FileHash $DownloadFullPath).Hash.ToLower() -eq "$($Sha256Sum)") {
                # Write-Output "ok"
                Move-Item $TargetDir $BackupDir `
                    && Write-Output "check signature" `
                    && & $gpg --verify "$($DownloadFullPath).sig" $DownloadFullPath >nul 2>&1 `
                    && Write-Output "check malware" `
                    && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
                    && Write-Output "extract" `
                    && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir).new" -y > nul `
                    && Move-Item "$($TargetDir).new\jdk-$($RemoteLatestTag -replace '\+(\d)?\.?\d?', '+$1')" $TargetDir `
                    && Write-Output "cleanup" `
                    && Remove-Item -Path $DownloadFullPath -Force `
                    && Remove-Item -Path "$($DownloadFullPath).sig" -Force `
                    && Remove-Item -Path "$($TargetDir).new" -Force `
                    && Remove-Item -Path $BackupDir -Recurse -Force `
                    && Write-Output "updated to version: $($RemoteLatestTag)" `
                || Move-Item $BackupDir $TargetDir
            }
    } else {
        Write-Output "Nothing to update."
    }
}

foreach($MajorVersion in $args) {
    Update-Jdk $MajorVersion
}
