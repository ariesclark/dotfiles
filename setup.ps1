#!/usr/bin/env pwsh
#
# setup.ps1 - provision Windows-side tooling for these dotfiles.
#   irm https://raw.githubusercontent.com/ariesclark/dotfiles/main/setup.ps1 | iex
#
# Companion to setup.sh, which provisions WSL/Linux. Re-run any time; steps are idempotent.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info { param([string]$Message) Write-Host "> $Message" -ForegroundColor DarkGray }
function Write-Done { param([string]$Message) Write-Host "+ $Message" -ForegroundColor Green }
function Write-Fail { param([string]$Message) Write-Host "x $Message" -ForegroundColor Red; exit 1 }

function Test-Command { param([string]$Name) [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# winget edits the machine/user PATH in the registry, but the running process keeps its
# old copy. Re-read both so a freshly installed command resolves without a new shell.
function Update-Path {
    $machine = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = @($machine, $user | Where-Object { $_ }) -join ';'
}

function Install-OnePasswordCli {
    Update-Path
    $present = Test-Command op

    # Update through winget, not `op update`: the built-in updater is interactive and hangs
    # under non-interactive WSL interop. winget's --silent install/upgrade handles elevation.
    if (-not (Test-Command winget)) {
        if ($present) {
            Write-Done "1Password ready ($(op --version)); no winget, skipping update"
            return
        }
        Write-Fail "winget not found. install 'App Installer' from the Microsoft Store and re-run. manual install: https://www.1password.dev/cli/get-started"
    }

    if ($present) {
        Write-Info "updating 1Password"
        winget upgrade --exact --id AgileBits.1Password.CLI --source winget `
            --accept-source-agreements --accept-package-agreements --silent
    } else {
        Write-Info "installing 1Password"
        winget install --exact --id AgileBits.1Password.CLI --source winget `
            --accept-source-agreements --accept-package-agreements --silent
    }

    # Judge success by whether 'op' resolves, not winget's exit code: an up-to-date package
    # makes upgrade/install return a non-zero "no upgrade" code even though it is present.
    Update-Path
    if (Test-Command op) {
        Write-Done "1Password ready ($(op --version)) ♡"
    } else {
        Write-Fail "winget ran but op still not found (exit $LASTEXITCODE)"
    }
}

Install-OnePasswordCli
