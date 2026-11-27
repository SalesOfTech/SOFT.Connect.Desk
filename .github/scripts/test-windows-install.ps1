param(
    [ValidateSet("all", "support", "operator")]
    [string]$Role,
    [ValidateSet("x64", "arm64")]
    [string]$Architecture
)

$ErrorActionPreference = "Stop"
$app = "SOFT.Connect.Desk"
$registry = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$app"
$installed = Join-Path $env:ProgramFiles "$app\$app.exe"
$dist = Join-Path $PSScriptRoot "..\..\dist\windows"
$archPart = if ($Architecture -eq "arm64") { "arm64-" } else { "" }
$releaseVersion = $env:GITHUB_REF_NAME.TrimStart('v').Replace('-', '.')
$patchNumber = [int]($releaseVersion.Split('.')[2])

function Wait-ForInstall([scriptblock]$Condition, [string]$Description) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (& $Condition) { return }
        Start-Sleep -Seconds 2
    } while ($timer.Elapsed.TotalSeconds -lt 150)
    throw "Timed out waiting for $Description"
}

function Start-Desk([string]$Path, [string[]]$Arguments) {
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -PassThru
    try {
        # The self-extracting EXE launches the installed runner asynchronously.
        if (-not $process.WaitForExit(90000)) { throw "Did not exit: $Path $Arguments" }
    }
    finally {
        $process.Dispose()
    }
}

function Assert-NewInstall([string]$RoleName) {
    $bundle = Join-Path $dist "$RoleName\bundle\libsoftconnectdesk.dll"
    $expectedHash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash
    $installedDll = Join-Path (Split-Path $installed) "libsoftconnectdesk.dll"
    Wait-ForInstall {
        $state = Get-ItemProperty -LiteralPath $registry -ErrorAction SilentlyContinue
        $state.DisplayVersion -eq $releaseVersion -and $state.VersionBuild -eq $patchNumber -and
        $state.WindowsInstaller -eq 0 -and (Test-Path -LiteralPath $installed) -and
        (Test-Path -LiteralPath $installedDll) -and
        (Get-FileHash -LiteralPath $installedDll -Algorithm SHA256).Hash -eq $expectedHash
    } "$RoleName $Architecture $releaseVersion with the new DLL and EXE installation state"
}

$upgradeRole = if ($Role -eq "operator") { "Operator" } else { "Support" }
$oldName = "$app-$upgradeRole-${archPart}install.exe"
$baselineHashes = @{
    "SOFT.Connect.Desk-Support-install.exe" = "7ad5b41ddc99ff5e29aa71bd4884421e66802d0371d2186cfdf734b5ff4e2586"
    "SOFT.Connect.Desk-Support-arm64-install.exe" = "488ba55490d591a4583e61687cd853d2f5ff9c3e26bd1d483c6f910778fcb85d"
    "SOFT.Connect.Desk-Operator-install.exe" = "cca5ab12989e7b72bd58c7270dff5ba8ca898c86845819d1282dd688950555df"
    "SOFT.Connect.Desk-Operator-arm64-install.exe" = "ecbbd0ca49441493d75069fe1ea39e6032370e5e61a062d9460e41150fda3770"
}
$old = Join-Path $env:RUNNER_TEMP $oldName
Invoke-WebRequest -Uri "https://github.com/SalesOfTech/SOFT.Connect.Desk/releases/download/v1.4.9-soft.6/$oldName" -OutFile $old
if ((Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash -ne $baselineHashes[$oldName]) {
    throw "The Windows upgrade baseline does not match the published v1.4.9-soft.6 asset"
}

Start-Desk $old @("--silent-install", "printer=0")
Wait-ForInstall {
    $state = Get-ItemProperty -LiteralPath $registry -ErrorAction SilentlyContinue
    $state.DisplayVersion -like "1.4.9*" -and (Test-Path -LiteralPath $installed)
} "the v1.4.9-soft.6 installation"
Start-Desk (Join-Path $dist "$upgradeRole\$oldName") @("--update")
Assert-NewInstall $upgradeRole
Write-Host "EXE upgrade passed on $Architecture ($upgradeRole, v1.4.9-soft.6 -> $releaseVersion)"

Start-Desk $installed @("--uninstall")
Wait-ForInstall {
    -not (Test-Path -LiteralPath $installed) -and -not (Test-Path -LiteralPath $registry) -and
    -not (Get-Service -Name $app -ErrorAction SilentlyContinue)
} "removal of the upgrade fixture"

$freshRole = if ($Role -eq "all") { "Operator" } else { $upgradeRole }
Start-Desk (Join-Path $dist "$freshRole\$app-$freshRole-${archPart}install.exe") @("--silent-install", "printer=0")
Assert-NewInstall $freshRole
Write-Host "Fresh EXE installation passed on $Architecture ($freshRole, $releaseVersion)"
