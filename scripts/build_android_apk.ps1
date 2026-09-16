#Requires -Version 7.0

<#
.SYNOPSIS
    Builds a reproducible incremental Android release APK for Aaalice Pocket.

.DESCRIPTION
    Validates the repository's frozen Flutter, Dart, Java, Gradle, AGP, Kotlin,
    compile SDK, and Android build-tools versions before building. The default
    path never upgrades tools, clears caches, refreshes Gradle dependencies, or
    runs code generation. Pub is resolved offline only when the dependency
    manifest changed, and the APK build itself always uses --no-pub.

.PARAMETER AllowOnlinePubRestore
    Allows Pub to use the network when pubspec.yaml or pubspec.lock changed and
    the local Pub cache cannot satisfy the locked dependency graph.

.PARAMETER RestartGradleDaemon
    Stops the current Gradle daemon before building. This is an explicit
    recovery action for a permission-constrained daemon; it does not delete
    Gradle caches or build outputs.

.PARAMETER OutputDirectory
    Repository-relative or absolute directory receiving the versioned APK.

.PARAMETER ValidateOnly
    Validates the frozen toolchain and dependency sources without resolving
    packages, stopping Gradle, or starting a build.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/build_android_apk.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/build_android_apk.ps1 -RestartGradleDaemon
#>

[CmdletBinding()]
param(
    [switch]$AllowOnlinePubRestore,
    [switch]$RestartGradleDaemon,
    [switch]$ValidateOnly,
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = 'dist/android'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RequiredMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        [Parameter(Mandatory)]
        [string]$Pattern,
        [Parameter(Mandatory)]
        [string]$Description
    )

    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) {
        throw "Unable to read $Description from the frozen build configuration."
    }
    return $match.Groups['value'].Value
}

function Assert-EqualValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Actual,
        [Parameter(Mandatory)]
        [string]$Expected
    )

    if ($Actual -cne $Expected) {
        throw "$Name mismatch. Expected '$Expected', found '$Actual'. Restore the known Android toolchain instead of upgrading it."
    }
}

function Get-DependencyFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PubspecPath,
        [Parameter(Mandatory)]
        [string]$LockfilePath,
        [Parameter(Mandatory)]
        [string]$FlutterVersion
    )

    $pubspecHash = (Get-FileHash -LiteralPath $PubspecPath -Algorithm SHA256).Hash
    $lockfileHash = (Get-FileHash -LiteralPath $LockfilePath -Algorithm SHA256).Hash
    $bytes = [Text.Encoding]::UTF8.GetBytes(
        "$FlutterVersion`n$pubspecHash`n$lockfileHash"
    )
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-AndroidDevPluginNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PluginMetadataPath
    )

    if (-not (Test-Path -LiteralPath $PluginMetadataPath -PathType Leaf)) {
        return @()
    }

    $metadata = Get-Content -Raw -Encoding UTF8 -LiteralPath $PluginMetadataPath |
        ConvertFrom-Json
    return @(
        $metadata.plugins.android |
            Where-Object { $_.dev_dependency -eq $true } |
            ForEach-Object { [string]$_.name }
    )
}

function Test-ReleasePluginRegistrant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistrantPath,
        [Parameter(Mandatory)]
        [string[]]$DevPluginNames
    )

    if (-not (Test-Path -LiteralPath $RegistrantPath -PathType Leaf)) {
        return $false
    }

    $registrantText = Get-Content -Raw -Encoding UTF8 -LiteralPath $RegistrantPath
    foreach ($pluginName in $DevPluginNames) {
        if ($registrantText.Contains("Error registering plugin $pluginName,")) {
            return $false
        }
    }
    return $true
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$environmentLockPath = Join-Path $repoRoot 'tool/android_build_environment.lock.json'
$localPropertiesPath = Join-Path $repoRoot 'android/local.properties'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$pubspecLockPath = Join-Path $repoRoot 'pubspec.lock'
$dependencyStatePath = Join-Path $repoRoot '.dart_tool/aaalice_android_build_state.json'
$pluginMetadataPath = Join-Path $repoRoot '.flutter-plugins-dependencies'
$androidPluginRegistrantPath = Join-Path $repoRoot 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'

foreach ($requiredPath in @(
    $environmentLockPath,
    $localPropertiesPath,
    $pubspecPath,
    $pubspecLockPath
)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required build file is missing: $requiredPath"
    }
}

$environmentLock = Get-Content -Raw -Encoding UTF8 -LiteralPath $environmentLockPath |
    ConvertFrom-Json
$localProperties = ConvertFrom-StringData (
    Get-Content -Raw -Encoding UTF8 -LiteralPath $localPropertiesPath
)
if ([string]::IsNullOrWhiteSpace($localProperties.'flutter.sdk')) {
    throw 'flutter.sdk is missing from android/local.properties.'
}
if ([string]::IsNullOrWhiteSpace($localProperties.'sdk.dir')) {
    throw 'sdk.dir is missing from android/local.properties.'
}

$flutterRoot = [IO.Path]::GetFullPath($localProperties.'flutter.sdk')
$androidSdkRoot = [IO.Path]::GetFullPath($localProperties.'sdk.dir')
$flutterCommand = Join-Path $flutterRoot 'bin/flutter.bat'
$flutterExtensionPath = Join-Path $flutterRoot 'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt'
$gradleWrapperPath = Join-Path $repoRoot 'android/gradle/wrapper/gradle-wrapper.properties'
$settingsGradlePath = Join-Path $repoRoot 'android/settings.gradle'
$gradleCommand = Join-Path $repoRoot 'android/gradlew.bat'
$buildToolsRoot = Join-Path $androidSdkRoot "build-tools/$($environmentLock.buildToolsVersion)"
$aaptCommand = Join-Path $buildToolsRoot 'aapt.exe'
$apksignerCommand = Join-Path $buildToolsRoot 'apksigner.bat'

foreach ($requiredTool in @(
    $flutterCommand,
    $flutterExtensionPath,
    $gradleWrapperPath,
    $settingsGradlePath,
    $gradleCommand,
    $aaptCommand,
    $apksignerCommand
)) {
    if (-not (Test-Path -LiteralPath $requiredTool -PathType Leaf)) {
        throw "Frozen Android build tool is missing: $requiredTool"
    }
}

$flutterInfo = (& $flutterCommand --version --machine | Out-String) |
    ConvertFrom-Json
Assert-EqualValue -Name 'Flutter' -Actual ([string]$flutterInfo.frameworkVersion) -Expected ([string]$environmentLock.flutterVersion)
Assert-EqualValue -Name 'Dart' -Actual ([string]$flutterInfo.dartSdkVersion) -Expected ([string]$environmentLock.dartVersion)

if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    throw 'JAVA_HOME is not configured. The frozen Android environment requires JDK 17.'
}
$javaCommand = Join-Path $env:JAVA_HOME 'bin/java.exe'
$keytoolCommand = Join-Path $env:JAVA_HOME 'bin/keytool.exe'
foreach ($javaTool in @($javaCommand, $keytoolCommand)) {
    if (-not (Test-Path -LiteralPath $javaTool -PathType Leaf)) {
        throw "Frozen JDK tool is missing: $javaTool"
    }
}
$javaVersionText = (& $javaCommand -version 2>&1 | Out-String)
$javaMajor = Get-RequiredMatch -Text $javaVersionText -Pattern 'version\s+"(?<value>\d+)' -Description 'Java major version'
Assert-EqualValue -Name 'Java major version' -Actual $javaMajor -Expected ([string]$environmentLock.javaMajorVersion)

$wrapperText = Get-Content -Raw -Encoding UTF8 -LiteralPath $gradleWrapperPath
$gradleVersion = Get-RequiredMatch -Text $wrapperText -Pattern 'gradle-(?<value>[0-9.]+)-(?:all|bin)\.zip' -Description 'Gradle version'
Assert-EqualValue -Name 'Gradle' -Actual $gradleVersion -Expected ([string]$environmentLock.gradleVersion)

$settingsText = Get-Content -Raw -Encoding UTF8 -LiteralPath $settingsGradlePath
$agpVersion = Get-RequiredMatch -Text $settingsText -Pattern 'com\.android\.application"\s+version\s+"(?<value>[^"]+)' -Description 'Android Gradle Plugin version'
$kotlinVersion = Get-RequiredMatch -Text $settingsText -Pattern 'org\.jetbrains\.kotlin\.android"\s+version\s+"(?<value>[^"]+)' -Description 'Kotlin version'
Assert-EqualValue -Name 'Android Gradle Plugin' -Actual $agpVersion -Expected ([string]$environmentLock.androidGradlePluginVersion)
Assert-EqualValue -Name 'Kotlin' -Actual $kotlinVersion -Expected ([string]$environmentLock.kotlinVersion)

$flutterExtensionText = Get-Content -Raw -Encoding UTF8 -LiteralPath $flutterExtensionPath
$compileSdk = Get-RequiredMatch -Text $flutterExtensionText -Pattern 'compileSdkVersion:\s*Int\s*=\s*(?<value>\d+)' -Description 'Flutter compile SDK version'
Assert-EqualValue -Name 'compileSdk' -Actual $compileSdk -Expected ([string]$environmentLock.compileSdkVersion)
$platformPath = Join-Path $androidSdkRoot "platforms/android-$compileSdk"
if (-not (Test-Path -LiteralPath $platformPath -PathType Container)) {
    throw "Frozen Android platform is missing: $platformPath"
}

$versionText = Get-Content -Raw -Encoding UTF8 -LiteralPath $pubspecPath
$appVersion = Get-RequiredMatch -Text $versionText -Pattern '(?m)^version:\s*(?<value>[^\s]+)' -Description 'application version'
if ($appVersion -notmatch '^(?<name>[^+]+)\+(?<code>\d+)$') {
    throw "pubspec.yaml version must contain a numeric Android build number: $appVersion"
}
$versionName = $Matches['name']
$versionCode = $Matches['code']

Push-Location -LiteralPath $repoRoot
try {
    & (Join-Path $repoRoot 'scripts/verify_flutter_sources.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw 'Flutter dependency source verification failed.'
    }

    if ($ValidateOnly) {
        [PSCustomObject]@{
            PSTypeName = 'Aaalice.AndroidBuildEnvironment'
            Flutter = [string]$environmentLock.flutterVersion
            Dart = [string]$environmentLock.dartVersion
            Java = [string]$environmentLock.javaMajorVersion
            Gradle = [string]$environmentLock.gradleVersion
            AndroidGradlePlugin = [string]$environmentLock.androidGradlePluginVersion
            Kotlin = [string]$environmentLock.kotlinVersion
            CompileSdk = [int]$environmentLock.compileSdkVersion
            BuildTools = [string]$environmentLock.buildToolsVersion
            ApplicationId = [string]$environmentLock.applicationId
        } | Format-List
        return
    }

    $fingerprintParameters = @{
        PubspecPath = $pubspecPath
        LockfilePath = $pubspecLockPath
        FlutterVersion = [string]$environmentLock.flutterVersion
    }
    $dependencyFingerprint = Get-DependencyFingerprint @fingerprintParameters
    $packageConfigPath = Join-Path $repoRoot '.dart_tool/package_config.json'
    $storedFingerprint = $null
    if (Test-Path -LiteralPath $dependencyStatePath -PathType Leaf) {
        try {
            $storedState = Get-Content -Raw -Encoding UTF8 -LiteralPath $dependencyStatePath |
                ConvertFrom-Json
            $storedFingerprint = [string]$storedState.fingerprint
        }
        catch {
            Write-Warning 'Ignoring an unreadable local Android dependency-state marker.'
        }
    }

    if ($storedFingerprint -cne $dependencyFingerprint -or
        -not (Test-Path -LiteralPath $packageConfigPath -PathType Leaf)) {
        $pubArguments = @('pub', 'get', '--enforce-lockfile')
        if (-not $AllowOnlinePubRestore) {
            $pubArguments += '--offline'
        }
        Write-Host 'Dependency declaration changed; resolving the locked graph once.' -ForegroundColor Cyan
        & $flutterCommand @pubArguments
        if ($LASTEXITCODE -ne 0) {
            if (-not $AllowOnlinePubRestore) {
                throw 'Offline Pub resolution failed. Fix the cache/network cause, then use -AllowOnlinePubRestore only if locked packages are absent.'
            }
            throw 'Pub resolution failed.'
        }
        $stateDirectory = Split-Path -Parent $dependencyStatePath
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        [PSCustomObject]@{
            fingerprint = $dependencyFingerprint
            resolvedAt = [DateTimeOffset]::Now.ToString('O')
        } | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $dependencyStatePath
    }
    else {
        Write-Host 'Reusing the existing locked Pub dependency graph.' -ForegroundColor Green
    }

    # Flutter 3.44 only rewrites the Android registrant when Pub is enabled.
    # A preceding debug run may therefore leave dev-only plugins in the Java
    # registrant while Gradle correctly excludes those plugins from release.
    # Regenerate release metadata only when that state is detected; repeated
    # release builds continue directly with --no-pub.
    $androidDevPluginNames = Get-AndroidDevPluginNames -PluginMetadataPath $pluginMetadataPath
    $registrantParameters = @{
        RegistrantPath = $androidPluginRegistrantPath
        DevPluginNames = $androidDevPluginNames
    }
    $releaseRegistrantReady = Test-ReleasePluginRegistrant @registrantParameters
    if (-not $releaseRegistrantReady) {
        Write-Host 'Preparing release-only Android plugin metadata once...' -ForegroundColor Cyan
        & $flutterCommand build apk --release --config-only
        if ($LASTEXITCODE -ne 0) {
            throw 'Android release plugin metadata preparation failed.'
        }
        $androidDevPluginNames = Get-AndroidDevPluginNames -PluginMetadataPath $pluginMetadataPath
        $registrantParameters.DevPluginNames = $androidDevPluginNames
        $releaseRegistrantReady = Test-ReleasePluginRegistrant @registrantParameters
        if (-not $releaseRegistrantReady) {
            throw 'Android release plugin registrant still contains a dev-only plugin.'
        }
    }
    else {
        Write-Host 'Reusing release-safe Android plugin metadata.' -ForegroundColor Green
    }

    if ($RestartGradleDaemon) {
        Write-Host 'Stopping the current Gradle daemon without deleting caches...' -ForegroundColor Yellow
        & $gradleCommand --stop
        if ($LASTEXITCODE -ne 0) {
            throw 'Gradle daemon stop failed.'
        }
    }

    Write-Host 'Building the release APK incrementally with --no-pub...' -ForegroundColor Cyan
    & $flutterCommand build apk --release --no-pub
    if ($LASTEXITCODE -ne 0) {
        throw 'Android release APK build failed.'
    }

    $apkPath = Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-release.apk'
    if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
        throw "Flutter reported success but the APK is missing: $apkPath"
    }

    $signatureOutput = & $apksignerCommand verify --verbose --print-certs $apkPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'APK signature verification failed.'
    }
    if (-not ($signatureOutput -match 'Verified using v2 scheme.*:\s+true')) {
        throw 'APK does not contain a verified v2 signature.'
    }

    $packageLine = (& $aaptCommand dump badging $apkPath | Select-Object -First 1)
    if ($packageLine -notmatch "name='$([regex]::Escape([string]$environmentLock.applicationId))'" -or
        $packageLine -notmatch "versionCode='$([regex]::Escape($versionCode))'" -or
        $packageLine -notmatch "versionName='$([regex]::Escape($versionName))'") {
        throw "APK package/version mismatch: $packageLine"
    }

    $keyPropertiesPath = Join-Path $repoRoot 'android/key.properties'
    if (-not (Test-Path -LiteralPath $keyPropertiesPath -PathType Leaf)) {
        throw 'android/key.properties is required for the Aaalice Pocket release signature.'
    }
    $keyProperties = ConvertFrom-StringData (
        Get-Content -Raw -Encoding UTF8 -LiteralPath $keyPropertiesPath
    )
    $keyStorePath = [IO.Path]::GetFullPath(
        (Join-Path (Join-Path $repoRoot 'android/app') $keyProperties.storeFile)
    )
    if (-not (Test-Path -LiteralPath $keyStorePath -PathType Leaf)) {
        throw "Release keystore is missing: $keyStorePath"
    }
    $keytoolArguments = @(
        '-list',
        '-v',
        '-keystore', $keyStorePath,
        '-storepass', $keyProperties.storePassword,
        '-alias', $keyProperties.keyAlias
    )
    $keytoolOutput = & $keytoolCommand @keytoolArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'Configured release keystore could not be verified.'
    }
    $expectedSignerParameters = @{
        Text = $keytoolOutput | Out-String
        Pattern = 'SHA256:\s*(?<value>(?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2})'
        Description = 'release keystore signer digest'
    }
    $expectedSigner = Get-RequiredMatch @expectedSignerParameters
    $actualSignerParameters = @{
        Text = $signatureOutput | Out-String
        Pattern = 'Signer #1 certificate SHA-256 digest:\s*(?<value>[0-9A-Fa-f]{64})'
        Description = 'APK signer digest'
    }
    $actualSigner = Get-RequiredMatch @actualSignerParameters
    $normalizedExpectedSigner = $expectedSigner.Replace(':', '').ToLowerInvariant()
    Assert-EqualValue -Name 'APK signer' -Actual $actualSigner.ToLowerInvariant() -Expected $normalizedExpectedSigner

    $resolvedOutputDirectory = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
        [IO.Path]::GetFullPath($OutputDirectory)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDirectory))
    }
    New-Item -ItemType Directory -Path $resolvedOutputDirectory -Force | Out-Null
    $outputPath = Join-Path $resolvedOutputDirectory "Aaalice_Pocket_$versionName.apk"
    Copy-Item -LiteralPath $apkPath -Destination $outputPath -Force
    $artifact = Get-Item -LiteralPath $outputPath
    $sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()

    [PSCustomObject]@{
        PSTypeName = 'Aaalice.AndroidBuildArtifact'
        Path = $artifact.FullName
        VersionName = $versionName
        VersionCode = [int]$versionCode
        ApplicationId = [string]$environmentLock.applicationId
        SizeBytes = $artifact.Length
        Sha256 = $sha256
    } | Format-List
}
finally {
    Pop-Location
}
