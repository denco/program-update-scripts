# Download and verification functions for tool updater

function Get-ExpectedChecksum {
    param (
        [PSCustomObject] $ChecksumDef,
        [hashtable] $Variables,
        [string] $TargetFileName
    )
    if (-not $ChecksumDef -or $ChecksumDef.algorithm -eq "none") { return $null }

    $url = Resolve-Template $ChecksumDef.urlTemplate $Variables
    $ProgressPreference = 'SilentlyContinue'

    switch ($ChecksumDef.source) {
        "sidecar-file" {
            $resp = (Invoke-WebRequest -Uri $url).Content
            $raw = if ($resp -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($resp) } else { "$resp" }
            return ($raw.Trim() -split '\s+')[0].ToLower()
        }

        "digest-file" {
            $resp = (Invoke-WebRequest -Uri $url).Content
            $raw = if ($resp -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($resp) } else { "$resp" }
            return ($raw.Trim() -split '\s+')[0].ToLower()
        }

        "checksums-file" {
            $resp = (Invoke-WebRequest -Uri $url).Content
            $raw = if ($resp -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($resp) } else { "$resp" }
            $lines = $raw.Split("`n") | Select-String -Pattern ([regex]::Escape($TargetFileName))
            if ($lines) {
                return ("$($lines | Select-Object -Last 1)".Trim() -split '\s+')[0].ToLower()
            }
        }

        "manifest-yaml" {
            $resp = (Invoke-WebRequest -Uri $url).Content
            $raw = if ($resp -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($resp) } else { "$resp" }
            $match = $raw | Select-String -Pattern 'sha512:\s*(\S+)'
            if ($match) {
                $base64 = $match.Matches[0].Groups[1].Value.Trim()
                return [System.BitConverter]::ToString([System.Convert]::FromBase64String($base64)).Replace("-", "").ToLower()
            }
        }

        "html-scrape" {
            $resp = (Invoke-WebRequest -Uri $url).Content
            if ($Variables['id'] -eq "bruno") {
                $line = ($resp.Split("`n") | Select-String -Pattern "$TargetFileName" -SimpleMatch | Select-Object -Last 1)
                if ("$line" -match 'sha256:([a-fA-F0-9]{64})') { return $Matches[1].ToLower() }
            } elseif ($Variables['id'] -eq "git") {
                $line = ($resp.Split("`n") | Select-String -Pattern ([regex]::Escape($TargetFileName)) -Context 0, 1)
                $clean = "$line" -replace "</?td>|\r|\n|\f", "" -replace "\B\s+|>|<", ""
                $parts = $clean -split '\s+'
                if ($parts.Length -gt 1) { return $parts[1].ToLower() }
            } elseif ($Variables['id'] -eq "python") {
                $row = ($resp.Split('<tr') | Select-String -Pattern $TargetFileName -AllMatches)
                if ($row) {
                    $cells = ("$row".Split('td')[-2].Split('>')[3, 4, 7, 8]).Split('<')[0, 2, 4, 6]
                    return (-join $cells).ToLower()
                }
            }
        }

        "json-api" {
            $resp = (Invoke-WebRequest -Uri $url).Content
            if ($Variables['id'] -eq "vscode") {
                if ("$resp" -match '"sha"\s*:\s*"([a-fA-F0-9]{64})"') { return $Matches[1].ToLower() }
            } elseif ($Variables['id'] -eq "7-zip" -or $Variables['id'] -eq "seven_zip") {
                $line = ($resp.Split("`n") | Select-String -Pattern "net.sf.files" -SimpleMatch)
                if ($line) {
                    $jsonText = "$line".Split("=")[1].Replace(";", "") | ConvertFrom-Json
                    if ($jsonText.$TargetFileName.sha1) { return $jsonText.$TargetFileName.sha1.ToLower() }
                }
            }
        }
    }
    $ProgressPreference = 'Continue'
    return $null
}

function Invoke-ToolDownload {
    param (
        [PSCustomObject] $ToolDef,
        [hashtable] $Variables
    )
    $targetFileName = Resolve-Template $ToolDef.download.fileNameTemplate $Variables
    $Variables['fileName'] = $targetFileName

    $downloadUrl = Resolve-Template $ToolDef.download.urlTemplate $Variables
    $downloadFullPath = Join-Path $env:TEMP $targetFileName

    # Kill blocking process if requested
    if ($ToolDef.target.preUpdateKillProcess) {
        $rawName = $ToolDef.target.preUpdateKillProcess
        $noExtName = ($rawName -replace '\.(exe|bin)$', '')
        Get-Process -Name $rawName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if ($noExtName -ne $rawName) {
            Get-Process -Name $noExtName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        if (-not (Test-Path -Path $downloadFullPath)) {
            Write-Host "  Downloading: $downloadUrl ..."
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadFullPath
            $ProgressPreference = 'Continue'
        }
        return $downloadFullPath
    } catch {
        Write-Error "Failed to download $downloadUrl : $_"
        return $null
    }
}

function Test-ToolVerification {
    param (
        [PSCustomObject] $ToolDef,
        [hashtable] $Variables,
        [string] $DownloadFullPath,
        [string] $RemoteVersion,
        [string] $GpgPath,
        [string] $VScannerPath
    )

    $targetFileName = $Variables['fileName']

    # 1. Verification: Checksum
    if ($ToolDef.verification.checksum -and $ToolDef.verification.checksum.algorithm -ne "none") {
        Write-Host "  Verifying checksum ($($ToolDef.verification.checksum.algorithm)) ..."
        $expectedHash = Get-ExpectedChecksum -ChecksumDef $ToolDef.verification.checksum -Variables $Variables -TargetFileName $targetFileName
        if ($expectedHash) {
            $algo = $ToolDef.verification.checksum.algorithm.ToUpper()
            $actualHash = (Get-FileHash -Path $DownloadFullPath -Algorithm $algo).Hash.ToLower()
            if ($actualHash -ne $expectedHash.ToLower()) {
                Write-Error "Checksum mismatch! Expected: $expectedHash, got: $actualHash"
                Remove-Item -Path $DownloadFullPath -Force -ErrorAction SilentlyContinue
                return $false
            }
            Write-Host "  Checksum: Verified OK" -ForegroundColor Green
        } else {
            Write-Warning "Could not retrieve expected checksum, skipping checksum check."
        }
    }

    # 2. Verification: Signature (GPG / Cosign)
    if ($ToolDef.verification.signatures) {
        foreach ($sig in $ToolDef.verification.signatures) {
            if ($sig.versionCondition -and -not (Test-VersionCondition -Condition $sig.versionCondition -Version $RemoteVersion)) {
                continue
            }
            $sigUrl = Resolve-Template $sig.urlTemplate $Variables
            $isNodeJs = ($ToolDef.id -eq "nodejs" -or $Variables['id'] -eq "nodejs")
            if ($isNodeJs) {
                $sigFileName = Split-Path -Path $sigUrl -Leaf
                $downloadDir = [System.IO.Path]::GetDirectoryName($DownloadFullPath)
                $sigPath = Join-Path $downloadDir $sigFileName
            } else {
                $sigExt = [System.IO.Path]::GetExtension($sigUrl)
                $sigPath = "$DownloadFullPath$sigExt"
            }

            Write-Host "  Verifying signature ($($sig.type)) ..."
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $sigUrl -OutFile $sigPath -ErrorAction SilentlyContinue
            $ProgressPreference = 'Continue'

            if (Test-Path -Path $sigPath) {
                if ($sig.type -eq "gpg" -and (Test-Path -Path $GpgPath)) {
                    if ($isNodeJs) {
                        & $GpgPath --verify $sigPath 2>&1 | Out-Null
                    } else {
                        & $GpgPath --verify $sigPath $DownloadFullPath 2>&1 | Out-Null
                    }
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "GPG signature verification failed!"
                        Remove-Item -Path $DownloadFullPath -Force -ErrorAction SilentlyContinue
                        Remove-Item -Path $sigPath -Force -ErrorAction SilentlyContinue
                        return $false
                    }
                    Write-Host "  GPG signature: Verified OK" -ForegroundColor Green
                } elseif ($sig.type -eq "cosign") {
                    $cosignCmd = Get-Command "cosign.exe" -ErrorAction SilentlyContinue
                    if ($cosignCmd) {
                        & $cosignCmd.Source verify-blob $DownloadFullPath `
                            --bundle $sigPath `
                            --cert-identity $sig.cosignCertIdentity `
                            --certificate-oidc-issuer $sig.cosignOidcIssuer 2>&1 | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            Write-Error "Cosign verification failed!"
                            return $false
                        }
                        Write-Host "  Cosign signature: Verified OK" -ForegroundColor Green
                    }
                }
                Remove-Item -Path $sigPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # 3. Verification: Antivirus Scan
    $malwareScanEnabled = if ($ToolDef.verification -and $null -ne $ToolDef.verification.malwareScan) { [bool]$ToolDef.verification.malwareScan } else { $true }
    if ($malwareScanEnabled -and (Test-Path -Path $VScannerPath)) {
        Write-Host "  Scanning for malware (Windows Defender) ..."
        & $VScannerPath -Scan -ScanType 3 -File $DownloadFullPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Malware scan failed or threat detected!"
            return $false
        }
    }

    return $true
}
