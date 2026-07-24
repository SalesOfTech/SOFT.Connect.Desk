param(
    [ValidateSet("all", "support", "operator")]
    [string]$Role = "support"
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
    $lines = & "$env:SystemRoot\System32\cmd.exe" /s /c "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set"
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
$env:VCPKG_DEFAULT_TRIPLET = "x64-windows-static"
$env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"
$env:LIBCLANG_PATH = $llvmBin
$env:LLVM_CONFIG_PATH = Join-Path $llvmBin "llvm-config.exe"
$env:LLVMInstallDir = Split-Path -Parent $llvmBin
$env:PATH = @($llvmBin, (Join-Path $env:USERPROFILE ".cargo\bin"), $env:PATH) -join ";"

$msvcCompiler = Join-Path $env:VCToolsInstallDir "bin\Hostx64\x64\cl.exe"
$env:CC_x86_64_pc_windows_msvc = $msvcCompiler
$env:CXX_x86_64_pc_windows_msvc = $msvcCompiler

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
        $features = "flutter,hwcodec,vram,$Feature"
        & $cargo +1.75.0 build --locked --features $features --lib --release
        if ($LASTEXITCODE -ne 0) {
            throw "Cargo build failed for $RoleName"
        }

        $coreDll = Join-Path $cargoTarget "release\librustdesk.dll"
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

        $flutterBundle = Join-Path $sourceRoot "flutter\build\windows\x64\runner\Release"
        Copy-Item -LiteralPath $flutterBundle -Destination $bundleRoot -Recurse

        $virtualDisplay = Join-Path $cargoTarget "release\deps\dylib_virtual_display.dll"
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
            -f $bundleRoot -o $portableDir -e $innerExe
        if ($LASTEXITCODE -ne 0) {
            throw "Portable packer failed for $RoleName"
        }

        $packer = Join-Path $cargoTarget "release\rustdesk-portable-packer.exe"
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
    Build-Role `
        -RoleName "Support" `
        -Feature "soft-connect-support" `
        -PortableName "SOFT.Connect.Desk-Support-QS.exe" `
        -InstallerName "SOFT.Connect.Desk-Support-install.exe"
}

if ($Role -in @("all", "operator")) {
    Build-Role `
        -RoleName "Operator" `
        -Feature "soft-connect-operator" `
        -PortableName "SOFT.Connect.Desk-Operator-Portable.exe" `
        -InstallerName "SOFT.Connect.Desk-Operator-install.exe"
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
