# Named, account-isolated shells for Codex and other AI command-line tools.
# Compatible with Windows PowerShell 5.1.

param(
    [string]$InvocationName = 'agentshell',
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$ArgumentList = @(),
    [switch]$Library
)

Set-StrictMode -Version 2.0

$script:AgentShellVersion = '0.4.0'
$script:AgentShellExitCode = 0
$script:AgentShellRuntimePath = $PSCommandPath
$script:AgentShellDataHome = if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_HOME)) {
    [IO.Path]::GetFullPath($env:AGENT_SHELL_HOME)
} else {
    [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'AgentShell'))
}
$script:AgentShellProfilesDirectory = Join-Path $script:AgentShellDataHome 'profiles'
$script:AgentShellBinDirectory = if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_BIN_DIR)) {
    [IO.Path]::GetFullPath($env:AGENT_SHELL_BIN_DIR)
} else {
    Join-Path $script:AgentShellDataHome 'bin'
}
$script:AgentShellProfileTools = @('codex', 'codexr', 'codexmv', 'claude', 'gemini', 'copilot')
$script:AgentShellAuthVariables = @(
    'CODEX_API_KEY', 'CODEX_ACCESS_TOKEN', 'OPENAI_API_KEY',
    'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN',
    'GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_APPLICATION_CREDENTIALS',
    'COPILOT_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN',
    'CODEX_SESSION_ID', 'CODEX_THREAD_ID', 'CODEX_CI'
)
$script:AgentShellUtf8NoBom = New-Object Text.UTF8Encoding($false)
$script:AgentShellUtf8Bom = New-Object Text.UTF8Encoding($true)

function Write-AgentShellError {
    param([string]$Message)
    [Console]::Error.WriteLine('AgentShell error: ' + $Message)
}

function Throw-AgentShellError {
    param([string]$Message)
    throw ('AgentShell error: ' + $Message)
}

function Show-AgentShellUsage {
    @'
AgentShell - separate AI CLI accounts by named terminal profile

Usage:
  agentshell ACCOUNT
  agentshell --account ACCOUNT [-- COMMAND [ARG...]]
  agentshell -v | status [ACCOUNT]
  agent-run --account ACCOUNT TOOL [ARG...]
  agent-profile create|list|show|status|login|aliases ACCOUNT [TOOL]
  agent-profile history ACCOUNT [private|shared]
  agent-profile sessions [ACCOUNT]
  agent-profile codex-home ACCOUNT [ROLLOUT_PATH]

Codex shortcuts after PowerShell integration is loaded:
  codex   --account ACCOUNT [CODEX_ARG...]
  codexr  --account ACCOUNT [RESUME_ARG...]
  codexmv --account ACCOUNT [MOVE_ARG...]

The current working directory is preserved. AgentShell changes provider state
locations; it is not a filesystem or OS security container.
'@ | Write-Output
}

function Test-AgentShellProfileName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or $Name.EndsWith('.')) {
        Throw-AgentShellError "invalid account name '$Name' (use 1-64 letters, numbers, dots, underscores, or hyphens)"
    }

    $deviceBase = ($Name -split '\.')[0]
    if ($deviceBase -match '^(?i:CON|PRN|AUX|NUL|CLOCK\$|COM[1-9]|LPT[1-9])$') {
        Throw-AgentShellError "invalid Windows device account name '$Name'"
    }

    if (Test-Path -LiteralPath $script:AgentShellProfilesDirectory -PathType Container) {
        $collision = Get-ChildItem -LiteralPath $script:AgentShellProfilesDirectory -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $Name -and $_.Name -cne $Name } |
            Select-Object -First 1
        if ($null -ne $collision) {
            Throw-AgentShellError "account '$Name' differs only by case from existing account '$($collision.Name)'"
        }
    }

    return $true
}

function Get-AgentShellProfileRoot {
    param([Parameter(Mandatory = $true)][string]$Name)
    [void](Test-AgentShellProfileName $Name)
    return Join-Path $script:AgentShellProfilesDirectory $Name
}

function Get-AgentShellBaseCodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_BASE_CODEX_HOME)) {
        return [IO.Path]::GetFullPath($env:AGENT_SHELL_BASE_CODEX_HOME)
    }
    return Join-Path $HOME '.codex'
}

function Get-AgentShellSharedSqliteHome {
    if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_SHARED_CODEX_SQLITE_HOME)) {
        return [IO.Path]::GetFullPath($env:AGENT_SHELL_SHARED_CODEX_SQLITE_HOME)
    }
    return Get-AgentShellBaseCodexHome
}

function Get-AgentShellSharedCodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_SHARED_CODEX_HOME)) {
        return [IO.Path]::GetFullPath($env:AGENT_SHELL_SHARED_CODEX_HOME)
    }
    return Get-AgentShellSharedSqliteHome
}

function Get-AgentShellProfileValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Key,
        [string]$Fallback = ''
    )

    $config = Join-Path (Get-AgentShellProfileRoot $Name) 'profile.conf'
    if (Test-Path -LiteralPath $config -PathType Leaf) {
        foreach ($line in [IO.File]::ReadAllLines($config)) {
            $separator = $line.IndexOf('=')
            if ($separator -gt 0 -and $line.Substring(0, $separator) -ceq $Key) {
                $value = $line.Substring($separator + 1)
                if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
            }
        }
    }
    return $Fallback
}

function Set-AgentShellProfileValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $root = Get-AgentShellProfileRoot $Name
    $config = Join-Path $root 'profile.conf'
    $lines = New-Object Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($config)) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0 -and $line.Substring(0, $separator) -ceq $Key) { continue }
        $lines.Add($line)
    }
    $lines.Add($Key + '=' + $Value)
    $temporary = Join-Path $root ('.profile.conf.' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllLines($temporary, $lines.ToArray(), $script:AgentShellUtf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $config -Force
}

function Get-AgentShellHistoryMode {
    param([Parameter(Mandatory = $true)][string]$Name)
    $mode = Get-AgentShellProfileValue $Name 'codex_history' 'private'
    if ($mode -notin @('private', 'shared')) { return 'private' }
    return $mode
}

function Get-AgentShellSqliteHome {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ((Get-AgentShellHistoryMode $Name) -eq 'shared') {
        return Get-AgentShellSharedSqliteHome
    }
    return Join-Path (Get-AgentShellProfileRoot $Name) 'codex-home'
}

function New-AgentShellSharedItem {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source) -or (Test-Path -LiteralPath $Destination)) { return }
    try {
        if (Test-Path -LiteralPath $Source -PathType Container) {
            New-Item -ItemType Junction -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
        } else {
            New-Item -ItemType HardLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Warning "AgentShell kept customization private because it could not link '$Source': $($_.Exception.Message)"
    }
}

function Copy-AgentShellCodexConfig {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf) -or (Test-Path -LiteralPath $Destination)) { return }
    $lines = @([IO.File]::ReadAllLines($Source) | Where-Object { $_ -notmatch '^\s*sqlite_home\s*=' })
    [IO.File]::WriteAllLines($Destination, $lines, $script:AgentShellUtf8NoBom)
}

function Test-AgentShellPathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return $resolvedPath.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Get-AgentShellHistoryHomeForRollout {
    param([Parameter(Mandatory = $true)][string]$RolloutPath)

    $candidates = New-Object Collections.Generic.List[string]
    $candidates.Add((Get-AgentShellSharedCodexHome))
    if (Test-Path -LiteralPath $script:AgentShellProfilesDirectory -PathType Container) {
        foreach ($profile in @(Get-ChildItem -LiteralPath $script:AgentShellProfilesDirectory -Directory -Force)) {
            $candidate = Join-Path $profile.FullName 'codex-home'
            if (Test-Path -LiteralPath $candidate -PathType Container) { $candidates.Add($candidate) }
        }
    }

    foreach ($candidate in $candidates) {
        if ((Test-AgentShellPathWithin $RolloutPath (Join-Path $candidate 'sessions')) -or
            (Test-AgentShellPathWithin $RolloutPath (Join-Path $candidate 'archived_sessions'))) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    return [IO.Path]::GetFullPath((Get-AgentShellSharedCodexHome))
}

function Initialize-AgentShellSharedAccountState {
    param([Parameter(Mandatory = $true)][string]$Name)

    $root = Get-AgentShellProfileRoot $Name
    $identity = Join-Path $root 'codex-home'
    $accountView = Join-Path $root 'codex-shared-home'
    $marker = Join-Path $accountView '.account-state-v1'
    New-Item -ItemType Directory -Force -Path $identity, $accountView | Out-Null

    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
        foreach ($item in @('auth.json', 'config.toml', 'installation_id', 'internal_storage.json')) {
            $source = Join-Path $identity $item
            $destination = Join-Path $accountView $item
            if ((Test-Path -LiteralPath $source -PathType Leaf) -and -not (Test-Path -LiteralPath $destination)) {
                Copy-Item -LiteralPath $source -Destination $destination
            }
        }
        [IO.File]::WriteAllText($marker, '', $script:AgentShellUtf8NoBom)
    }

    foreach ($item in @('AGENTS.md', 'skills', 'plugins', 'rules')) {
        New-AgentShellSharedItem (Join-Path $identity $item) (Join-Path $accountView $item)
    }
    return $accountView
}

function Initialize-AgentShellCodexView {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$HistoryHome,
        [Parameter(Mandatory = $true)][string]$View
    )

    $historyHomeFull = [IO.Path]::GetFullPath($HistoryHome)
    $accountView = Initialize-AgentShellSharedAccountState $Name
    New-Item -ItemType Directory -Force -Path $historyHomeFull, $View | Out-Null
    $historyMarker = Join-Path $View '.history-root-v1'
    $pendingMarker = Join-Path $View '.history-root-v1.pending'
    $viewOwned = Test-Path -LiteralPath $historyMarker -PathType Leaf
    if ($viewOwned) {
        $recorded = [IO.File]::ReadAllText($historyMarker).Trim()
        if (-not [string]::Equals([IO.Path]::GetFullPath($recorded), $historyHomeFull, [StringComparison]::OrdinalIgnoreCase)) {
            Throw-AgentShellError "history view points at an unexpected root: $View"
        }
    } elseif (Test-Path -LiteralPath $pendingMarker -PathType Leaf) {
        $recorded = [IO.File]::ReadAllText($pendingMarker).Trim()
        if (-not [string]::Equals([IO.Path]::GetFullPath($recorded), $historyHomeFull, [StringComparison]::OrdinalIgnoreCase)) {
            Throw-AgentShellError "incomplete history view points at an unexpected root: $View"
        }
        $viewOwned = $true
    } else {
        foreach ($item in @('sessions', 'archived_sessions', 'attachments', 'generated_images', 'shell_snapshots', 'thread-writer-locks', 'history.jsonl', 'session_index.jsonl')) {
            if (Test-Path -LiteralPath (Join-Path $View $item)) {
                Throw-AgentShellError "refusing existing unowned history path: $(Join-Path $View $item)"
            }
        }
        [IO.File]::WriteAllText($pendingMarker, $historyHomeFull, $script:AgentShellUtf8NoBom)
        $viewOwned = $true
    }

    foreach ($item in @('sessions', 'archived_sessions', 'attachments', 'generated_images', 'shell_snapshots', 'thread-writer-locks')) {
        $source = Join-Path $historyHomeFull $item
        $destination = Join-Path $View $item
        New-Item -ItemType Directory -Force -Path $source | Out-Null
        if (Test-Path -LiteralPath $destination) {
            if (-not $viewOwned) { Throw-AgentShellError "refusing existing unowned history path: $destination" }
        } else {
            New-Item -ItemType Junction -Path $destination -Target $source -ErrorAction Stop | Out-Null
        }
    }

    foreach ($item in @('history.jsonl', 'session_index.jsonl')) {
        $source = Join-Path $historyHomeFull $item
        $destination = Join-Path $View $item
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            [IO.File]::WriteAllText($source, '', $script:AgentShellUtf8NoBom)
        }
        if (Test-Path -LiteralPath $destination) {
            if (-not $viewOwned) { Throw-AgentShellError "refusing existing unowned history file: $destination" }
        } else {
            New-Item -ItemType HardLink -Path $destination -Target $source -ErrorAction Stop | Out-Null
        }
    }

    if (-not [string]::Equals([IO.Path]::GetFullPath($View), [IO.Path]::GetFullPath($accountView), [StringComparison]::OrdinalIgnoreCase)) {
        foreach ($item in @('auth.json', 'config.toml', 'installation_id', 'internal_storage.json', 'AGENTS.md', 'skills', 'plugins', 'rules')) {
            New-AgentShellSharedItem (Join-Path $accountView $item) (Join-Path $View $item)
        }
    }
    [IO.File]::WriteAllText($historyMarker, $historyHomeFull, $script:AgentShellUtf8NoBom)
    Remove-Item -LiteralPath $pendingMarker -Force -ErrorAction SilentlyContinue
}

function Get-AgentShellCodexHome {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$RolloutPath = ''
    )

    $root = Get-AgentShellProfileRoot $Name
    if ((Get-AgentShellHistoryMode $Name) -ne 'shared') {
        return Join-Path $root 'codex-home'
    }

    $sharedHome = [IO.Path]::GetFullPath((Get-AgentShellSharedCodexHome))
    $historyHome = if ([string]::IsNullOrWhiteSpace($RolloutPath)) {
        $sharedHome
    } else {
        Get-AgentShellHistoryHomeForRollout $RolloutPath
    }
    if ([string]::Equals([IO.Path]::GetFullPath($historyHome), $sharedHome, [StringComparison]::OrdinalIgnoreCase)) {
        $view = Join-Path $root 'codex-shared-home'
    } else {
        $sourceName = Split-Path (Split-Path $historyHome -Parent) -Leaf
        [void](Test-AgentShellProfileName $sourceName)
        $view = Join-Path (Join-Path $root 'codex-history-views') $sourceName
    }
    Initialize-AgentShellCodexView $Name $historyHome $view
    return $view
}

function Write-AgentShellCommandShim {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][string]$RuntimePath
    )

    New-Item -ItemType Directory -Force -Path $script:AgentShellBinDirectory | Out-Null
    $escapedRuntime = $RuntimePath.Replace("'", "''")
    $escapedInvocation = $CommandName.Replace("'", "''")
    $psPath = Join-Path $script:AgentShellBinDirectory ($CommandName + '.ps1')
    $psContent = @"
# Generated by AgentShell. Do not edit this shim.
param([Parameter(ValueFromRemainingArguments=`$true)][object[]]`$Arguments)
& '$escapedRuntime' -InvocationName '$escapedInvocation' -ArgumentList `$Arguments
if (`$null -ne `$LASTEXITCODE) { exit `$LASTEXITCODE }
"@
    if (Test-Path -LiteralPath $psPath -PathType Leaf) {
        $existing = [IO.File]::ReadAllText($psPath)
        if (-not $existing.StartsWith('# Generated by AgentShell.')) {
            Throw-AgentShellError "refusing to replace unrelated command: $psPath"
        }
    }
    # Windows PowerShell 5.1 requires a BOM to decode non-ASCII paths safely.
    [IO.File]::WriteAllText($psPath, $psContent, $script:AgentShellUtf8Bom)

    $cmdPath = Join-Path $script:AgentShellBinDirectory ($CommandName + '.cmd')
    $cmdContent = "@echo off`r`nrem Generated by AgentShell. Do not edit this shim.`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0$CommandName.ps1`" %*`r`n"
    if (Test-Path -LiteralPath $cmdPath -PathType Leaf) {
        $existingCmd = [IO.File]::ReadAllText($cmdPath)
        if ($existingCmd -notmatch '(?i)\A@echo off\r?\nrem Generated by AgentShell\.') {
            Throw-AgentShellError "refusing to replace unrelated command: $cmdPath"
        }
    }
    [IO.File]::WriteAllText($cmdPath, $cmdContent, [Text.Encoding]::ASCII)
}

function Install-AgentShellProfileAliases {
    param([Parameter(Mandatory = $true)][string]$Name)
    foreach ($tool in $script:AgentShellProfileTools) {
        Write-AgentShellCommandShim -CommandName ("agent-$Name-$tool") -RuntimePath $script:AgentShellRuntimePath
    }
}

function Initialize-AgentShellProfile {
    param([Parameter(Mandatory = $true)][string]$Name)

    [void](Test-AgentShellProfileName $Name)
    New-Item -ItemType Directory -Force -Path $script:AgentShellProfilesDirectory | Out-Null
    $root = Get-AgentShellProfileRoot $Name
    $created = -not (Test-Path -LiteralPath $root -PathType Container)
    foreach ($directory in @(
        $root,
        (Join-Path $root 'codex-home'),
        (Join-Path $root 'claude-home'),
        (Join-Path $root 'gemini-home\.gemini'),
        (Join-Path $root 'copilot-home'),
        (Join-Path $root 'cache\copilot')
    )) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $config = Join-Path $root 'profile.conf'
    $envFile = Join-Path $root 'env.ps1'
    if ($created) {
        $configLines = @(
            'name=' + $Name,
            'format_version=1',
            'created_at=' + [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'),
            'codex_history=private'
        )
        [IO.File]::WriteAllLines($config, $configLines, $script:AgentShellUtf8NoBom)
        [IO.File]::WriteAllText($envFile, "# Optional private account-specific environment variables.`r`n# Prefer browser login. Do not commit credentials from this file.`r`n", $script:AgentShellUtf8Bom)
    } else {
        if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
            Throw-AgentShellError "existing account is missing profile.conf: $root"
        }
        if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
            [IO.File]::WriteAllText($envFile, "# Optional private account-specific environment variables.`r`n", $script:AgentShellUtf8Bom)
        }
    }

    $baseCodex = Get-AgentShellBaseCodexHome
    Copy-AgentShellCodexConfig (Join-Path $baseCodex 'config.toml') (Join-Path $root 'codex-home\config.toml')
    foreach ($item in @('AGENTS.md', 'skills', 'plugins', 'rules')) {
        New-AgentShellSharedItem (Join-Path $baseCodex $item) (Join-Path $root ('codex-home\' + $item))
    }
    Install-AgentShellProfileAliases $Name

    if ($created) {
        [Console]::Error.WriteLine("Created AgentShell account: $Name")
        [Console]::Error.WriteLine("  state: $root")
    }
    return $root
}

function Save-AgentShellEnvironment {
    $snapshot = @{}
    foreach ($entry in Get-ChildItem Env:) {
        $snapshot[$entry.Name] = $entry.Value
    }
    return $snapshot
}

function Restore-AgentShellEnvironment {
    param([Parameter(Mandatory = $true)][hashtable]$Snapshot)
    foreach ($entry in @(Get-ChildItem Env:)) {
        if (-not $Snapshot.ContainsKey($entry.Name)) {
            [Environment]::SetEnvironmentVariable($entry.Name, $null, 'Process')
        }
    }
    foreach ($name in $Snapshot.Keys) {
        [Environment]::SetEnvironmentVariable($name, [string]$Snapshot[$name], 'Process')
    }
}

function Set-AgentShellProfileEnvironment {
    param([Parameter(Mandatory = $true)][string]$Name)

    $root = Initialize-AgentShellProfile $Name
    $envFile = Join-Path $root 'env.ps1'
    $historyMode = Get-AgentShellHistoryMode $Name
    $sqliteHome = Get-AgentShellSqliteHome $Name
    $codexHome = Get-AgentShellCodexHome $Name
    New-Item -ItemType Directory -Force -Path $sqliteHome | Out-Null

    if ($env:AGENT_SHELL_PRESERVE_AUTH_ENV -ne '1') {
        foreach ($variable in $script:AgentShellAuthVariables) {
            [Environment]::SetEnvironmentVariable($variable, $null, 'Process')
        }
    }
    if (Test-Path -LiteralPath $envFile -PathType Leaf) {
        & $envFile
    }

    $values = @{
        AGENT_SHELL_ACCOUNT = $Name
        AGENT_SHELL_PROFILE_ROOT = $root
        AGENT_SHELL_PROFILE_ENV = $envFile
        AGENT_SHELL_CODEX_HISTORY_MODE = $historyMode
        AGENT_SHELL_CODEX_SQLITE_HOME = $sqliteHome
        AGENT_SHELL_CODEX_HOME = $codexHome
        CODEX_HOME = $codexHome
        CODEX_SQLITE_HOME = $sqliteHome
        CLAUDE_CONFIG_DIR = (Join-Path $root 'claude-home')
        GEMINI_CLI_HOME = (Join-Path $root 'gemini-home')
        COPILOT_HOME = (Join-Path $root 'copilot-home')
        COPILOT_CACHE_HOME = (Join-Path $root 'cache\copilot')
    }
    foreach ($entry in $values.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }

    return [PSCustomObject]@{
        Name = $Name
        Root = $root
        HistoryMode = $historyMode
        SqliteHome = $sqliteHome
        CodexHome = $codexHome
    }
}

function Resolve-AgentShellNativeCommand {
    param([Parameter(Mandatory = $true)][string]$Name)

    $commands = @(Get-Command $Name -CommandType Application, ExternalScript -All -ErrorAction SilentlyContinue)
    foreach ($command in $commands) {
        $source = [string]$command.Source
        if ([string]::IsNullOrWhiteSpace($source)) { continue }
        $fullSource = [IO.Path]::GetFullPath($source)
        if ($fullSource -ieq [IO.Path]::GetFullPath($script:AgentShellRuntimePath)) { continue }
        if ($fullSource.StartsWith([IO.Path]::GetFullPath($script:AgentShellBinDirectory) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { continue }
        return $fullSource
    }
    return $null
}

function Invoke-AgentShellNative {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [object[]]$Arguments = @()
    )
    $global:LASTEXITCODE = $null
    & $Command @Arguments
    $script:AgentShellExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
}

function Invoke-AgentShellTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Tool,
        [object[]]$Arguments = @()
    )

    $snapshot = Save-AgentShellEnvironment
    try {
        $profile = Set-AgentShellProfileEnvironment $Name
        if ($env:AGENT_SHELL_QUIET -ne '1' -and -not [Console]::IsErrorRedirected) {
            [Console]::Error.WriteLine("AgentShell [$Name] - $Tool - history=$($profile.HistoryMode) - cwd=$((Get-Location).Path)")
            if ($Tool -in @('codex', 'codexr') -and $profile.HistoryMode -eq 'private') {
                [Console]::Error.WriteLine("Private history hides earlier base/account sessions. Locate them: agent-profile sessions $Name")
            }
        }

        $command = $null
        $toolArguments = @($Arguments)
        $wrapperEnabled = if ([string]::IsNullOrWhiteSpace($env:AGENT_SHELL_USE_CODEX_WRAPPER)) { '1' } else { $env:AGENT_SHELL_USE_CODEX_WRAPPER }
        $wrapperPath = if (-not [string]::IsNullOrWhiteSpace($env:AGENT_SHELL_CODEX_WRAPPER)) {
            $env:AGENT_SHELL_CODEX_WRAPPER
        } else {
            Join-Path $HOME 'scripts\codex_wrapper.ps1'
        }
        if ($Tool -in @('codex', 'codexr', 'codexmv') -and
            $wrapperEnabled -eq '1' -and
            (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) {
            $command = [IO.Path]::GetFullPath($wrapperPath)
            $toolArguments = @($Tool) + $toolArguments
        } else {
            switch ($Tool) {
                'codexr' {
                    $command = Resolve-AgentShellNativeCommand 'codexr'
                    if ($null -eq $command) {
                        $command = Resolve-AgentShellNativeCommand 'codex'
                        $toolArguments = @('resume') + $toolArguments
                    }
                }
                'codexmv' { $command = Resolve-AgentShellNativeCommand 'codexmv' }
                default { $command = Resolve-AgentShellNativeCommand $Tool }
            }
        }
        if ($null -eq $command) { Throw-AgentShellError "command not found: $Tool" }
        Invoke-AgentShellNative $command $toolArguments
    } finally {
        Restore-AgentShellEnvironment $snapshot
    }
}

function Split-AgentShellAccountOption {
    param([object[]]$Arguments = @())
    $result = [ordered]@{ Account = $null; Remaining = @($Arguments); WasSpecified = $false }
    if ($Arguments.Count -eq 0) { return [PSCustomObject]$result }
    $first = [string]$Arguments[0]
    if ($first -in @('--account', '--project')) {
        $result.WasSpecified = $true
        if ($Arguments.Count -lt 2 -or [string]::IsNullOrWhiteSpace([string]$Arguments[1])) {
            Throw-AgentShellError "$first requires a value"
        }
        $result.Account = [string]$Arguments[1]
        if ($Arguments.Count -gt 2) { $result.Remaining = @($Arguments[2..($Arguments.Count - 1)]) } else { $result.Remaining = @() }
    } elseif ($first -match '^--(?:account|project)=(.*)$') {
        $result.WasSpecified = $true
        if ([string]::IsNullOrWhiteSpace($Matches[1])) { Throw-AgentShellError (($first -split '=')[0] + ' requires a value') }
        $result.Account = $Matches[1]
        if ($Arguments.Count -gt 1) { $result.Remaining = @($Arguments[1..($Arguments.Count - 1)]) } else { $result.Remaining = @() }
    }
    return [PSCustomObject]$result
}

function Show-AgentShellProfile {
    param([Parameter(Mandatory = $true)][string]$Name)
    $root = Initialize-AgentShellProfile $Name
    $mode = Get-AgentShellHistoryMode $Name
    $sqliteHome = Get-AgentShellSqliteHome $Name
    $codexHome = Get-AgentShellCodexHome $Name
    @(
        "Account:       $Name",
        "Profile root:  $root",
        "Codex home:    $codexHome",
        "Account state: $(Join-Path $root 'codex-home')",
        "History mode:  $mode",
        "SQLite home:   $sqliteHome",
        "Claude home:   $(Join-Path $root 'claude-home')",
        "Gemini home:   $(Join-Path $root 'gemini-home')",
        "Copilot home:  $(Join-Path $root 'copilot-home')",
        "Working dir:   $((Get-Location).Path) (unchanged)",
        "Private env:   $(Join-Path $root 'env.ps1')"
    ) | Write-Output
    Show-AgentShellHistoryHint $Name
}

function Show-AgentShellHistoryHint {
    param([string]$Name)
    if ((Get-AgentShellHistoryMode $Name) -eq 'private') {
        "Private history hides earlier base/account sessions. Locate them: agent-profile sessions $Name"
    }
}

function Show-AgentShellSessionStore {
    param([string]$Label, [string]$Root)
    "${Label}: $Root"
    foreach ($item in @('sessions', 'archived_sessions')) {
        $path = Join-Path $Root $item
        $count = 0
        if (Test-Path -LiteralPath $path -PathType Container) {
            $count = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -Filter '*.jsonl' -ErrorAction Stop).Count
        }
        "  ${item}: $count rollout files"
    }
}

function Show-AgentShellSessions {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $env:AGENT_SHELL_ACCOUNT }
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        [void](Test-AgentShellProfileName $Name)
        if (-not (Test-Path -LiteralPath (Join-Path (Get-AgentShellProfileRoot $Name) 'profile.conf') -PathType Leaf)) {
            Throw-AgentShellError "unknown account: $Name"
        }
        "Account: $Name; configured history: $(Get-AgentShellHistoryMode $Name)"
    }
    $base = Get-AgentShellBaseCodexHome
    $shared = Get-AgentShellSharedCodexHome
    Show-AgentShellSessionStore 'Base Codex history' $base
    if (-not [string]::Equals([IO.Path]::GetFullPath($base), [IO.Path]::GetFullPath($shared), [StringComparison]::OrdinalIgnoreCase)) {
        Show-AgentShellSessionStore 'Configured shared history' $shared
    }
    if (Test-Path -LiteralPath $script:AgentShellProfilesDirectory -PathType Container) {
        foreach ($root in @(Get-ChildItem -LiteralPath $script:AgentShellProfilesDirectory -Directory -Force | Sort-Object Name)) {
            if (Test-Path -LiteralPath (Join-Path $root.FullName 'profile.conf') -PathType Leaf) {
                Show-AgentShellSessionStore "Private history ($($root.Name))" (Join-Path $root.FullName 'codex-home')
            }
        }
    }
    'Counts are saved rollout files (including agent threads), not picker entries. No histories were changed.'
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        "To use shared history with this account login: agent-profile history $Name shared"
        "Then launch: agent-codex --account $Name resume --all"
    }
}

function Show-AgentShellProfileList {
    '{0,-24} {1,-12} {2,-9} {3}' -f 'ACCOUNT', 'CODEX LOGIN', 'HISTORY', 'STATE'
    if (-not (Test-Path -LiteralPath $script:AgentShellProfilesDirectory -PathType Container)) { return }
    foreach ($directory in @(Get-ChildItem -LiteralPath $script:AgentShellProfilesDirectory -Directory -Force | Sort-Object Name)) {
        $codexHome = Get-AgentShellCodexHome $directory.Name
        $login = if (Test-Path -LiteralPath (Join-Path $codexHome 'auth.json') -PathType Leaf) { 'saved' } else { 'not logged in' }
        '{0,-24} {1,-12} {2,-9} {3}' -f $directory.Name, $login, (Get-AgentShellHistoryMode $directory.Name), $directory.FullName
    }
}

function Set-AgentShellHistoryMode {
    param([Parameter(Mandatory = $true)][string]$Name, [string]$Mode)
    [void](Initialize-AgentShellProfile $Name)
    if ([string]::IsNullOrWhiteSpace($Mode)) {
        Get-AgentShellHistoryMode $Name | Write-Output
        return
    }
    if ($Mode -notin @('private', 'shared')) { Throw-AgentShellError 'history mode must be private or shared' }
    Set-AgentShellProfileValue $Name 'codex_history' $Mode
    $sqliteHome = Get-AgentShellSqliteHome $Name
    $codexHome = Get-AgentShellCodexHome $Name
    New-Item -ItemType Directory -Force -Path $sqliteHome | Out-Null
    "AgentShell account $Name now uses $Mode Codex history."
    "SQLite home: $sqliteHome"
    "Codex home: $codexHome"
    "Existing sessions stay in their original store. Locate them: agent-profile sessions $Name"
    "Already-running shells and Codex sessions keep their environment. Relaunch: agent-codex --account $Name resume --all"
}

function Show-AgentShellStatus {
    param([string]$Name)
    "AgentShell $script:AgentShellVersion"
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $env:AGENT_SHELL_ACCOUNT }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        'Current account: none (ordinary shell)'
        'Tip: agentshell ACCOUNT, or agentshell status ACCOUNT'
        return
    }
    $root = Initialize-AgentShellProfile $Name
    $codexHome = Get-AgentShellCodexHome $Name
    $login = if (Test-Path -LiteralPath (Join-Path $codexHome 'auth.json') -PathType Leaf) { 'saved' } else { 'not logged in' }
    "Current account: $Name"
    "Codex login:    $login"
    "History mode:   $(Get-AgentShellHistoryMode $Name)"
    "Codex home:     $codexHome"
    "SQLite home:    $(Get-AgentShellSqliteHome $Name)"
    "Working dir:    $((Get-Location).Path)"
    Show-AgentShellHistoryHint $Name
}

function Invoke-AgentShellProfileCommand {
    param([object[]]$Arguments = @())
    $action = if ($Arguments.Count -gt 0) { [string]$Arguments[0] } else { '' }
    $name = if ($Arguments.Count -gt 1) { [string]$Arguments[1] } else { '' }
    $third = if ($Arguments.Count -gt 2) { [string]$Arguments[2] } else { '' }
    switch ($action) {
        { $_ -in @('-h', '--help', 'help', '') } { Show-AgentShellUsage; return }
        { $_ -in @('list', 'ls') } { Show-AgentShellProfileList; return }
        'sessions' { Show-AgentShellSessions $name; return }
        'create' { if ([string]::IsNullOrWhiteSpace($name)) { Throw-AgentShellError 'profile create requires ACCOUNT' }; Show-AgentShellProfile $name; return }
        'show' { if ([string]::IsNullOrWhiteSpace($name)) { Throw-AgentShellError 'profile show requires ACCOUNT' }; Show-AgentShellProfile $name; return }
        'history' { if ([string]::IsNullOrWhiteSpace($name)) { Throw-AgentShellError 'profile history requires ACCOUNT' }; Set-AgentShellHistoryMode $name $third; return }
        'codex-home' {
            if ([string]::IsNullOrWhiteSpace($name)) { Throw-AgentShellError 'profile codex-home requires ACCOUNT' }
            [void](Initialize-AgentShellProfile $name)
            Get-AgentShellCodexHome $name $third | Write-Output
            return
        }
        'aliases' {
            if ([string]::IsNullOrWhiteSpace($name)) { Throw-AgentShellError 'profile aliases requires ACCOUNT' }
            [void](Initialize-AgentShellProfile $name)
            foreach ($tool in $script:AgentShellProfileTools) { "agent-$name-$tool" }
            return
        }
        'status' {
            if ([string]::IsNullOrWhiteSpace($name)) { Throw-AgentShellError 'profile status requires ACCOUNT' }
            Show-AgentShellProfile $name
            $provider = if ([string]::IsNullOrWhiteSpace($third)) { 'codex' } else { $third }
            if ($provider -eq 'codex') { Invoke-AgentShellTool $name 'codex' @('login', 'status'); return }
            "$provider state is isolated under $(Join-Path (Get-AgentShellProfileRoot $name) ($provider + '-home'))."
            return
        }
        'login' {
            if ([string]::IsNullOrWhiteSpace($name)) { Throw-AgentShellError 'profile login requires ACCOUNT' }
            $provider = if ([string]::IsNullOrWhiteSpace($third)) { 'codex' } else { $third }
            if ($provider -eq 'codex') { Invoke-AgentShellTool $name 'codex' @('login'); return }
            Invoke-AgentShellTool $name $provider @()
            return
        }
        default { Throw-AgentShellError "unknown profile action: $action" }
    }
}

function Open-AgentShellPowerShell {
    param([Parameter(Mandatory = $true)][string]$Name)
    $snapshot = Save-AgentShellEnvironment
    try {
        [void](Set-AgentShellProfileEnvironment $Name)
        [Console]::Error.WriteLine("AgentShell account $Name - cwd remains $((Get-Location).Path)")
        $global:LASTEXITCODE = $null
        & powershell.exe -NoLogo -NoExit
        $script:AgentShellExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    } finally {
        Restore-AgentShellEnvironment $snapshot
    }
}

function Invoke-AgentShellStaticTool {
    param([string]$Tool, [object[]]$Arguments = @())
    $parsed = Split-AgentShellAccountOption $Arguments
    $account = $parsed.Account
    if ([string]::IsNullOrWhiteSpace($account)) { $account = $env:AGENT_SHELL_ACCOUNT }
    if ([string]::IsNullOrWhiteSpace($account)) { Throw-AgentShellError "$Tool requires --account ACCOUNT (or run it inside agentshell ACCOUNT)" }
    return Invoke-AgentShellTool $account $Tool $parsed.Remaining
}

function Invoke-AgentShellRunCommand {
    param([object[]]$Arguments = @())
    $parsed = Split-AgentShellAccountOption $Arguments
    $remaining = @($parsed.Remaining)
    $account = $parsed.Account
    if ([string]::IsNullOrWhiteSpace($account) -and $remaining.Count -gt 0 -and -not ([string]$remaining[0]).StartsWith('-')) {
        $account = [string]$remaining[0]
        if ($remaining.Count -gt 1) { $remaining = @($remaining[1..($remaining.Count - 1)]) } else { $remaining = @() }
    }
    if ([string]::IsNullOrWhiteSpace($account)) { Throw-AgentShellError 'agent-run requires --account ACCOUNT' }
    if ($remaining.Count -eq 0) { Throw-AgentShellError 'agent-run requires TOOL' }
    if ([string]$remaining[0] -eq '--') {
        if ($remaining.Count -lt 2) { Throw-AgentShellError 'missing command after --' }
        $remaining = @($remaining[1..($remaining.Count - 1)])
    }
    $tool = [string]$remaining[0]
    $toolArgs = if ($remaining.Count -gt 1) { @($remaining[1..($remaining.Count - 1)]) } else { @() }
    return Invoke-AgentShellTool $account $tool $toolArgs
}

function Invoke-AgentShellMainCommand {
    param([object[]]$Arguments = @())
    if ($Arguments.Count -eq 0) { Show-AgentShellUsage; return }
    $first = [string]$Arguments[0]
    if ($first -in @('-h', '--help', 'help')) { Show-AgentShellUsage; return }
    if ($first -in @('-v', '--version')) {
        $name = if ($Arguments.Count -gt 1) { [string]$Arguments[1] } else { '' }
        Show-AgentShellStatus $name
        return
    }
    if ($first -eq 'status') {
        $name = if ($Arguments.Count -gt 1) { [string]$Arguments[1] } else { '' }
        Show-AgentShellStatus $name
        return
    }
    if ($first -eq 'profile') {
        $rest = if ($Arguments.Count -gt 1) { @($Arguments[1..($Arguments.Count - 1)]) } else { @() }
        return Invoke-AgentShellProfileCommand $rest
    }
    if ($first -eq 'run') {
        $rest = if ($Arguments.Count -gt 1) { @($Arguments[1..($Arguments.Count - 1)]) } else { @() }
        return Invoke-AgentShellRunCommand $rest
    }

    $parsed = Split-AgentShellAccountOption $Arguments
    $remaining = @($parsed.Remaining)
    $account = $parsed.Account
    if ([string]::IsNullOrWhiteSpace($account)) {
        if ($remaining.Count -eq 0) { Throw-AgentShellError 'agentshell requires ACCOUNT' }
        $account = [string]$remaining[0]
        if ($remaining.Count -gt 1) { $remaining = @($remaining[1..($remaining.Count - 1)]) } else { $remaining = @() }
    }
    [void](Test-AgentShellProfileName $account)
    if ($remaining.Count -gt 0 -and [string]$remaining[0] -eq '--') {
        if ($remaining.Count -gt 1) { $remaining = @($remaining[1..($remaining.Count - 1)]) } else { $remaining = @() }
    }
    if ($remaining.Count -eq 0) { return Open-AgentShellPowerShell $account }
    $tool = [string]$remaining[0]
    $toolArgs = if ($remaining.Count -gt 1) { @($remaining[1..($remaining.Count - 1)]) } else { @() }
    return Invoke-AgentShellTool $account $tool $toolArgs
}

function Invoke-AgentShellRuntime {
    param([string]$Name, [object[]]$Arguments = @())

    if ($Name -match '^agent-(.+)-(codexr|codexmv|codex|claude|gemini|copilot)$') {
        return Invoke-AgentShellTool $Matches[1] $Matches[2] $Arguments
    }
    switch ($Name) {
        'agent-profile' { return Invoke-AgentShellProfileCommand $Arguments }
        'agent-run' { return Invoke-AgentShellRunCommand $Arguments }
        'agent-codex' { return Invoke-AgentShellStaticTool 'codex' $Arguments }
        'agent-codexr' { return Invoke-AgentShellStaticTool 'codexr' $Arguments }
        'agent-codexmv' { return Invoke-AgentShellStaticTool 'codexmv' $Arguments }
        'agent-claude' { return Invoke-AgentShellStaticTool 'claude' $Arguments }
        'agent-gemini' { return Invoke-AgentShellStaticTool 'gemini' $Arguments }
        'agent-copilot' { return Invoke-AgentShellStaticTool 'copilot' $Arguments }
        'agentshell' { return Invoke-AgentShellMainCommand $Arguments }
        default { Throw-AgentShellError "unknown invocation name: $Name" }
    }
}

if (-not $Library) {
    try {
        $script:AgentShellExitCode = 0
        Invoke-AgentShellRuntime $InvocationName $ArgumentList
        exit [int]$script:AgentShellExitCode
    } catch {
        Write-AgentShellError ($_.Exception.Message -replace '^AgentShell error:\s*', '')
        exit 2
    }
}
