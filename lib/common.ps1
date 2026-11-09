# Common utility functions for tool updater

function Resolve-Template {
    param (
        [string] $Template,
        [hashtable] $Variables
    )
    if ([string]::IsNullOrEmpty($Template)) { return $Template }
    $result = $Template
    foreach ($key in $Variables.Keys) {
        $val = [string]$Variables[$key]
        $result = $result.Replace("`${$key}", $val)
    }
    return $result
}

function Resolve-PathVariables {
    param ([string] $Path)
    if ([string]::IsNullOrEmpty($Path)) { return $Path }
    $Path = $Path.Replace('$env:LOCALAPPDATA', $env:LOCALAPPDATA)
    $Path = $Path.Replace('${env:ProgramFiles}', ${env:ProgramFiles})
    $Path = $Path.Replace('$env:ProgramFiles', ${env:ProgramFiles})
    $Path = $Path.Replace('$env:TEMP', $env:TEMP)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-SemVer {
    param ([string] $VersionString)
    if ([string]::IsNullOrEmpty($VersionString)) { return [System.Version]"0.0.0" }
    $clean = ($VersionString -replace '^[vV]', '') -replace '-.*$', ''
    $clean = $clean -replace '\.windows\.', '.'
    $clean = $clean -replace '\+', '.'
    $parts = $clean.Split('.')
    if ($parts.Length -eq 1) {
        $clean = "$clean.0.0"
    } elseif ($parts.Length -eq 2) {
        $clean = "$clean.0"
    } elseif ($parts.Length -gt 4) {
        $clean = ($parts[0..3] -join '.')
    }
    try {
        return [System.Version]$clean
    } catch {
        return [System.Version]"0.0.0"
    }
}

function Test-VersionCondition {
    param (
        [string] $Condition,
        [string] $Version
    )
    if ([string]::IsNullOrEmpty($Condition)) { return $true }
    $ver = Get-SemVer $Version
    if ($Condition -match '^\s*<\s*(.+)$') {
        return ($ver -lt (Get-SemVer $Matches[1].Trim()))
    }
    if ($Condition -match '^\s*>=\s*(.+)$') {
        return ($ver -ge (Get-SemVer $Matches[1].Trim()))
    }
    if ($Condition -match '^\s*<=\s*(.+)$') {
        return ($ver -le (Get-SemVer $Matches[1].Trim()))
    }
    if ($Condition -match '^\s*>\s*(.+)$') {
        return ($ver -gt (Get-SemVer $Matches[1].Trim()))
    }
    return $true
}
