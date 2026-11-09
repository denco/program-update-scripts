# Extraction, installation, and rollback functions for tool updater

function Install-ToolArtifact {
    param (
        [PSCustomObject] $ToolDef,
        [hashtable] $Variables,
        [string] $DownloadFullPath,
        [string] $RemoteVersion,
        [string] $TargetDir,
        [string] $TargetFile,
        [string] $BackupDir,
        [string] $BackupFile,
        [string] $BaseInstallPath,
        [string] $BinDirectory,
        [string] $SevenZipPath
    )

    $isBinary = ($ToolDef.target.type -eq "binary")
    $name = $ToolDef.name

    Write-Host "  Installing ..."
    $oldPwd = Get-Location
    $stagingDir = if (-not $isBinary) { "$TargetDir.new" } else { $null }

    try {
        if ($isBinary) {
            if (-not (Test-Path -Path $BinDirectory)) {
                New-Item -Path $BinDirectory -ItemType Directory -Force | Out-Null
            }
            if (Test-Path -Path $TargetFile) {
                Move-Item -Path $TargetFile -Destination $BackupFile -Force
            }

            # Extract binary
            & $SevenZipPath x "$DownloadFullPath" "$($ToolDef.target.binaryName)" -y -o"$BinDirectory" | Out-Null
            if (-not (Test-Path -Path $TargetFile)) {
                throw "Extraction failed to produce $TargetFile"
            }

        } else {
            # Directory installation
            if (-not (Test-Path -Path $BaseInstallPath)) {
                New-Item -Path $BaseInstallPath -ItemType Directory -Force | Out-Null
            }
            if (Test-Path -Path $TargetDir) {
                if (Test-Path -Path $BackupDir) { Remove-Item -Path $BackupDir -Recurse -Force }
                Rename-Item -Path $TargetDir -NewName (Split-Path $BackupDir -Leaf) -Force
            }

            if (Test-Path -Path $stagingDir) { Remove-Item -Path $stagingDir -Recurse -Force }

            switch ($ToolDef.extraction.method) {
                "direct-7z" {
                    & $SevenZipPath x "$DownloadFullPath" -o"$TargetDir" -y | Out-Null
                }

                "subfolder-move" {
                    & $SevenZipPath x "$DownloadFullPath" -o"$stagingDir" -y | Out-Null
                    $sub = $ToolDef.extraction.sourceSubfolder
                    $sourcePath = Join-Path $stagingDir $sub
                    $matchedDirs = Get-Item -Path $sourcePath -ErrorAction SilentlyContinue
                    if (-not $matchedDirs) {
                        $leaf = Split-Path $sub -Leaf
                        $matchedDirs = Get-ChildItem -Path $stagingDir -Filter $leaf -Recurse -Directory -ErrorAction SilentlyContinue
                    }
                    if ($matchedDirs) {
                        if (-not (Test-Path -Path $TargetDir)) {
                            New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
                        }
                        Get-ChildItem -Path $matchedDirs[0].FullName | Move-Item -Destination $TargetDir -Force
                    } else {
                        throw "Could not find subfolder matching '$sub' in extracted archive"
                    }
                }

                "nested-7z" {
                    & $SevenZipPath x "$DownloadFullPath" -o"$stagingDir" -y | Out-Null
                    $nested = Join-Path $stagingDir $ToolDef.extraction.nestedArchivePath
                    if (Test-Path -Path $nested) {
                        & $SevenZipPath x "$nested" -o"$TargetDir" -y | Out-Null
                    } else {
                        throw "Nested archive not found at $nested"
                    }
                }

                "msi-admin" {
                    if (-not (Test-Path -Path $stagingDir)) {
                        New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null
                    }

                    $msiArgs = @("/a", "`"$DownloadFullPath`"", "/qn", "TARGETDIR=`"$stagingDir`"")
                    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -NoNewWindow -Wait -PassThru
                    if ($proc.ExitCode -ne 0) {
                        throw "msiexec /a administrative extraction failed with exit code $($proc.ExitCode)"
                    }

                    if ($ToolDef.id -eq "libreoffice" -or [string]::IsNullOrWhiteSpace($ToolDef.extraction.sourceSubfolder)) {
                        # After extraction is successfully finished, rename whole new directory to proper target directory
                        if (Test-Path -Path $TargetDir) { Remove-Item -Path $TargetDir -Recurse -Force }
                        Rename-Item -Path $stagingDir -NewName (Split-Path $TargetDir -Leaf) -Force
                    } else {
                        # Search for extracted application folder
                        $sub = $ToolDef.extraction.sourceSubfolder
                        $matched = $null

                        if ($sub) {
                            $directPath = Join-Path $stagingDir $sub
                            if (Test-Path -Path $directPath -PathType Container) {
                                $matched = @(Get-Item -Path $directPath)
                            } else {
                                $cleanPattern = (Split-Path $sub -Leaf).Trim('*')
                                $found = Get-ChildItem -Path $stagingDir -Recurse -Directory -ErrorAction SilentlyContinue |
                                    Where-Object { $_.Name -like "*$cleanPattern*" } |
                                    Select-Object -First 1
                                if ($found) { $matched = @($found) }
                            }
                        }

                        if ($matched) {
                            if (-not (Test-Path -Path $TargetDir)) {
                                New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
                            }
                            Get-ChildItem -Path $matched[0].FullName | Move-Item -Destination $TargetDir -Force
                        } else {
                            if (Test-Path -Path $TargetDir) { Remove-Item -Path $TargetDir -Recurse -Force }
                            Rename-Item -Path $stagingDir -NewName (Split-Path $TargetDir -Leaf) -Force
                        }

                        if (Test-Path -Path $stagingDir) {
                            Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                "installer-silent" {
                    $argsList = foreach ($a in $ToolDef.extraction.installerArgs) {
                        Resolve-Template $a $Variables
                    }
                    Start-Process -FilePath $DownloadFullPath -ArgumentList $argsList -NoNewWindow -Wait
                }
            }

            # Verify that target directory is populated
            $targetItems = Get-ChildItem -Path $TargetDir -ErrorAction SilentlyContinue
            if (-not $targetItems -or $targetItems.Count -eq 0) {
                throw "Installation failed: target directory '$TargetDir' is empty after extraction"
            }

            # Preserve directories/files from .bak
            if ($ToolDef.target.preserve -and (Test-Path -Path $BackupDir)) {
                foreach ($item in $ToolDef.target.preserve) {
                    $bakItem = Join-Path $BackupDir $item
                    if (Test-Path -Path $bakItem) {
                        Write-Host "  Preserving user data: $item"
                        Copy-Item -Path $bakItem -Destination (Join-Path $TargetDir $item) -Recurse -Force
                    }
                }
            }

            # Renames
            if ($ToolDef.target.renames) {
                foreach ($r in $ToolDef.target.renames) {
                    $src = Join-Path $TargetDir $r.source
                    $dst = Join-Path $TargetDir $r.destination
                    Get-Item -Path $src -ErrorAction SilentlyContinue | ForEach-Object {
                        Move-Item -Path $_.FullName -Destination $dst -Force
                    }
                }
            }

            # Cleanups
            if ($ToolDef.target.cleanups) {
                foreach ($c in $ToolDef.target.cleanups) {
                    $cleanPath = Join-Path $TargetDir $c
                    if (Test-Path -Path $cleanPath) {
                        Remove-Item -Path $cleanPath -Recurse -Force
                    }
                }
            }

            # Write VERSION file
            Set-Content -Path (Join-Path $TargetDir "VERSION") -Value $RemoteVersion
        }

        # Remove staging and backup only after all steps completed successfully
        if ($stagingDir -and (Test-Path -Path $stagingDir)) { Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue }
        if ($isBinary -and (Test-Path -Path $BackupFile)) { Remove-Item -Path $BackupFile -Force -ErrorAction SilentlyContinue }
        if (-not $isBinary -and (Test-Path -Path $BackupDir)) { Remove-Item -Path $BackupDir -Recurse -Force -ErrorAction SilentlyContinue }

        # Cleanup download
        Remove-Item -Path $DownloadFullPath -Force -ErrorAction SilentlyContinue

        Write-Host "  Successfully updated $name to version: $RemoteVersion" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Installation failed: $_"
        Set-Location $oldPwd
        # Rollback
        if ($isBinary -and (Test-Path -Path $BackupFile)) {
            if (Test-Path -Path $TargetFile) { Remove-Item -Path $TargetFile -Force -ErrorAction SilentlyContinue }
            Move-Item -Path $BackupFile -Destination $TargetFile -Force
            Write-Host "  Rollback completed to previous version." -ForegroundColor Yellow
        } elseif (-not $isBinary -and (Test-Path -Path $BackupDir)) {
            if (Test-Path -Path $TargetDir) { Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction SilentlyContinue }
            Rename-Item -Path $BackupDir -NewName (Split-Path $TargetDir -Leaf) -Force
            Write-Host "  Rollback completed to previous version." -ForegroundColor Yellow
        }
        return $false
    }
    finally {
        Set-Location $oldPwd
    }
}
