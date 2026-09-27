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
    $arguments = @($args)
    $first = if ($arguments.Count -gt 0) { [string]$arguments[0] } else { '' }
    if ($first -eq 'default') {
        if ($arguments.Count -ne 1) { Throw-AgentShellError 'Usage: agentshell default' }
        Restore-AgentShellActivation
        if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_ACCOUNT)) {
            foreach ($name in @('CODEX_API_KEY','CODEX_ACCESS_TOKEN','OPENAI_API_KEY',
                'ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_OAUTH_TOKEN',
                'GEMINI_API_KEY','GOOGLE_API_KEY','GOOGLE_APPLICATION_CREDENTIALS',
                'COPILOT_GITHUB_TOKEN','GH_TOKEN','GITHUB_TOKEN')) {
                [Environment]::SetEnvironmentVariable($name, $null, 'Process')
            }
        }
        foreach ($name in @('AGENT_SHELL_ACCOUNT','AGENT_SHELL_PROFILE_ROOT','AGENT_SHELL_PROFILE_ENV',
            'AGENT_SHELL_CODEX_HISTORY_MODE','AGENT_SHELL_CODEX_SQLITE_HOME','AGENT_SHELL_CODEX_HOME',
            'CODEX_SQLITE_HOME','CODEX_SESSION_ID','CODEX_THREAD_ID','CODEX_CI',
            'CLAUDE_CONFIG_DIR','GEMINI_CLI_HOME','COPILOT_HOME','COPILOT_CACHE_HOME')) {
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
        $env:CODEX_HOME = if ($env:AGENT_SHELL_BASE_CODEX_HOME) { $env:AGENT_SHELL_BASE_CODEX_HOME } else { Join-Path $HOME '.codex' }
        $global:AgentShellActivationState = $null
        $global:LASTEXITCODE = 0
        [Console]::Error.WriteLine("AgentShell: ordinary Codex at $env:CODEX_HOME (current shell)")
        return
    }
    if ($first -eq 'deactivate') {
        if ($arguments.Count -ne 1) { Throw-AgentShellError 'Usage: agentshell deactivate' }
        Restore-AgentShellActivation
        $global:AgentShellActivationState = $null
        $global:LASTEXITCODE = 0
        return
    }
    if ($first -eq 'activate') {
        if ($arguments.Count -ne 2) { Throw-AgentShellError 'Usage: agentshell activate ACCOUNT' }
        Set-AgentShellActiveAccount ([string]$arguments[1])
        return
    }
    if ($first -in @('', '-h', '--help', 'help', '-v', '--version', 'status', 'profile', 'run')) {
        Invoke-AgentShellRuntimeFromProfile 'agentshell' $arguments
        return
    }
    $parsed = Split-AgentShellAccountOption $arguments
    $account = $parsed.Account
    $remaining = @($parsed.Remaining)
    if (-not $parsed.WasSpecified) {
        $account = $first
        $remaining = @(if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] })
    }
    if ($remaining.Count -eq 1 -and $remaining[0] -eq '--') { $remaining = @() }
    if ($remaining.Count -eq 0) {
        Set-AgentShellActiveAccount $account
    } else {
        Invoke-AgentShellRuntimeFromProfile 'agentshell' $arguments
    }
}

if ($null -eq (Get-Variable AgentShellActivationState -Scope Global -ErrorAction SilentlyContinue)) {
    $global:AgentShellActivationState = $null
}

function Restore-AgentShellActivation {
    $state = $global:AgentShellActivationState
    if ($null -eq $state) { return }
    foreach ($name in $state.Changed) {
        $current = [Environment]::GetEnvironmentVariable($name, 'Process')
        # Keep subsequent user changes such as conda's PATH update.
        if ($current -cne $state.Applied[$name]) { continue }
        [Environment]::SetEnvironmentVariable($name, $state.Before[$name], 'Process')
    }
}

function Set-AgentShellActiveAccount {
    param([Parameter(Mandatory = $true)][string]$Account)
    $current = Save-AgentShellEnvironment
    $location = Get-Location
    try {
        Restore-AgentShellActivation
        $before = Save-AgentShellEnvironment
        [void](Set-AgentShellProfileEnvironment $Account)
        # Account environment files cannot change the caller's home identity.
        foreach ($name in @('HOME', 'USERPROFILE')) {
            [Environment]::SetEnvironmentVariable($name, $before[$name], 'Process')
        }
        $after = Save-AgentShellEnvironment
        $changed = @(@($before.Keys) + @($after.Keys) | Sort-Object -Unique |
            Where-Object { $before[$_] -cne $after[$_] })
        $global:AgentShellActivationState = [PSCustomObject]@{
            Before = $before
            Applied = $after
            Changed = $changed
        }
        $global:LASTEXITCODE = 0
        [Console]::Error.WriteLine("AgentShell account $Account (current shell)")
    } catch {
        Restore-AgentShellEnvironment $current
        throw
    } finally {
        Set-Location -LiteralPath $location.Path
    }
}

if ($null -eq (Get-Command cr -ErrorAction SilentlyContinue)) {
    Set-Alias -Name cr -Value codexr -Scope Global
}

function global:prompt {
        $prefix = if ([string]::IsNullOrWhiteSpace($env:AGENT_SHELL_ACCOUNT)) { '' } else { "[agent:$env:AGENT_SHELL_ACCOUNT] " }
        $base = $global:AgentShellPowerShellState.BasePrompt
        if ($null -ne $base) { return $prefix + ((& $base) -replace '\[agent:[A-Za-z0-9._-]+\] ', '') }
        return $prefix + 'PS ' + (Get-Location).Path + '> '
}
