# Aeris

**Breathe freely.** Windows VPN and DPI client using native WinUI 3. Development version 0.1.0. The initial app is a launchable development shell, not a working VPN UI. The approved UI design will be implemented in the subsequent stages.

[Aeris Core](https://github.com/geliopat/Aeris-Core) · [Aeris Resources](https://github.com/geliopat/Aeris-Resources) · [UI specification](https://github.com/geliopat/Aeris-Core/blob/main/docs/UI-SPECIFICATION.md)

Build on Windows with .NET 10 SDK and Windows SDK/WinUI build tools:

```powershell
dotnet build src/Aeris/Aeris.csproj -c Release -p:Platform=x64
```

Windows App SDK 1.8.10 is a deliberately pinned initial baseline, subject to actual Windows build and compatibility testing. The installer, IPC and agreed dashboard are not implemented. License decision pending upstream audit.
