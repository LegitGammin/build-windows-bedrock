# escape=`
FROM mcr.microsoft.com/windows/servercore:ltsc2022

SHELL ["powershell", "-Command", "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue';"]

WORKDIR C:\app

# Bootstrap script only (NO bedrock binaries bundled)
COPY start.ps1 C:\app\start.ps1

# Bedrock ports (UDP)
EXPOSE 19132/udp
EXPOSE 19133/udp

# Persistent data mount
VOLUME C:\data

ENTRYPOINT ["powershell.exe","-NoLogo","-ExecutionPolicy","Bypass","-File","C:\\app\\start.ps1"]
