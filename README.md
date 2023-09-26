# Scripts to update/install programs

All scripts install programs into `%LOCALAPPDATA%\Programs`

## Exceptions

- [terrafrom](./update-terraform.ps1) will be installed into `%LOCALAPPDATA%\Programs\bin`
- [jdk](./update-jdk.ps1) accept parameter for installed jdk-versions, jdk version is own subdirectory in `%LOCALAPPDATA%\Programs\jdk`  
  ex: `.\update-jdk.ps1 17 20` - will install jdk17 and jdk20
