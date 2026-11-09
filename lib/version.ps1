# Version checking functions for tool updater

function Get-RemoteVersion {
    param (
        [PSCustomObject] $ToolDef,
        [hashtable] $Variables
    )
    $remote = $ToolDef.version.remote

    switch ($remote.source) {
        "git-ls-remote" {
            $repoUrl = Resolve-Template $remote.repositoryUrl $Variables
            $tagsRaw = git ls-remote --tags "$repoUrl" 2>$null

            if ($remote.excludePattern) {
                $tagsRaw = $tagsRaw | Select-String -Pattern $remote.excludePattern -NotMatch
            }
            if ($remote.matchPattern) {
                $pattern = Resolve-Template $remote.matchPattern $Variables
                $tagsRaw = $tagsRaw | Select-String -Pattern $pattern
            }

            $extracted = @()
            $regex = if ($remote.tagVersionExtractRegex) { $remote.tagVersionExtractRegex } else { 'refs/tags/v?(\d+(?:\.\d+)*)' }

            foreach ($line in $tagsRaw) {
                $lineStr = "$line"
                if ($lineStr -match $regex) {
                    $extracted += [PSCustomObject]@{
                        RawTag  = $Matches[0]
                        Version = $Matches[1]
                        SemVer  = Get-SemVer $Matches[1]
                    }
                }
            }

            if ($extracted.Count -eq 0) { return $null }

            $latest = $extracted | Sort-Object SemVer | Select-Object -Last 1
            $resultVersion = $latest.Version

            # Secondary stable check (e.g. VS Code productVersion)
            if ($remote.secondaryStableCheck) {
                try {
                    $sec = $remote.secondaryStableCheck
                    $ProgressPreference = 'SilentlyContinue'
                    $secContent = (Invoke-WebRequest -Uri $sec.url).Content
                    $ProgressPreference = 'Continue'
                    if ($sec.jsonPath -eq "productVersion") {
                        if ($secContent -match '"productVersion"\s*:\s*"([^"]+)"') {
                            $stableVer = $Matches[1]
                            if ($stableVer -ne $resultVersion) {
                                Write-Verbose "Remote tag ($resultVersion) differs from stable build ($stableVer); using stable build version."
                                $resultVersion = $stableVer
                            }
                        }
                    }
                } catch {
                    Write-Verbose "Secondary check failed, using git tag version: $_"
                }
            }

            return $resultVersion
        }

        "http-scrape" {
            $url = Resolve-Template $remote.url $Variables
            $ProgressPreference = 'SilentlyContinue'
            $content = (Invoke-WebRequest -Uri $url).Content
            $ProgressPreference = 'Continue'

            if ($ToolDef.id -eq "libreoffice") {
                $versions = [System.Collections.Generic.List[string]]::new()
                foreach ($m in [regex]::Matches($content, 'href=["'']?(\d+\.\d+\.\d+)/?["'']?')) {
                    $val = $m.Groups[1].Value
                    if (-not $versions.Contains($val)) {
                        $versions.Add($val)
                    }
                }
                if ($versions.Count -gt 0) {
                    $sorted = $versions | Sort-Object { Get-SemVer $_ }
                    return ($sorted | Select-Object -Last 1)
                }
            } elseif ($ToolDef.id -eq "7-zip" -or $ToolDef.id -eq "seven_zip") {
                $folder = ($content.Split("`n") | Select-String -Pattern 'class="folder"' -SimpleMatch | Select-Object -First 1)
                if ("$folder" -match '7-Zip/(\d+\.\d+)/') {
                    return $Matches[1]
                }
            } elseif ($ToolDef.id -eq "yed") {
                if ($content -match 'Download yEd\s+([\d\.]+)') {
                    return $Matches[1]
                }
            }
            return $null
        }

        default {
            Write-Error "Unsupported remote source: $($remote.source)"
            return $null
        }
    }
}

function Get-LocalVersion {
    param (
        [PSCustomObject] $ToolDef,
        [string] $TargetDir,
        [string] $TargetFile,
        [hashtable] $Variables
    )
    $local = $ToolDef.version.local
    $current = "0.0.0"
    $updateNotBefore = -1
    $postponedVersion = $null

    switch ($local.source) {
        "version-file" {
            $fName = if ($local.fileName) { $local.fileName } else { "VERSION" }
            $verFile = Join-Path $TargetDir $fName
            if (Test-Path -Path $verFile) {
                $lines = @(Get-Content -Path $verFile)
                if ($lines.Count -ge 1) { $current = $lines[0].Trim() }
                if ($lines.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($lines[1])) { $updateNotBefore = [int64]($lines[1].Trim()) }
                if ($lines.Count -ge 3) { $postponedVersion = $lines[2].Trim() }
            }
        }

        "metadata-file" {
            $metaPath = Join-Path $TargetDir $local.fileName
            if (Test-Path -Path $metaPath) {
                $content = Get-Content -Path $metaPath -Raw
                if ($local.fileName -eq ".eclipseproduct") {
                    $dict = ConvertFrom-StringData $content
                    if ($dict[$local.propertyKey]) { $current = $dict[$local.propertyKey] }
                } elseif ($local.fileName -eq "release") {
                    $dict = ConvertFrom-StringData $content
                    if ($dict[$local.propertyKey]) { $current = $dict[$local.propertyKey].Replace('"', '') }
                } elseif ($local.fileName -match 'netbeans\.conf') {
                    $match = $content | Select-String -Pattern 'netbeans_default_userdir="?\${DEFAULT_USERDIR_ROOT}/(\d+)'
                    if ($match) { $current = $match.Matches[0].Groups[1].Value }
                }
            }
        }

        "executable-version" {
            $cmd = Resolve-Template $local.command $Variables
            try {
                $cmdOutput = & cmd /c "$cmd" 2>&1 | Out-String
                $regex = if ($local.extractRegex) { $local.extractRegex } else { '(\d+(?:\.\d+)+)' }
                if ($cmdOutput -match $regex) {
                    $current = $Matches[1]
                }
            } catch {
                $current = "0.0.0"
            }
        }
    }

    return @{
        Version          = $current
        UpdateNotBefore  = $updateNotBefore
        PostponedVersion = $postponedVersion
    }
}

function Test-UpdateDelay {
    param (
        [PSCustomObject] $ToolDef,
        [string] $LocalVersion,
        [string] $RemoteVersion,
        [hashtable] $LocalInfo,
        [string] $TargetDir,
        [switch] $Force
    )
    $delayDays = if ($ToolDef.updateDelayDays) { [int]$ToolDef.updateDelayDays } else { 0 }
    if ($delayDays -le 0 -or $Force) { return $false }

    $updateNotBefore = $LocalInfo.UpdateNotBefore
    $postponedVersion = $LocalInfo.PostponedVersion
    $remoteSemVer = Get-SemVer $RemoteVersion
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    if ($updateNotBefore -eq -1) {
        $notBefore = $now + (24 * 3600 * $delayDays)
        $dateStr = [DateTimeOffset]::FromUnixTimeSeconds($notBefore).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss")
        Write-Host "  Update will be delayed until: $dateStr" -ForegroundColor Yellow
        if (Test-Path -Path $TargetDir) {
            Set-Content -Path (Join-Path $TargetDir "VERSION") -Value "$LocalVersion`r`n$notBefore`r`n$RemoteVersion"
        }
        return $true
    }
    elseif ($RemoteVersion -eq $postponedVersion -and $now -lt $updateNotBefore) {
        $dateStr = [DateTimeOffset]::FromUnixTimeSeconds($updateNotBefore).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss")
        Write-Host "  Update to $RemoteVersion is delayed until: $dateStr" -ForegroundColor Yellow
        return $true
    }
    elseif ($remoteSemVer -gt (Get-SemVer $postponedVersion) -and $now -lt $updateNotBefore) {
        $notBefore = $now + (24 * 3600 * $delayDays)
        $dateStr = [DateTimeOffset]::FromUnixTimeSeconds($notBefore).UtcDateTime.ToString("yyyy-MM-dd HH:mm:ss")
        Write-Host "  Newer version $RemoteVersion detected, postponing until: $dateStr" -ForegroundColor Yellow
        if (Test-Path -Path $TargetDir) {
            Set-Content -Path (Join-Path $TargetDir "VERSION") -Value "$LocalVersion`r`n$notBefore`r`n$RemoteVersion"
        }
        return $true
    }

    return $false
}
