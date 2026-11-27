param(
    [Parameter(Mandatory)]
    [ValidateSet('FAST', 'FULL', 'CLEAN')]
    [string] $Mode,
    [Parameter(Mandatory)]
    [string] $WorkDirectory,
    [switch] $SaveArchives
)

$ErrorActionPreference = 'Stop'
$project = 'src/Aeris/Aeris.csproj'
$officialNuGetConfig = (Resolve-Path -LiteralPath 'NuGet.config').Path
$archiveDirectory = Join-Path $WorkDirectory 'aeris-nupkgs'
$manifestPath = Join-Path $archiveDirectory 'manifest.json'
$packageLimit = 512MB
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$attempt = [guid]::NewGuid().ToString('N').Substring(0, 12)
$cacheResult = 'miss'
$archiveBytes = 0
$restoreTime = 0
$buildTime = 0
$buildResult = 'not run'
$sdk = 'unavailable'
$lock = Get-Content -LiteralPath 'src/Aeris/packages.lock.json' -Raw | ConvertFrom-Json -AsHashtable
$lockedArchives = @{}
$lockedPackages = @{}
foreach ($graph in $lock.dependencies.Values) {
    foreach ($package in $graph.GetEnumerator()) {
        $name = "$($package.Key).$($package.Value.resolved).nupkg".ToLowerInvariant()
        $lockedArchives[$name] = $true
        $lockedPackages[$package.Key] = $true
    }
}

function Test-ArchiveCache {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $false }
    try {
        $root = Get-Item -LiteralPath $archiveDirectory -Force
        $children = @(Get-ChildItem -LiteralPath $archiveDirectory -Force)
        if ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        if ($children | Where-Object { $_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) }) {
            return $false
        }
        $hashes = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
        $files = @($children | Where-Object Name -ne 'manifest.json')
        if ($files.Count -eq 0 -or $files.Count -ne $hashes.Count -or $files.Count -ne $lockedArchives.Count) {
            return $false
        }
        $length = ($files | Measure-Object -Property Length -Sum).Sum
        if ($length -gt $packageLimit) { return $false }
        foreach ($file in $files) {
            if (-not $lockedArchives.ContainsKey($file.Name)) { return $false }
            if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $hashes[$file.Name]) {
                return $false
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Write-CachedNuGetConfig {
    [xml] $config = Get-Content -LiteralPath $officialNuGetConfig -Raw
    $source = $config.CreateElement('add')
    $source.SetAttribute('key', 'verified-cache')
    $source.SetAttribute('value', $archiveDirectory)
    [void] $config.configuration.packageSources.AppendChild($source)
    $mapping = $config.CreateElement('packageSourceMapping')
    foreach ($name in @('nuget.org', 'verified-cache')) {
        $packageSource = $config.CreateElement('packageSource')
        $packageSource.SetAttribute('key', $name)
        $patterns = if ($name -eq 'verified-cache') { $lockedPackages.Keys } else { '*' }
        foreach ($pattern in $patterns) {
            $package = $config.CreateElement('package')
            $package.SetAttribute('pattern', $pattern)
            [void] $packageSource.AppendChild($package)
        }
        [void] $mapping.AppendChild($packageSource)
    }
    [void] $config.configuration.AppendChild($mapping)
    $path = Join-Path $WorkDirectory "NuGet.cached-$attempt.config"
    $config.Save($path)
    return $path
}

function Restore-Client([string] $ConfigFile, [string] $Store) {
    $env:NUGET_PACKAGES = Join-Path $WorkDirectory $Store
    dotnet restore $project -p:Platform=x64 --locked-mode --force --no-http-cache --configfile $ConfigFile | Out-Host
    return $LASTEXITCODE
}

try {
    $sdk = dotnet --version
    if ($LASTEXITCODE -ne 0) { throw 'Could not determine the .NET SDK version.' }
    dotnet --info
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the .NET SDK.' }

    $restoreStart = $clock.Elapsed.TotalSeconds
    $restored = $false
    if ($Mode -eq 'CLEAN') {
        $cacheResult = 'disabled by CLEAN'
    } elseif (Test-ArchiveCache) {
        $restored = (Restore-Client (Write-CachedNuGetConfig) "nuget-cached-$attempt") -eq 0
        $cacheResult = if ($restored) { 'verified package archives' } else { 'cached restore rejected' }
        $archiveBytes = (Get-ChildItem -LiteralPath $archiveDirectory -File -Filter '*.nupkg' |
            Measure-Object -Property Length -Sum).Sum
    } elseif (Test-Path -LiteralPath $archiveDirectory) {
        $cacheResult = 'cache missing a valid digest manifest'
    }
    if (-not $restored) {
        if ((Restore-Client $officialNuGetConfig "nuget-online-$attempt") -ne 0) { throw 'Locked NuGet restore failed.' }
    }
    $restoreTime = $clock.Elapsed.TotalSeconds - $restoreStart

    $buildStart = $clock.Elapsed.TotalSeconds
    $buildResult = 'failed'
    $buildArguments = @('build', $project, '-c', 'Release', '-p:Platform=x64', '--no-restore')
    if ($Mode -ne 'FAST') { $buildArguments += '--no-incremental' }
    dotnet @buildArguments
    if ($LASTEXITCODE -ne 0) { throw 'Windows x64 client build failed.' }
    $buildTime = $clock.Elapsed.TotalSeconds - $buildStart
    $buildResult = 'rebuilt and verified'

    if ($SaveArchives -and $Mode -ne 'CLEAN' -and $cacheResult -eq 'miss') {
        $packages = @(Get-ChildItem -LiteralPath $env:NUGET_PACKAGES -Recurse -File -Filter '*.nupkg' |
            Where-Object { $lockedArchives.ContainsKey($_.Name) })
        $archiveBytes = ($packages | Measure-Object -Property Length -Sum).Sum
        if ($packages.Count -eq $lockedArchives.Count -and $packages.Count -gt 0 -and $archiveBytes -le $packageLimit) {
            New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
            $hashes = @{}
            foreach ($package in $packages) {
                Copy-Item -LiteralPath $package.FullName -Destination $archiveDirectory
                $hashes.Add($package.Name, (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash)
            }
            $hashes | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8
            if ($env:GITHUB_OUTPUT) { 'archives_ready=true' >> $env:GITHUB_OUTPUT }
        } elseif ($archiveBytes -gt $packageLimit) {
            $cacheResult = 'archives exceed the 512 MiB limit'
        }
    }
} finally {
    $summary = @(
        '### Windows x64 client'
        ''
        "- Mode: $Mode"
        "- NuGet cache: $cacheResult ($archiveBytes bytes of archives)"
        "- .NET SDK: $sdk"
        "- Runner image: $env:ImageOS $env:ImageVersion"
        "- Client: $buildResult; the current verification compiles from source"
        ('- Package restore and validation: {0:N1}s' -f $restoreTime)
        ('- Compilation: {0:N1}s' -f $buildTime)
        '- Separate test project and packaging: pending'
        ('- Client task total: {0:N1}s' -f $clock.Elapsed.TotalSeconds)
    )
    if ($env:GITHUB_STEP_SUMMARY) {
        $summary | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8
    } else {
        $summary | Out-Host
    }
}
