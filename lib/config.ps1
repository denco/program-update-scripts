# Configuration and catalog management functions for tool updater

function Get-ToolConfiguration {
    param (
        [string] $ConfigFile,
        [string] $ScriptDir
    )

    $defaultConfigFile = Join-Path $ScriptDir "config.json"
    $catalogDir = Join-Path $ScriptDir "catalog"

    if (-not (Test-Path -Path $ConfigFile)) {
        Write-Error "Configuration file not found: $ConfigFile"
        exit 1
    }

    $rawLoaded = Get-Content -Raw -Path $ConfigFile | ConvertFrom-Json

    # Check if $ConfigFile is a single tool definition (has .id, no .tools or .defaults)
    if ($rawLoaded.id -and -not $rawLoaded.tools -and -not $rawLoaded.defaults) {
        $singleTool = $rawLoaded
        if (Test-Path -Path $defaultConfigFile) {
            $Config = Get-Content -Raw -Path $defaultConfigFile | ConvertFrom-Json
        } else {
            $Config = [PSCustomObject]@{
                defaults = [PSCustomObject]@{
                    baseInstallPath = "$env:LOCALAPPDATA\Programs"
                    binDirectory    = "$env:LOCALAPPDATA\Programs\bin"
                    sevenZipPath    = "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
                    gpgPath         = "$env:LOCALAPPDATA\Programs\git\usr\bin\gpg.exe"
                    virusScanner    = [PSCustomObject]@{
                        enabled    = $true
                        executable = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"
                        arguments  = @("-Scan", "-ScanType", "3", "-File", "`${filePath}")
                    }
                }
            }
        }
        $Config | Add-Member -MemberType NoteProperty -Name "tools" -Value @($singleTool) -Force
    } else {
        $Config = $rawLoaded
    }

    # Merge tools from catalog directory
    $toolsList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $existingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($Config.tools) {
        foreach ($t in $Config.tools) {
            $toolsList.Add($t)
            if ($t.id) { [void]$existingIds.Add($t.id) }
        }
    }

    if (Test-Path -Path $catalogDir) {
        $descFiles = Get-ChildItem -Path $catalogDir -Filter "*.json" | Sort-Object Name
        foreach ($df in $descFiles) {
            try {
                $tObj = Get-Content -Raw -Path $df.FullName | ConvertFrom-Json
                if ($tObj.id -and -not $existingIds.Contains($tObj.id)) {
                    $toolsList.Add($tObj)
                    [void]$existingIds.Add($tObj.id)
                }
            } catch {
                Write-Warning "Failed to parse tool definition: $($df.FullName) - $_"
            }
        }
    }

    $Config | Add-Member -MemberType NoteProperty -Name "tools" -Value ($toolsList.ToArray()) -Force

    # Resolve tool runtime paths
    $baseInstallPath = Resolve-PathVariables $Config.defaults.baseInstallPath
    $binDirectory    = Resolve-PathVariables $Config.defaults.binDirectory
    $sevenZip        = Resolve-PathVariables $Config.defaults.sevenZipPath
    $gpg             = Resolve-PathVariables $Config.defaults.gpgPath
    $vScanner        = Resolve-PathVariables $Config.defaults.virusScanner.executable

    if (-not (Test-Path -Path $sevenZip)) {
        $7zCommand = Get-Command "7z.exe" -ErrorAction SilentlyContinue
        if ($7zCommand) { $sevenZip = $7zCommand.Source }
    }
    if (-not (Test-Path -Path $gpg)) {
        $gpgCommand = Get-Command "gpg.exe" -ErrorAction SilentlyContinue
        if ($gpgCommand) { $gpg = $gpgCommand.Source }
    }

    return [PSCustomObject]@{
        Config = $Config
        Tools  = $Config.tools
        Paths  = @{
            BaseInstallPath = $baseInstallPath
            BinDirectory    = $binDirectory
            SevenZip        = $sevenZip
            Gpg             = $gpg
            VirusScanner    = $vScanner
        }
    }
}

function Show-ToolCatalog {
    param (
        [array] $Tools
    )
    Write-Host "`nTools Catalog ($($Tools.Count) tools loaded)`n" -ForegroundColor Cyan
    $toolRows = foreach ($t in $Tools) {
        [PSCustomObject]@{
            ID          = $t.id
            Name        = $t.name
            Type        = $t.target.type
            DelayDays   = $t.updateDelayDays
            MultiVer    = if ($t.multiVersion -and $t.multiVersion.enabled) { "Yes (" + ($t.multiVersion.defaultVersions -join ', ') + ")" } else { "No" }
            Checksum    = $t.verification.checksum.algorithm
            Signatures  = if ($t.verification.signatures) { ($t.verification.signatures.type -join ', ') } else { "none" }
        }
    }
    $toolRows | Format-Table -AutoSize
}

function Get-TargetTools {
    param (
        [array] $ToolsList,
        [string[]] $ToolParam
    )

    if (-not $ToolParam -or $ToolParam -contains "all" -or $ToolParam -contains "*") {
        return $ToolsList
    }

    $matchedTools = @()
    foreach ($entry in $ToolParam) {
        $parts = $entry -split '[,; ]'
        foreach ($req in $parts) {
            $req = $req.Trim()
            if (-not $req) { continue }
            $match = $ToolsList | Where-Object { $_.id -eq $req.ToLower() -or $_.name -like "*$req*" }
            if ($match) {
                foreach ($m in $match) {
                    if ($matchedTools.id -notcontains $m.id) {
                        $matchedTools += $m
                    }
                }
            } else {
                Write-Warning "Tool '$req' not found in configuration!"
            }
        }
    }
    return $matchedTools
}
