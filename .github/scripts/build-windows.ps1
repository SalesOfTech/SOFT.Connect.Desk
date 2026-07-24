param(
    [ValidateSet("all", "support", "operator")]
    [string]$Role = "support",
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64"
)

$ErrorActionPreference = "Stop"

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$distRoot = Join-Path $sourceRoot "dist\windows"
$cargoTarget = if ($env:CARGO_TARGET_DIR) {
    $env:CARGO_TARGET_DIR
}
else {
    Join-Path $env:RUNNER_TEMP "soft-connect-cargo-target"
}
$vcpkgRoot = $env:VCPKG_ROOT
$targetTriple = if ($Architecture -eq "arm64") {
    "aarch64-pc-windows-msvc"
}
else {
    "x86_64-pc-windows-msvc"
}
$vcpkgTriplet = if ($Architecture -eq "arm64") {
    "arm64-windows-static"
}
else {
    "x64-windows-static"
}

if (-not $vcpkgRoot) {
    throw "VCPKG_ROOT is not set"
}

$cargo = (Get-Command cargo.exe).Source
$python = (Get-Command python.exe).Source
$flutterCommand = (Get-Command flutter.bat).Source
$flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterCommand)
$vcpkg = Join-Path $vcpkgRoot "vcpkg.exe"
$llvmBin = Split-Path -Parent (Get-Command clang.exe).Source

function Import-Vs2022Environment {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "vswhere.exe was not found"
    }

    $installationPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    $vsDevCmd = Join-Path $installationPath "Common7\Tools\VsDevCmd.bat"
    if (-not (Test-Path -LiteralPath $vsDevCmd)) {
        throw "Visual Studio 2022 build environment was not found"
    }

    $env:VSCMD_SKIP_SENDTELEMETRY = "1"
    $vsArch = if ($Architecture -eq "arm64") { "arm64" } else { "x64" }
    $hostArch = if ($Architecture -eq "arm64" -and $env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        "arm64"
    }
    else {
        "x64"
    }
    $lines = & "$env:SystemRoot\System32\cmd.exe" /s /c "`"$vsDevCmd`" -arch=$vsArch -host_arch=$hostArch >nul && set"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to initialize Visual Studio 2022"
    }
    foreach ($line in $lines) {
        if ($line.StartsWith("=") -or -not $line.Contains("=")) {
            continue
        }
        $name, $value = $line.Split("=", 2)
        [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

Import-Vs2022Environment

$env:CARGO_TARGET_DIR = $cargoTarget
$env:CARGO_INCREMENTAL = "0"
$env:VCPKG_DEFAULT_TRIPLET = $vcpkgTriplet
$env:VCPKG_DEFAULT_HOST_TRIPLET = $vcpkgTriplet
$env:LIBCLANG_PATH = $llvmBin
$env:LLVM_CONFIG_PATH = Join-Path $llvmBin "llvm-config.exe"
$env:LLVMInstallDir = Split-Path -Parent $llvmBin
$env:PATH = @($llvmBin, (Join-Path $env:USERPROFILE ".cargo\bin"), $env:PATH) -join ";"

$hostFolder = if ($Architecture -eq "arm64" -and $env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    "Hostarm64"
}
else {
    "Hostx64"
}
$targetFolder = if ($Architecture -eq "arm64") { "arm64" } else { "x64" }
$msvcCompiler = Join-Path $env:VCToolsInstallDir "bin\$hostFolder\$targetFolder\cl.exe"
if (-not (Test-Path -LiteralPath $msvcCompiler)) {
    $msvcCompiler = Join-Path $env:VCToolsInstallDir "bin\Hostx64\$targetFolder\cl.exe"
}
if ($Architecture -eq "arm64") {
    $env:CC_aarch64_pc_windows_msvc = $msvcCompiler
    $env:CXX_aarch64_pc_windows_msvc = $msvcCompiler
}
else {
    $env:CC_x86_64_pc_windows_msvc = $msvcCompiler
    $env:CXX_x86_64_pc_windows_msvc = $msvcCompiler
}

$vcpkgInstalled = Join-Path $vcpkgRoot "installed"
if (-not (Test-Path -LiteralPath $vcpkgInstalled)) {
    throw "vcpkg dependencies are not installed: $vcpkgInstalled"
}

New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

function Clear-RoleOutput {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $safeRoot = [System.IO.Path]::GetFullPath($distRoot)
    if (-not $resolved.StartsWith($safeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove path outside dist root: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Build-Role {
    param(
        [string]$RoleName,
        [string]$Feature,
        [string]$PortableName,
        [string]$InstallerName
    )

    $roleRoot = Join-Path $distRoot $RoleName
    $bundleRoot = Join-Path $roleRoot "bundle"
    Clear-RoleOutput -Path $roleRoot
    New-Item -ItemType Directory -Force -Path $roleRoot | Out-Null

    Push-Location $sourceRoot
    try {
        $features = if ($Architecture -eq "arm64") {
            "flutter,hwcodec,$Feature"
        }
        else {
            "flutter,hwcodec,vram,$Feature"
        }
        & $cargo +1.75.0 build --locked --target $targetTriple --features $features --lib --release
        if ($LASTEXITCODE -ne 0) {
            throw "Cargo build failed for $RoleName"
        }

        $coreDll = Join-Path $cargoTarget "$targetTriple\release\librustdesk.dll"
        if (-not (Test-Path -LiteralPath $coreDll)) {
            throw "Cargo core DLL not found: $coreDll"
        }
        $flutterCoreDir = Join-Path $sourceRoot "target\release"
        New-Item -ItemType Directory -Force -Path $flutterCoreDir | Out-Null
        Copy-Item -LiteralPath $coreDll `
            -Destination (Join-Path $flutterCoreDir "librustdesk.dll") -Force

        Push-Location (Join-Path $sourceRoot "flutter")
        try {
            & $flutterCommand build windows --release
            if ($LASTEXITCODE -ne 0) {
                throw "Flutter build failed for $RoleName"
            }
        }
        finally {
            Pop-Location
        }

        $flutterBundle = Join-Path $sourceRoot "flutter\build\windows\$Architecture\runner\Release"
        Copy-Item -LiteralPath $flutterBundle -Destination $bundleRoot -Recurse

        $virtualDisplay = Join-Path $cargoTarget "$targetTriple\release\deps\dylib_virtual_display.dll"
        if (Test-Path -LiteralPath $virtualDisplay) {
            Copy-Item -LiteralPath $virtualDisplay -Destination $bundleRoot -Force
        }

        $innerExe = Join-Path $bundleRoot "SOFT.Connect.Desk.exe"
        if (-not (Test-Path -LiteralPath $innerExe)) {
            throw "Flutter bundle executable not found: $innerExe"
        }

        $portableDir = Join-Path $sourceRoot "libs\portable"
        & $python -m pip install --disable-pip-version-check `
            -r (Join-Path $portableDir "requirements.txt")
        if ($LASTEXITCODE -ne 0) {
            throw "Portable Python dependencies failed"
        }

        & $python (Join-Path $portableDir "generate.py") `
            -f $bundleRoot -o $portableDir -e $innerExe -t $targetTriple
        if ($LASTEXITCODE -ne 0) {
            throw "Portable packer failed for $RoleName"
        }

        $packer = Join-Path $cargoTarget "$targetTriple\release\rustdesk-portable-packer.exe"
        if (-not (Test-Path -LiteralPath $packer)) {
            throw "Portable packer executable not found: $packer"
        }
        Copy-Item -LiteralPath $packer -Destination (Join-Path $roleRoot $PortableName) -Force
        Copy-Item -LiteralPath $packer -Destination (Join-Path $roleRoot $InstallerName) -Force
    }
    finally {
        Pop-Location
    }
}

if ($Role -in @("all", "support")) {
    $supportPortable = if ($Architecture -eq "arm64") {
        "SOFT.Connect.Desk-Support-arm64-QS.exe"
    }
    else {
        "SOFT.Connect.Desk-Support-QS.exe"
    }
    $supportInstaller = if ($Architecture -eq "arm64") {
        "SOFT.Connect.Desk-Support-arm64-install.exe"
    }
    else {
        "SOFT.Connect.Desk-Support-install.exe"
    }
    Build-Role `
        -RoleName "Support" `
        -Feature "soft-connect-support" `
        -PortableName $supportPortable `
        -InstallerName $supportInstaller
}

if ($Role -in @("all", "operator")) {
    $operatorPortable = if ($Architecture -eq "arm64") {
        "SOFT.Connect.Desk-Operator-arm64-Portable.exe"
    }
    else {
        "SOFT.Connect.Desk-Operator-Portable.exe"
    }
    $operatorInstaller = if ($Architecture -eq "arm64") {
        "SOFT.Connect.Desk-Operator-arm64-install.exe"
    }
    else {
        "SOFT.Connect.Desk-Operator-install.exe"
    }
    Build-Role `
        -RoleName "Operator" `
        -Feature "soft-connect-operator" `
        -PortableName $operatorPortable `
        -InstallerName $operatorInstaller
}

$hashRows = Get-ChildItem -LiteralPath $distRoot -Recurse -Filter "*.exe" |
    Sort-Object FullName |
    ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $relative = $_.FullName.Substring($distRoot.TrimEnd("\").Length + 1).Replace("\", "/")
        "$hash  $relative"
    }
$hashRows | Set-Content -LiteralPath (Join-Path $distRoot "SHA256SUMS.txt") -Encoding ascii

Write-Output "Windows artifacts: $distRoot"
