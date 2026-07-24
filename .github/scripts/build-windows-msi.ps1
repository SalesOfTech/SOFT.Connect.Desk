param(
    [ValidateSet("all", "support", "operator")]
    [string]$Role = "support",
    [ValidateSet("x64", "ARM64")]
    [string]$Platform = "x64"
)

$ErrorActionPreference = "Stop"

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$distRoot = Join-Path $sourceRoot "dist\windows"
$python = (Get-Command python.exe).Source
$nuget = (Get-Command nuget.exe).Source
$msbuild = (Get-Command msbuild.exe).Source

$roles = switch ($Role) {
    "support" { @("Support") }
    "operator" { @("Operator") }
    "all" { @("Support", "Operator") }
}

foreach ($roleName in $roles) {
    $bundleRoot = Join-Path $distRoot "$roleName\bundle"
    if (-not (Test-Path -LiteralPath $bundleRoot)) {
        throw "Windows bundle not found: $bundleRoot"
    }

    Push-Location (Join-Path $sourceRoot "res\msi")
    try {
        & $python preprocess.py `
            --arp `
            --app-name "SOFT.Connect.Desk" `
            --manufacturer "Sales Of Tech" `
            -d $bundleRoot
        if ($LASTEXITCODE -ne 0) {
            throw "MSI preprocessing failed for $roleName"
        }

        & $nuget restore msi.sln
        if ($LASTEXITCODE -ne 0) {
            throw "NuGet restore failed for $roleName"
        }

        & $msbuild msi.sln `
            "-p:Configuration=Release" `
            "-p:Platform=$Platform" `
            "/p:TargetVersion=Windows10"
        if ($LASTEXITCODE -ne 0) {
            throw "MSI build failed for $roleName"
        }

        $msi = Get-ChildItem -Path ".\Package\bin\*\Release\en-us\Package.msi" |
            Select-Object -First 1
        if (-not $msi) {
            throw "Package.msi was not produced for $roleName"
        }

        $archName = if ($Platform -eq "ARM64") { "arm64" } else { "x64" }
        $output = Join-Path $distRoot "$roleName\SOFT.Connect.Desk-$roleName-windows-$archName.msi"
        Copy-Item -LiteralPath $msi.FullName -Destination $output -Force
    }
    finally {
        Pop-Location
    }
}

Write-Output "MSI artifacts were written under $distRoot"
