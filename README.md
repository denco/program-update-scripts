# Collection of powershell scripts to update/install programs

## Requirements

- PowerShell 7

## Installation directory

All scripts install programs into `$env:LOCALAPPDATA\Programs`

## Exceptions

- [terrafrom](./update-terraform.ps1) will be installed into `$env:LOCALAPPDATA\Programs\bin`
- [jdk](./update-jdk.ps1) accept parameter for installed jdk-versions, jdk version is own subdirectory in `$env:LOCALAPPDATA\Programs\jdk`  
  ex: `.\update-jdk.ps1 17 20` - will install jdk17 and jdk20
