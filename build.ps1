#Requires -Version 5.1
<#
.SYNOPSIS
    Validates and deploys the SSHTools module into your PSModulePath.

.DESCRIPTION
    A small build/deploy helper for local use. It:

      1. (unless -SkipTests) runs PSScriptAnalyzer and the Pester suite, and aborts if
         either fails -- so you never deploy a broken build;
      2. copies the module files into a versioned module folder
         (<ModulesPath>\SSHTools\<version>) so 'Import-Module SSHTools' works from any
         session, and 'Get-Module -ListAvailable' reports the version.

    Only the shipping files are deployed (manifest, root module, Public\, Private\,
    README.md) -- tests, CI config, and docs are left behind.

.PARAMETER Path
    Module root to deploy into. Defaults to C:\Scripts\Modules (a custom folder on
    the PSModulePath). The module lands at <Path>\SSHTools\<version>. Use this to target
    a personal module folder instead of the standard per-user locations.

.PARAMETER Edition
    Deploy into the standard per-edition module path instead of -Path:
      Desktop = Windows PowerShell 5.1, Core = PowerShell 7+, Both = both.

.PARAMETER Scope
    With -Edition: CurrentUser (default) installs under your Documents; AllUsers installs
    under Program Files and requires an elevated session.

.PARAMETER SkipTests
    Skip the PSScriptAnalyzer + Pester validation step and deploy immediately.

.EXAMPLE
    .\build.ps1
    Validate, then install into C:\Scripts\Modules.

.EXAMPLE
    .\build.ps1 -Path D:\MyModules
    Deploy into a different custom module folder.

.EXAMPLE
    .\build.ps1 -Edition Core -WhatIf
    Show where it would deploy into the PowerShell 7 per-user path, copying nothing.

.EXAMPLE
    .\build.ps1 -SkipTests
    Deploy without running the test suite.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'CustomPath')]
param(
    [Parameter(ParameterSetName = 'CustomPath')]
    [string]$Path = 'C:\Scripts\Modules',

    [Parameter(ParameterSetName = 'PSModulePath', Mandatory)]
    [ValidateSet('Desktop', 'Core', 'Both')]
    [string]$Edition,

    [Parameter(ParameterSetName = 'PSModulePath')]
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root         = $PSScriptRoot
$moduleName   = 'SSHTools'
$manifestPath = Join-Path $root "$moduleName.psd1"
$version      = (Import-PowerShellDataFile -Path $manifestPath).ModuleVersion

Write-Host "== $moduleName $version ==" -ForegroundColor Cyan

# --- 1. Validation -----------------------------------------------------------
if (-not $SkipTests) {
    Write-Host 'Running PSScriptAnalyzer...' -ForegroundColor Cyan
    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
        $analysis = foreach ($p in 'Public', 'Private', "$moduleName.psm1", "$moduleName.psd1", 'Tests') {
            $target = Join-Path $root $p
            if (Test-Path $target) { Invoke-ScriptAnalyzer -Path $target -Recurse -Settings $settings }
        }
        $analysisErrors = @($analysis | Where-Object Severity -eq 'Error')
        if ($analysis) { $analysis | Format-Table RuleName, Severity, ScriptName, Line -AutoSize | Out-String | Write-Host }
        if ($analysisErrors.Count -gt 0) { throw "PSScriptAnalyzer reported $($analysisErrors.Count) error(s); aborting." }
    }
    else {
        Write-Warning 'PSScriptAnalyzer not installed; skipping lint.'
    }

    Write-Host 'Running Pester...' -ForegroundColor Cyan
    $pester = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -ge [version]'5.0.0' -and $_.Version -lt [version]'6.0.0' } |
        Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pester) {
        throw "Pester 5.x is required. Install-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99, or re-run with -SkipTests."
    }
    Import-Module $pester.Path -Force
    $config = New-PesterConfiguration
    $config.Run.Path         = Join-Path $root 'Tests'
    $config.Run.PassThru     = $true
    $config.Output.Verbosity = 'Normal'
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) { throw "$($result.FailedCount) test(s) failed; aborting deploy." }
    Write-Host "Tests passed ($($result.PassedCount) passed, $($result.SkippedCount) skipped)." -ForegroundColor Green
}

# --- 2. Resolve destination(s) ----------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'CustomPath') {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Module root '$Path' does not exist yet; it will be created."
    }
    $onPath = ($env:PSModulePath -split ';' | ForEach-Object { $_.TrimEnd('\') }) -contains $Path.TrimEnd('\')
    if (-not $onPath) {
        Write-Warning "'$Path' is not in `$env:PSModulePath; the module will deploy there but won't be auto-discovered until you add it."
    }
    $targets = @([pscustomobject]@{
            Edition = 'Custom'
            Path    = Join-Path $Path "$moduleName\$version"
        })
}
else {
    if ($Scope -eq 'AllUsers') {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) { throw "-Scope AllUsers requires an elevated (Run as Administrator) session." }
    }

    $docs     = [Environment]::GetFolderPath('MyDocuments')   # OneDrive-redirection aware
    $editions = if ($Edition -eq 'Both') { @('Desktop', 'Core') } else { @($Edition) }

    $targets = foreach ($ed in $editions) {
        $base = switch ("$ed|$Scope") {
            'Desktop|CurrentUser' { Join-Path $docs 'WindowsPowerShell\Modules' }
            'Desktop|AllUsers' { Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules' }
            'Core|CurrentUser' { Join-Path $docs 'PowerShell\Modules' }
            'Core|AllUsers' { Join-Path $env:ProgramFiles 'PowerShell\Modules' }
        }
        [pscustomobject]@{
            Edition = $ed
            Path    = Join-Path $base "$moduleName\$version"
        }
    }
}

# --- 3. Deploy ---------------------------------------------------------------
$include = @("$moduleName.psd1", "$moduleName.psm1", 'Public', 'Private', 'README.md')

foreach ($t in $targets) {
    if (-not $PSCmdlet.ShouldProcess($t.Path, "Deploy $moduleName $version ($($t.Edition))")) { continue }

    if (Test-Path -LiteralPath $t.Path) { Remove-Item -LiteralPath $t.Path -Recurse -Force }
    New-Item -ItemType Directory -Path $t.Path -Force | Out-Null

    foreach ($item in $include) {
        $src = Join-Path $root $item
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $t.Path -Recurse -Force }
    }
    Write-Host "Deployed $($t.Edition) -> $($t.Path)" -ForegroundColor Green
}

if ($WhatIfPreference) { return }

Write-Host "`nDone. Open a new session and run: Import-Module $moduleName" -ForegroundColor Cyan
