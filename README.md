# Aeris

**Breathe freely.** Windows VPN and DPI client using native WinUI 3. Development version 0.1.0. The initial app is a launchable development shell, not a working VPN UI. The approved UI design will be implemented in the subsequent stages.

[Aeris Core](https://github.com/geliopat/Aeris-Core) · [Aeris Resources](https://github.com/geliopat/Aeris-Resources) · [UI specification](https://github.com/geliopat/Aeris-Core/blob/main/docs/UI-SPECIFICATION.md)

Build on Windows with .NET 11 SDK and Windows SDK/WinUI build tools:

```powershell
dotnet build src/Aeris/Aeris.csproj -c Release -p:Platform=x64
```

Toolchain: .NET SDK 11.0.100 (stable feature band, servicing patches allowed), C# 15, Windows target SDK 10.0.26100.0, Windows App SDK 2.7.0 / WinUI 3. The minimum target OS remains Windows 10 22H2 x64 (19045); compatibility requires actual runtime tests, including on Windows 10 editions outside Microsoft support. Use runtime availability checks for newer Windows APIs. Keep dependencies on verified stable versions and update them through reviewed changes. The installer, IPC and agreed dashboard are not implemented. License decision pending upstream audit.
