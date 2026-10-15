param(
    [string]$SwiftPath,
    [switch]$CoreOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($SwiftPath) {
    $swiftCommand = (Resolve-Path -LiteralPath $SwiftPath).Path
} else {
    $foundSwift = Get-Command swift -ErrorAction SilentlyContinue
    if (-not $foundSwift) {
        Write-Output 'BLOCKED: Swift compiler was not found. No Swift build or XCTest has run.'
        Write-Output 'Install Swift and Windows C++/SDK prerequisites using https://www.swift.org/install/windows/ or pass -SwiftPath.'
        exit 2
    }
    $swiftCommand = $foundSwift.Source
}
& $swiftCommand --version
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$packages = @('DongShaoCore')
if (-not $CoreOnly) { $packages += @('DongShaoMocks', 'DongShaoProviders', 'DongShaoWorkflows') }
foreach ($package in $packages) {
    $packagePath = Join-Path $projectRoot "iOS\Packages\$package"
    Write-Output "Testing $package"
    & $swiftCommand test --package-path $packagePath
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
Write-Output 'Swift package tests completed. This does not validate Apple SDKs or iPhone behavior.'
