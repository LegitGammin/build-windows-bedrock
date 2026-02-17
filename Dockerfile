@'
# escape=`
FROM mcr.microsoft.com/windows/servercore:ltsc2022

SHELL ["powershell", "-Command", "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue';"]

WORKDIR C:\app

COPY start.ps1 C:\app\start.ps1

EXPOSE 19132/udp
EXPOSE 19133/udp

VOLUME C:\data

ENTRYPOINT ["powershell.exe","-NoLogo","-ExecutionPolicy","Bypass","-File","C:\\app\\start.ps1"]
'@ | Set-Content -Encoding UTF8 .\Dockerfile
