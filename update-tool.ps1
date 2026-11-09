# [CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string[]] $Tool,

    [Parameter()]
    [string[]] $Versions,

    [Parameter()]
    [Alias("Install")]
    [switch] $Update,

    [Parameter()]
    [Alias("Check")]
    [switch] $CheckOnly,

    [Parameter()]
    [switch] $Force,

    [Parameter()]
    [Alias("l")]
    [switch] $List,

    [Parameter()]
    [Alias("h", "?")]
    [switch] $Help,

    [Parameter()]
    [string] $ConfigFile = ""
)

[cultureinfo]::CurrentUICulture = 'en-US'
$PSDefaultParameterValues['Invoke-WebRequest:UseBasicParsing'] = $true

if ($Help -or ($Tool -and ($Tool -contains "help" -or $Tool -contains "--help" -or $Tool -contains "-help"))) {
    Write-Host @"

Tool Updater & Catalog Manager

Usage:
  update-tool.ps1 [[-Tool] <string[]>] [-Versions <string[]>] [-Update] [-CheckOnly] [-Force] [-List] [-Help] [-ConfigFile <string>]

Commands / Flags:
  -Help, --help, -h          Show this help message and list commands
  -List, --list, -l          List all tools from the catalog
  -Update, -Install          Download, verify, and install updates (default action is check-only)
  -CheckOnly, -Check         Explicitly run in check-only mode (default behavior)
  -Force                     Force update or bypass update delay cooldown
  -Tool <name,...>           Specify one or more tools to check or update (e.g. git, nodejs, all)
  -Versions <ver,...>        Specify version(s) for multi-version tools (e.g. 18, 20)
  -ConfigFile <path>         Path to a custom configuration or tool specification JSON file

Examples:
  .\update-tool.ps1                     Check all catalog tools for updates (default)
  .\update-tool.ps1 git                 Check git for updates
  .\update-tool.ps1 git -Update         Update git to the latest version
  .\update-tool.ps1 nodejs 20 -Update   Update Node.js version 20
  .\update-tool.ps1 -List               List all tools available in catalog
  .\update-tool.ps1 --help              Show this help

"@
    exit 0
}

if ($Tool -and ($Tool -contains "list" -or $Tool -contains "--list" -or $Tool -contains "-list")) {
    $List = $true
}

if ([string]::IsNullOrEmpty($ConfigFile)) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = (Get-Location).Path }
    $ConfigFile = Join-Path $scriptDir "config.json"
}

# Dot-source modular libraries
$libDir = Join-Path $scriptDir "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "config.ps1")
. (Join-Path $libDir "version.ps1")
. (Join-Path $libDir "download.ps1")
. (Join-Path $libDir "install.ps1")

# Load configuration and tool definitions
$envConfig = Get-ToolConfiguration -ConfigFile $ConfigFile -ScriptDir $scriptDir
$Config          = $envConfig.Config
$Tools           = $envConfig.Tools
$BaseInstallPath = $envConfig.Paths.BaseInstallPath
$BinDirectory    = $envConfig.Paths.BinDirectory
$7Zip            = $envConfig.Paths.SevenZip
$Gpg             = $envConfig.Paths.Gpg
$vScanner        = $envConfig.Paths.VirusScanner

# List mode
if ($List) {
    Show-ToolCatalog -Tools $Tools
    exit 0
}

# --- Core Update Logic for Single Tool / Target ---
function Update-SingleTool {
    param (
        [PSCustomObject] $ToolDef,
        [string] $VersionParam = $null
    )

    $id = $ToolDef.id
    $name = $ToolDef.name

    # Determine directory or binary paths
    $isBinary = ($ToolDef.target.type -eq "binary")
    $isMulti = ($ToolDef.target.type -eq "multiVersionDirectory")

    $subDir = if ($ToolDef.target.directoryName) { $ToolDef.target.directoryName } else { $id }
    if ($isMulti -and $VersionParam) {
        $subDir = $subDir.Replace('${mainVersion}', $VersionParam)
    }

    $TargetDir = Join-Path $BaseInstallPath $subDir
    $BackupDir = "$TargetDir.bak"

    $TargetFile = if ($isBinary) { Join-Path $BinDirectory $ToolDef.target.binaryName } else { $null }
    $BackupFile = if ($isBinary) { "$TargetFile.bak" } else { $null }

    # Setup template variables
    $vars = [hashtable]::Synchronized(@{
        id               = $id
        name             = $name
        targetDir        = $TargetDir
        baseInstallPath  = $BaseInstallPath
        binDirectory     = $BinDirectory
    })

    if ($VersionParam) {
        $vars['mainVersion'] = $VersionParam
    }

    Write-Host "Checking updates for: $name$(if ($VersionParam) { " ($VersionParam)" })" -ForegroundColor Cyan

    # 1. Resolve Remote Version
    $remoteVersion = Get-RemoteVersion -ToolDef $ToolDef -Variables $vars
    if (-not $remoteVersion) {
        Write-Warning "Could not detect remote version for $name"
        return
    }

    $vars['version']            = $remoteVersion
    $vars['remoteTag']          = $remoteVersion
    $vars['versionWithoutDots'] = $remoteVersion.Replace('.', '')
    $vars['versionUnderscore']  = ($remoteVersion -replace '\+(\d+)?\.?\d?', '_$1')
    if (-not $vars.ContainsKey('mainVersion')) {
        $vars['mainVersion']   = ($remoteVersion.Split('.')[0])
    }

    # 2. Resolve Local Version
    $localInfo = Get-LocalVersion -ToolDef $ToolDef -TargetDir $TargetDir -TargetFile $TargetFile -Variables $vars
    $localVersion = $localInfo.Version

    Write-Host "  Local version : $localVersion"
    Write-Host "  Remote version: $remoteVersion"

    $remoteSemVer = Get-SemVer $remoteVersion
    $localSemVer  = Get-SemVer $localVersion

    # 3. Check if update is needed
    $needsUpdate = ($remoteSemVer -gt $localSemVer)
    if (-not $needsUpdate -and -not $Force) {
        Write-Host "  Status: Up to date." -ForegroundColor Green
        return
    }

    # 4. Check update delay window
    $isDelayed = Test-UpdateDelay -ToolDef $ToolDef -LocalVersion $localVersion -RemoteVersion $remoteVersion `
                                  -LocalInfo $localInfo -TargetDir $TargetDir -Force:$Force
    if ($isDelayed) {
        return
    }

    if (-not $Update -or $CheckOnly) {
        Write-Host "  Status: Update available ($localVersion -> $remoteVersion)" -ForegroundColor Yellow
        return
    }

    Write-Host "  Action: Updating $localVersion -> $remoteVersion ..." -ForegroundColor Green

    # 5. Download artifact
    $downloadFullPath = Invoke-ToolDownload -ToolDef $ToolDef -Variables $vars
    if (-not $downloadFullPath) {
        return
    }

    # 6. Verify artifact (checksum, signatures, malware scan)
    $verified = Test-ToolVerification -ToolDef $ToolDef -Variables $vars -DownloadFullPath $downloadFullPath `
                                     -RemoteVersion $remoteVersion -GpgPath $Gpg -VScannerPath $vScanner
    if (-not $verified) {
        return
    }

    # 7. Extract, Install, and write VERSION
    Install-ToolArtifact -ToolDef $ToolDef -Variables $vars -DownloadFullPath $downloadFullPath `
                        -RemoteVersion $remoteVersion -TargetDir $TargetDir -TargetFile $TargetFile `
                        -BackupDir $BackupDir -BackupFile $BackupFile -BaseInstallPath $BaseInstallPath `
                        -BinDirectory $BinDirectory -SevenZipPath $7Zip
}

# --- Execution Router ---
$targetTools = Get-TargetTools -ToolsList $Tools -ToolParam $Tool

foreach ($t in $targetTools) {
    if ($t.multiVersion -and $t.multiVersion.enabled) {
        $vList = if ($Versions) { $Versions } else { $t.multiVersion.defaultVersions }
        foreach ($v in $vList) {
            Update-SingleTool -ToolDef $t -VersionParam $v
        }
    } else {
        Update-SingleTool -ToolDef $t
    }
}
