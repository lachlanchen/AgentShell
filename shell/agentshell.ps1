# PowerShell integration for AgentShell.
# Only a leading --account/--project selector changes routing. Ordinary calls
# continue through the commands that existed before this helper was loaded.

Set-StrictMode -Version 2.0

$agentShellDataHome = if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_HOME)) {
    [IO.Path]::GetFullPath($env:AGENT_SHELL_HOME)
} else {
    [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'AgentShell'))
}
$agentShellRuntime = if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_RUNTIME)) {
    [IO.Path]::GetFullPath($env:AGENT_SHELL_RUNTIME)
} elseif (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_INSTALL_ROOT)) {
    Join-Path ([IO.Path]::GetFullPath($env:AGENT_SHELL_INSTALL_ROOT)) 'agentshell.ps1'
} else {
    Join-Path $agentShellDataHome 'lib\agentshell.ps1'
}
$agentShellBin = if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_BIN_DIR)) {
    [IO.Path]::GetFullPath($env:AGENT_SHELL_BIN_DIR)
} else {
    Join-Path $agentShellDataHome 'bin'
}

if (-not (Test-Path -LiteralPath $agentShellRuntime -PathType Leaf)) {
    throw "AgentShell runtime not found: $agentShellRuntime"
}

if (($env:Path -split ';') -notcontains $agentShellBin) {
    $env:Path = "$agentShellBin;$env:Path"
}

# Load the runtime as a function library. The script's dispatcher is disabled
# by -Library, so sourcing it cannot launch a command or change account state.
. $agentShellRuntime -Library

function Get-AgentShellCommandCapture {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) { return $null }

    if ($command.CommandType -eq [Management.Automation.CommandTypes]::Alias) {
        $command = Get-Command $command.Definition -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $command) { return $null }
    }

    if ($command.CommandType -eq [Management.Automation.CommandTypes]::Function -or
        $command.CommandType -eq [Management.Automation.CommandTypes]::Filter) {
        return [PSCustomObject]@{
            Kind = 'ScriptBlock'
            Value = $command.ScriptBlock
            Source = $Name
        }
    }

    if ($command.CommandType -eq [Management.Automation.CommandTypes]::Application -or
        $command.CommandType -eq [Management.Automation.CommandTypes]::ExternalScript) {
        return [PSCustomObject]@{
            Kind = 'Path'
            Value = [string]$command.Source
            Source = $Name
        }
    }

    return $null
}

if ($null -eq (Get-Variable -Name AgentShellPowerShellState -Scope Global -ErrorAction SilentlyContinue)) {
    $captures = @{}
    foreach ($tool in @('codex', 'codexr', 'codexmv', 'claude', 'gemini', 'copilot')) {
        $captures[$tool] = Get-AgentShellCommandCapture $tool
    }
    $promptCommand = Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue
    $global:AgentShellPowerShellState = [PSCustomObject]@{
        Commands = $captures
        BasePrompt = if ($null -ne $promptCommand) { $promptCommand.ScriptBlock } else { $null }
    }
}

# PowerShell resolves aliases before functions. Remove only aliases whose
# targets were captured above, then replace them with routing functions that
# preserve the captured ordinary behavior.
foreach ($tool in @('codex', 'codexr', 'codexmv', 'claude', 'gemini', 'copilot')) {
    if ($null -ne (Get-Alias $tool -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath ('Alias:\' + $tool) -Force
    }
}

function Invoke-AgentShellCapturedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [object[]]$Arguments = @()
    )

    $capture = $global:AgentShellPowerShellState.Commands[$Tool]
    if ($null -eq $capture -and $Tool -eq 'codexr') {
        $capture = $global:AgentShellPowerShellState.Commands['codex']
        if ($null -ne $capture) { $Arguments = @('resume') + @($Arguments) }
    }
    if ($null -eq $capture) {
        Throw-AgentShellError "ordinary command was not available before integration loaded: $Tool"
    }

    if ($capture.Kind -eq 'ScriptBlock') {
        & $capture.Value @Arguments
    } else {
        & $capture.Value @Arguments
    }
}

function Invoke-AgentShellSelectedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Account,
        [Parameter(Mandatory = $true)][string]$Tool,
        [object[]]$Arguments = @()
    )

    $snapshot = Save-AgentShellEnvironment
    try {
        [void](Set-AgentShellProfileEnvironment $Account)
        Invoke-AgentShellCapturedCommand $Tool $Arguments
    } finally {
        Restore-AgentShellEnvironment $snapshot
    }
}

function Invoke-AgentShellIntegratedTool {
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [object[]]$Arguments = @()
    )

    $parsed = Split-AgentShellAccountOption $Arguments
    if ($parsed.WasSpecified) {
        Invoke-AgentShellSelectedCommand $parsed.Account $Tool $parsed.Remaining
    } else {
        Invoke-AgentShellCapturedCommand $Tool $Arguments
    }
}

function Invoke-AgentShellRuntimeFromProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$Arguments = @()
    )

    # Keep output attached to this console so nested shells and AI TUIs remain
    # interactive. Process-style exit status travels out-of-band.
    $script:AgentShellExitCode = 0
    Invoke-AgentShellRuntime $Name $Arguments
    $global:LASTEXITCODE = [int]$script:AgentShellExitCode
}

function global:codex {
    Invoke-AgentShellIntegratedTool 'codex' @($args)
}

function global:codexr {
    Invoke-AgentShellIntegratedTool 'codexr' @($args)
}

function global:codexmv {
    Invoke-AgentShellIntegratedTool 'codexmv' @($args)
}

foreach ($provider in @('claude', 'gemini', 'copilot')) {
    if ($null -ne $global:AgentShellPowerShellState.Commands[$provider]) {
        $definition = [ScriptBlock]::Create("Invoke-AgentShellIntegratedTool '$provider' @(`$args)")
        Set-Item -LiteralPath ('Function:\global:' + $provider) -Value $definition
    }
}

function global:agentshell {
    Invoke-AgentShellRuntimeFromProfile 'agentshell' @($args)
}

if ($null -eq (Get-Command cr -ErrorAction SilentlyContinue)) {
    Set-Alias -Name cr -Value codexr -Scope Global
}

if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_ACCOUNT)) {
    function global:prompt {
        $prefix = if ([string]::IsNullOrWhiteSpace($env:AGENT_SHELL_ACCOUNT)) { '' } else { "[agent:$env:AGENT_SHELL_ACCOUNT] " }
        $base = $global:AgentShellPowerShellState.BasePrompt
        if ($null -ne $base) { return $prefix + (& $base) }
        return $prefix + 'PS ' + (Get-Location).Path + '> '
    }
}
