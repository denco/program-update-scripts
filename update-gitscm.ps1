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

$TargetDir = "$($TargetPath)\git"
$BackupDir = "$($TargetDir).bak"

try {
    $GitCurrentVersion = ("$(git --version)".Split(' ')[2] -replace '.w.*', "")
    # gpg
    # gpg --receive-keys C1E4CBA3AD78D3AFD894F9E0B7A66F03B59076A8
    $gpg  = "$($TargetPath)\git\usr\bin\gpg.exe"

} catch {
    $GitCurrentVersion = "0.0.0"
}

Write-Output "check updates for: git"

if ( $GitCurrentVersion -eq "0.0.0" ) {
    New-Item -Path "$($TargetPath)" -Name "git" -ItemType "directory" >nul 2>&1
    $GitRemoteLatestTag = "$((Invoke-WebRequest -Uri "https://git-scm.com/download/win").Content.Split('"') `
                             | Select-String -Pattern "-64-bit.exe" -AllMatches
                            )".Split('Git-').Split('-')[3].Split(".")[0..2] -join "."

} else {
    $GitRemoteLatestTag = "$(git ls-remote --tags "https://github.com/git-for-windows/git.git" `
                                | Select-String -Pattern "\{\}|-rc" -NotMatch `
                                | Select-String -Pattern "windows" -SimpleMatch `
                                | Sort-Object -erroraction 'SilentlyContinue' { [System.version]($_ -replace '\.windows.*', '' -split '[v]')[1] } `
                                | Select-Object -Last 1 )`
                            ".Trim().Split('v')[1]
}

$ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
$GitRemoteReleasesResponse = Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases"
$ProgressPreference = 'Continue'

# Write-Output "remote : >$($GitRemoteLatestTag)<"
# Write-Output "local : >$($GitCurrentVersion)<"

if ( [System.Version]($GitRemoteLatestTag -replace '\.windows.*', '') -gt [System.Version]$GitCurrentVersion ) {
    Write-Output "update needed to: $($GitRemoteLatestTag)"

    # MinGit
    # $FilePrefix  = "MinGit"
    # $FileSearchSuffix  = "64-bit.zip"

    # PortableGit
    $FilePrefix  = "PortableGit"
    $FileSearchSuffix  = "64-bit.7z.exe"

    $FileSearchPattern = "$($FilePrefix)-$($GitRemoteLatestTag -replace '\.windows.*', '')(.\d)?-$($FileSearchSuffix)"
    try {
        # $TargetFileName = (($GitRemoteReleasesResponse.Content.Split("`n") | select-string -Pattern "$($FileSearchPattern)" -AllMatches -Context 0,1)[0] -replace "</?td>", "" -split "\n")[0].split(" ")[1].trim()
        $TargetDownload = (($GitRemoteReleasesResponse.Content.Split("`n") | select-string -Pattern $FileSearchPattern -AllMatches -Context 0,1)[0] -replace "</?td>|\r|\n|\f", "" -replace "\B\s+|>|<", "")
    }
    catch {
        Write-Output "no windows package found"
        exit
    }

    $TargetFileName = ($TargetDownload -split "\s+")[0]
    $Sha256Sum = ($TargetDownload -split "\s+")[1]

    # write-Output "FILE: #$($TargetFileName)#"
    # write-Output "SUM:  #$($Sha256Sum)#"

    $DownloadFullPath = "$($env:TEMP)\$($TargetFileName)"

    $GitRemoteLatestVersionArray = @($TargetFileName.Replace("$($FilePrefix)-", "").Replace("-$($FileSearchSuffix)", "").Split("."))
    $GitRemoteLatestVersion = ($GitRemoteLatestVersionArray -join ".")

    $GitRemoteLatestVersionSuffix = ".windows.1"
    if ($GitRemoteLatestVersionArray.count -gt 3) {
        $GitRemoteLatestVersionSuffix = ".windows." + $GitRemoteLatestVersionArray[3]
        $GitRemoteLatestVersion = ($GitRemoteLatestVersionArray[0..2] -join ".")
    }
    #
    # write-Output $GitRemoteLatestVersionArray
    # Write-Output $DownloadFullPath
    # write-Output "DOWLOAD VERSION: $($GitRemoteLatestVersion), SUFFIX: $($GitRemoteLatestVersionSuffix)"

    if ( -not (Test-Path -Path $DownloadFullPath)) {
        $Url = "https://github.com/git-for-windows/git/releases/download/v$($GitRemoteLatestVersion)$($GitRemoteLatestVersionSuffix)/$($TargetFileName)"

        $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
        Invoke-WebRequest -Uri $Url -OutFile $DownloadFullPath
        $ProgressPreference = 'Continue'
    }

    if ((Get-FileHash $DownloadFullPath).Hash.ToLower() -eq "$($Sha256Sum)") {
        Move-Item $TargetDir $BackupDir `
            && & $vScanner -Scan -ScanType 3 -File $DownloadFullPath `
            && & $7Zip x "$($DownloadFullPath)" -o"$($TargetDir)" > nul `
            && Remove-Item -Path $DownloadFullPath -Force `
            && Remove-Item -Path $BackupDir -Recurse -Force `
            && Write-Output "updated to version: $($GitRemoteLatestTag)" `
        || Move-Item $BackupDir $TargetDir
    }
} else {
    Write-Output "Nothing to update."
}
