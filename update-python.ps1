# [CmdletBinding()]
[cultureinfo]::CurrentUICulture='en-US'

$TargetPath = "$($env:LOCALAPPDATA)\Programs"

$vScanner = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"

# gpg
# gpg --recv-key FC624643487034E5

$gpg = "$($TargetPath)\git\usr\bin\gpg.exe"


function  Update-Python {

    param (
        $PythonVersion
    )

    $TargetDir = "$($TargetPath)\python\$($PythonVersion)"
    $BackupDir = "$($TargetDir).bak"

    Write-Output "check updates for: python-$($PythonVersion)"

    $RemoteLatestTag = "$(git ls-remote --tags "https://github.com/python/cpython.git" `
                            | Select-String -Pattern "\{\}" -NotMatch `
                            | Select-String -Pattern "v$($PythonVersion)" -SimpleMatch `
                            | Sort-Object -erroraction 'SilentlyContinue' { [System.version]($_ -split 'v')[1] } `
                            | Select-Object -Last 1
                        )".Trim().Split('v')[1]

    try {
        $CurrentVersion = (& "$($TargetDir)\python.exe" --version).Split(' ')[1].Trim().Replace("v", "")
    }
    catch {
        $CurrentVersion = "0.0.0"
        # create new empty dir as backup fallback
        New-Item -Path "$($TargetPath)" -Name "Python" -ItemType "directory" -ErrorAction SilentlyContinue > nul
        New-Item -Path "$($TargetPath)\python" -Name "$($PythonVersion)" -ItemType "directory" -ErrorAction SilentlyContinue > nul
    }

    # Write-Output "remote: >$($RemoteLatestTag)<"
    # Write-Output "local : >$($CurrentVersion)<"

    if ( [System.Version]$($RemoteLatestTag) -gt [System.Version]$($CurrentVersion) ) {
        Write-Output "update needed to: $($RemoteLatestTag)"

        # https://www.python.org/ftp/python/3.11.8/python-3.11.8-amd64.exe
        $TargetFileName = "python-$($RemoteLatestTag)-amd64.exe"
        $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"

        $Url ="https://www.python.org/ftp/python/$($RemoteLatestTag)"
        # try {
            if ( -not (Test-Path -Path $DownloadFullPath)  ) {
                $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
                Write-Output "download"
                Invoke-WebRequest -Uri "$($Url)/$($TargetFileName)" -OutFile $DownloadFullPath
                $ProgressPreference = 'Continue'
            }

            if ([System.Version]$($RemoteLatestTag) -lt [System.Version]'3.14' ) {
                $SignatureFileExtension="asc"
            } else {
                $SignatureFileExtension="sigstore"
            }

            # get signature
            $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
            Invoke-WebRequest -Uri "$($Url)/$($TargetFileName).$($SignatureFileExtension)" -OutFile "$($DownloadFullPath).$($SignatureFileExtension)"
            $ProgressPreference = 'Continue'

            if ([System.Version]$($RemoteLatestTag) -lt [System.Version]'3.14' ) {
                Write-Output "check gpg signature" `
                && & $gpg --verify "$($DownloadFullPath).$($SignatureFileExtension)"  >nul 2>&1 `
                || Invoke-command -ScriptBlock {exit 1}
                # || exit 1
            } else {
                Write-Output "check cosign signature"
                cosign verify-blob "$($DownloadFullPath)" `
                    --bundle "$($DownloadFullPath).$($SignatureFileExtension)" `
                    --cert-identity hugo@python.org `
                    --certificate-oidc-issuer https://github.com/login/oauth `
                || Invoke-command -ScriptBlock {exit 1}
            }

            $checkSum =  ("$((Invoke-WebRequest -Uri "https://www.python.org/downloads/release/python-$($RemoteLatestTag.Replace('.',''))/").Content.Split('<tr') `
                            |Select-String -Pattern "https://www.python.org/ftp/python/$($RemoteLatestTag)/$($TargetFileName)" -AllMatches)".Split('td')[-2].Split('>')[3,4,7,8]).Split('<')[0,2,4,6]
            $checkSum = -join $checkSum

            # Write-Output "$($TargetFileName) checkSum: $($checkSum)"
            if ((Get-FileHash $DownloadFullPath -Algorithm SHA256).Hash.ToLower() -eq "$($checkSum)") {
                Write-Output "ok"
                Rename-Item $TargetDir $BackupDir `
                    && Write-Output "check malware" `
                    && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
                    && Write-Output "extract" `
                    && Start-Process $DownloadFullPath -ArgumentList "/repair","/quiet","DefaultJustForMeTargetDir=$($TargetDir)","InstallAllUsers=0","CompileAll=1","Shortcuts=0","Include_doc=1","AssociateFiles=0","AppendPath=0","Include_launcher=0","InstallLauncherAllUsers=0" -NoNewWindow -Wait `
                    && Write-Output "cleanup" `
                    && Remove-Item -Path $DownloadFullPath -Force `
                    && Remove-Item -Path "$($DownloadFullPath).$($SignatureFileExtension)" -Recurse -Force `
                    && Remove-Item -Path "$($env:TEMP)\Python $($RemoteLatestTag)*.log" -Force `
                    && Remove-Item -Path $BackupDir -Recurse -Force `
                    && Write-Output "updated to version: $($RemoteLatestTag)" `
                || Rename-Item $BackupDir $TargetDir
            }
        # } catch {
            # Write-Output "Something goes wrong by download of file: $($TargetFileName), Url: $($Url)/$($TargetFileName) !"
        # }
    } else {
        Write-Output "Nothing to update."
    }
}

foreach ($MajorVersion in $args) {
    Update-Python $MajorVersion
}
