# Collection of powershell scripts to update/install programs

## Requirements

- PowerShell 7

## Installation directory

All scripts install programs into `$env:LOCALAPPDATA\Programs`

## Exceptions

- [terrafrom](./update-terraform.ps1) will be installed into `$env:LOCALAPPDATA\Programs\bin`
- [jdk](./update-jdk.ps1) accept parameter for installed jdk-versions, jdk version is own subdirectory in `$env:LOCALAPPDATA\Programs\jdk`  
  ex: `.\update-jdk.ps1 17 20` - will install jdk17 and jdk20
- [nodejs](./update-nodejs.ps1) accept parameter for installed node-versions, node version is own subdirectory in `$env:LOCALAPPDATA\Programs\node`  
  ex: `.\update-nodejs.ps1 20` - will install nodeV20
- [python](./update-python.ps1) accept parameter for installed python-versions, python version is own subdirectory in `$env:LOCALAPPDATA\Programs\python`  
  ex: `.\update-python.ps1 3.12` - will install python-3.12
