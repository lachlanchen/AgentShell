# Windows PowerShell 5.1 integration tests for AgentShell.
#
# The test deliberately runs with an isolated HOME, USERPROFILE, profile,
# installation root, command directory, provider state root, and native-command
# directory.  It must never read or update the invoking user's AgentShell or
# PowerShell state.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installScript = Join-Path $repoRoot 'install.ps1'
$runtimeScript = Join-Path $repoRoot 'bin\agentshell.ps1'
$sourceShellHelper = Join-Path $repoRoot 'shell\agentshell.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('AgentShell PS5 test - 日本語 - ' + [Guid]::NewGuid().ToString('N'))

$environmentNames = @(
    'HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'PATH',
    'AGENT_SHELL_HOME', 'AGENT_SHELL_INSTALL_ROOT', 'AGENT_SHELL_BIN_DIR',
    'AGENT_SHELL_POWERSHELL_HELPER', 'AGENT_SHELL_POWERSHELL_PROFILE',
    'AGENT_SHELL_BASE_CODEX_HOME', 'AGENT_SHELL_SHARED_CODEX_SQLITE_HOME',
    'AGENT_SHELL_SHARED_CODEX_HOME',
    'AGENT_SHELL_CODEX_WRAPPER', 'AGENT_SHELL_USE_CODEX_WRAPPER',
    'AGENT_SHELL_PRESERVE_AUTH_ENV', 'AGENT_SHELL_ACCOUNT',
    'AGENT_SHELL_PROFILE_ROOT', 'AGENT_SHELL_PROFILE_ENV',
    'AGENT_SHELL_CODEX_HISTORY_MODE', 'AGENT_SHELL_CODEX_SQLITE_HOME',
    'AGENT_SHELL_CODEX_HOME',
    'AGENT_TEST_OUTPUT', 'AGENT_TEST_PROFILE_ONLY', 'CODEX_HOME', 'CODEX_SQLITE_HOME',
    'CODEX_API_KEY', 'CODEX_ACCESS_TOKEN', 'OPENAI_API_KEY',
    'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN',
    'GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_APPLICATION_CREDENTIALS',
    'COPILOT_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN',
    'CODEX_SESSION_ID', 'CODEX_THREAD_ID', 'CODEX_CI'
)

$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$functionNames = @('agentshell', 'codex', 'codexr', 'codexmv', 'claude', 'gemini', 'copilot')
$savedFunctions = @{}
foreach ($name in $functionNames) {
    $item = Get-Item -LiteralPath ('Function:\' + $name) -ErrorAction SilentlyContinue
    if ($null -ne $item) {
        $savedFunctions[$name] = $item.ScriptBlock
    }
}

$locationPushed = $false

function Fail-Test {
    param([string]$Message)
    throw ('AgentShell test failure: ' + $Message)
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        Fail-Test $Message
    }
}

function Assert-False {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if ($Condition) {
        Fail-Test $Message
    }
}

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [string]$Message
    )
    if ($Expected -cne $Actual) {
        Fail-Test ("{0}; expected <{1}> but got <{2}>" -f $Message, $Expected, $Actual)
    }
}

function Assert-PathEqual {
    param(
        [string]$Expected,
        [string]$Actual,
        [string]$Message
    )
    $expectedFull = [IO.Path]::GetFullPath($Expected).TrimEnd('\', '/')
    $actualFull = [IO.Path]::GetFullPath($Actual).TrimEnd('\', '/')
    if (-not [string]::Equals($expectedFull, $actualFull, [StringComparison]::OrdinalIgnoreCase)) {
        Fail-Test ("{0}; expected path <{1}> but got <{2}>" -f $Message, $expectedFull, $actualFull)
    }
}

function Assert-Sequence {
    param(
        [object[]]$Expected,
        [object[]]$Actual,
        [string]$Message
    )
    if ($null -eq $Expected) { $Expected = @() }
    if ($null -eq $Actual) { $Actual = @() }
    if ($Expected.Count -ne $Actual.Count) {
        Fail-Test ("{0}; expected {1} arguments but got {2}: [{3}]" -f $Message, $Expected.Count, $Actual.Count, ($Actual -join ', '))
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ([string]$Expected[$index] -cne [string]$Actual[$index]) {
            Fail-Test ("{0}; argument {1} expected <{2}> but got <{3}>" -f $Message, $index, $Expected[$index], $Actual[$index])
        }
    }
}

function Invoke-AgentCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @(),
        [switch]$ExpectFailure
    )

    $output = @(& $Command @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }

    if ($ExpectFailure) {
        if ($exitCode -eq 0) {
            Fail-Test ("command unexpectedly succeeded: {0} {1}" -f $Command, ($Arguments -join ' '))
        }
    }
    elseif ($exitCode -ne 0) {
        Fail-Test ("command failed ({0}): {1} {2}`n{3}" -f $exitCode, $Command, ($Arguments -join ' '), ($output -join [Environment]::NewLine))
    }
    return ,$output
}

function Read-NativeInvocation {
    if (-not (Test-Path -LiteralPath $env:AGENT_TEST_OUTPUT -PathType Leaf)) {
        Fail-Test 'the native stub did not write an invocation record'
    }

    $record = @{}
    foreach ($line in [IO.File]::ReadAllLines($env:AGENT_TEST_OUTPUT, [Text.Encoding]::UTF8)) {
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) {
            Fail-Test ("malformed native-stub record: {0}" -f $line)
        }
        $key = $line.Substring(0, $separator)
        $encoded = $line.Substring($separator + 1)
        if ($encoded -eq '!') {
            $record[$key] = $null
        }
        else {
            $record[$key] = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
        }
    }

    $argumentCount = [int]$record['argv.count']
    $arguments = @()
    for ($index = 0; $index -lt $argumentCount; $index++) {
        $arguments += $record['argv.' + $index]
    }

    return [PSCustomObject]@{
        Tool = $record['tool']
        Cwd = $record['cwd']
        Arguments = [object[]]$arguments
        Values = $record
    }
}

function Invoke-AndReadNative {
    param([Parameter(Mandatory = $true)][ScriptBlock]$Action)
    if (Test-Path -LiteralPath $env:AGENT_TEST_OUTPUT) {
        Remove-Item -LiteralPath $env:AGENT_TEST_OUTPUT -Force
    }
    & $Action | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail-Test ("native invocation returned exit code {0}" -f $LASTEXITCODE)
    }
    return Read-NativeInvocation
}

function Assert-AccountEnvironment {
    param(
        [PSCustomObject]$Invocation,
        [string]$Account,
        [string]$ExpectedSqliteHome,
        [string]$ExpectedCodexHome = ''
    )
    $profileRoot = Join-Path (Join-Path $env:AGENT_SHELL_HOME 'profiles') $Account
    if ([string]::IsNullOrWhiteSpace($ExpectedCodexHome)) {
        $ExpectedCodexHome = Join-Path $profileRoot 'codex-home'
    }
    Assert-Equal $Account $Invocation.Values['env.AGENT_SHELL_ACCOUNT'] 'selected account'
    Assert-PathEqual $ExpectedCodexHome $Invocation.Values['env.CODEX_HOME'] 'profile CODEX_HOME'
    Assert-PathEqual $ExpectedSqliteHome $Invocation.Values['env.CODEX_SQLITE_HOME'] 'profile CODEX_SQLITE_HOME'

    foreach ($name in @(
        'CODEX_API_KEY', 'CODEX_ACCESS_TOKEN', 'OPENAI_API_KEY',
        'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN',
        'GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_APPLICATION_CREDENTIALS',
        'COPILOT_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN',
        'CODEX_SESSION_ID', 'CODEX_THREAD_ID', 'CODEX_CI'
    )) {
        Assert-True ($null -eq $Invocation.Values['env.' + $name]) ("account launch must clear inherited {0}" -f $name)
    }
}

function New-NativeRecorder {
    param([string]$Directory)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null

    $typeSuffix = [Guid]::NewGuid().ToString('N')
    $source = @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

public static class AgentShellNativeStub_$typeSuffix
{
    private static void Field(StreamWriter writer, string key, string value)
    {
        if (value == null)
        {
            writer.WriteLine(key + "=!");
            return;
        }
        writer.WriteLine(key + "=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(value)));
    }

    public static int Main(string[] args)
    {
        string output = Environment.GetEnvironmentVariable("AGENT_TEST_OUTPUT");
        if (String.IsNullOrEmpty(output))
        {
            Console.Error.WriteLine("AGENT_TEST_OUTPUT is not set");
            return 91;
        }
        string tool = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
        string[] variables = new string[] {
            "AGENT_SHELL_ACCOUNT", "CODEX_HOME", "CODEX_SQLITE_HOME",
            "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_API_KEY",
            "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
            "GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_APPLICATION_CREDENTIALS",
            "COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN",
            "CODEX_SESSION_ID", "CODEX_THREAD_ID", "CODEX_CI"
        };
        using (StreamWriter writer = new StreamWriter(output, false, new UTF8Encoding(false)))
        {
            Field(writer, "tool", tool);
            Field(writer, "cwd", Directory.GetCurrentDirectory());
            Field(writer, "argv.count", args.Length.ToString(System.Globalization.CultureInfo.InvariantCulture));
            for (int index = 0; index < args.Length; index++)
                Field(writer, "argv." + index.ToString(System.Globalization.CultureInfo.InvariantCulture), args[index]);
            foreach (string variable in variables)
                Field(writer, "env." + variable, Environment.GetEnvironmentVariable(variable));
        }
        Console.WriteLine("stub " + tool);
        return 0;
    }
}
"@

    # Compile out-of-process so the test process never loads (and therefore
    # never locks) the recorder assembly. This lets the finally block remove
    # every temporary artifact on Windows.
    $sourcePath = Join-Path $Directory 'recorder.cs'
    $compiled = Join-Path $Directory 'recorder.exe'
    [IO.File]::WriteAllText($sourcePath, $source, (New-Object Text.UTF8Encoding($false)))
    $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) {
        Fail-Test ("the .NET Framework C# compiler was not found: {0}" -f $csc)
    }
    $compilerOutput = @(& $csc '/nologo' '/target:exe' ('/out:' + $compiled) $sourcePath 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Fail-Test ("could not compile native recorder:`n{0}" -f ($compilerOutput -join [Environment]::NewLine))
    }
    foreach ($name in @('codex', 'codexr', 'codexmv', 'claude', 'gemini', 'copilot')) {
        Copy-Item -LiteralPath $compiled -Destination (Join-Path $Directory ($name + '.exe'))
    }
}

try {
    foreach ($path in @($installScript, $runtimeScript, $sourceShellHelper)) {
        Assert-True (Test-Path -LiteralPath $path -PathType Leaf) ("required Windows entry point is missing: {0}" -f $path)
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        Assert-Equal 0 $parseErrors.Count ("PowerShell 5.1 parse errors in {0}: {1}" -f $path, (($parseErrors | ForEach-Object { $_.Message }) -join '; '))
    }

    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $testHome = Join-Path $testRoot 'Home 用户'
    $appData = Join-Path $testRoot 'AppData Roaming'
    $localAppData = Join-Path $testRoot 'AppData Local'
    $stateRoot = Join-Path $testRoot 'State プロファイル'
    $installRoot = Join-Path $testRoot 'Installed Runtime'
    $binDirectory = Join-Path $testRoot 'User Bin'
    $nativeDirectory = Join-Path $testRoot 'Native Commands'
    $workDirectory = Join-Path $testRoot 'Working Tree 中文'
    $profilePath = Join-Path $testRoot 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
    $helperPath = Join-Path $testRoot 'Documents\PowerShell\AgentShell.ps1'
    $sharedSqliteHome = Join-Path $testRoot 'Shared SQLite 共有'
    $baseCodexHome = Join-Path $testHome '.codex'

    foreach ($directory in @($testHome, $appData, $localAppData, $stateRoot, $installRoot, $binDirectory, $nativeDirectory, $workDirectory, (Split-Path -Parent $profilePath), $sharedSqliteHome, $baseCodexHome)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [IO.File]::WriteAllText($profilePath, "# existing profile`r`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $baseCodexHome 'auth.json'), "must-not-copy`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $baseCodexHome 'config.toml'), "model = `"test-model`"`nsqlite_home = `"must-not-inherit`"`n", (New-Object Text.UTF8Encoding($false)))

    $env:HOME = $testHome
    $env:USERPROFILE = $testHome
    $env:APPDATA = $appData
    $env:LOCALAPPDATA = $localAppData
    $env:AGENT_SHELL_HOME = $stateRoot
    $env:AGENT_SHELL_INSTALL_ROOT = $installRoot
    $env:AGENT_SHELL_BIN_DIR = $binDirectory
    $env:AGENT_SHELL_POWERSHELL_HELPER = $helperPath
    $env:AGENT_SHELL_POWERSHELL_PROFILE = $profilePath
    $env:AGENT_SHELL_BASE_CODEX_HOME = $baseCodexHome
    $env:AGENT_SHELL_SHARED_CODEX_SQLITE_HOME = $sharedSqliteHome
    $env:AGENT_SHELL_CODEX_WRAPPER = Join-Path $testRoot 'missing codex wrapper.ps1'
    $env:AGENT_SHELL_USE_CODEX_WRAPPER = '0'
    $env:AGENT_SHELL_PRESERVE_AUTH_ENV = '0'
    $env:AGENT_TEST_OUTPUT = Join-Path $testRoot 'native invocation.txt'
    foreach ($name in @(
        'AGENT_SHELL_ACCOUNT', 'AGENT_SHELL_PROFILE_ROOT', 'AGENT_SHELL_PROFILE_ENV',
        'AGENT_SHELL_CODEX_HISTORY_MODE', 'AGENT_SHELL_CODEX_SQLITE_HOME',
        'AGENT_SHELL_CODEX_HOME'
    )) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }

    New-NativeRecorder $nativeDirectory
    $env:PATH = $binDirectory + [IO.Path]::PathSeparator + $nativeDirectory + [IO.Path]::PathSeparator + $savedEnvironment['PATH']

    # Installation is repeatable, uses the explicitly isolated PowerShell
    # profile, and installs only one marked source block.
    & $installScript | Out-Null
    & $installScript | Out-Null
    $profileText = [IO.File]::ReadAllText($profilePath)
    Assert-Equal 1 ([regex]::Matches($profileText, '(?m)^# >>> AgentShell >>>\s*$')).Count 'installer must add one opening marker'
    Assert-Equal 1 ([regex]::Matches($profileText, '(?m)^# <<< AgentShell <<<\s*$')).Count 'installer must add one closing marker'
    Assert-True ($profileText.IndexOf($helperPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) 'profile marker must source the isolated helper path'
    Assert-True (Test-Path -LiteralPath $helperPath -PathType Leaf) 'installer did not write the isolated shell helper'
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot 'agentshell.ps1') -PathType Leaf) 'installer did not write the runtime'

    # Reinstalling with a moved helper must update the one managed profile
    # block instead of leaving a stale path behind.
    $relocatedHelperPath = Join-Path $testRoot 'Relocated Shell\agentshell.ps1'
    $env:AGENT_SHELL_POWERSHELL_HELPER = $relocatedHelperPath
    & $installScript | Out-Null
    $relocatedProfileText = [IO.File]::ReadAllText($profilePath)
    Assert-True ($relocatedProfileText.IndexOf($relocatedHelperPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) 'installer did not update a relocated helper path'
    Assert-Equal 1 ([regex]::Matches($relocatedProfileText, '(?m)^# >>> AgentShell >>>\s*$')).Count 'relocation must keep one marker block'
    $env:AGENT_SHELL_POWERSHELL_HELPER = $helperPath
    & $installScript | Out-Null

    foreach ($name in @('agentshell', 'agent-profile', 'agent-run', 'agent-codex', 'agent-codexr', 'agent-codexmv')) {
        $resolved = Get-Command $name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
        Assert-True ($null -ne $resolved) ("installer did not create command {0}" -f $name)
        Assert-True ([IO.Path]::GetFullPath($resolved.Source).StartsWith([IO.Path]::GetFullPath($binDirectory), [StringComparison]::OrdinalIgnoreCase)) ("{0} resolved outside the isolated bin directory" -f $name)
    }

    # A common first line is not a sufficient ownership marker. The installer
    # must refuse an unrelated batch file even when it starts with @echo off.
    $ownershipProbe = Join-Path $binDirectory 'agent-copilot.cmd'
    $ownedShim = [IO.File]::ReadAllBytes($ownershipProbe)
    [IO.File]::WriteAllText($ownershipProbe, "@echo off`r`necho unrelated`r`n", [Text.Encoding]::ASCII)
    $ownershipRefused = $false
    try {
        & $installScript | Out-Null
    } catch {
        $ownershipRefused = $_.Exception.Message -match 'refusing to replace unrelated command'
    }
    Assert-True $ownershipRefused 'installer must refuse an unrelated @echo off batch file'
    [IO.File]::WriteAllBytes($ownershipProbe, $ownedShim)

    # AgentShell should synchronously invoke commands in the current console.
    # Start-Process is both unnecessary here and a common source of popup
    # terminal windows on Windows.
    foreach ($path in @($installScript, $runtimeScript, $sourceShellHelper)) {
        $source = [IO.File]::ReadAllText($path)
        Assert-False ([regex]::IsMatch($source, '(?im)^\s*(?!#).*\bStart-Process\b')) ("{0} must not launch popup processes" -f $path)
        Assert-False ([regex]::IsMatch($source, '(?im)\$\w+\s*=\s*@\(\s*Invoke-AgentShellRuntime')) ("{0} must not buffer interactive runtime output" -f $path)
    }

    $agentProfileCommand = (Get-Command agent-profile -CommandType Application, ExternalScript | Select-Object -First 1).Source
    Invoke-AgentCommand $agentProfileCommand @('create', 'personal') | Out-Null
    Invoke-AgentCommand $agentProfileCommand @('create', 'personal') | Out-Null
    $personalRoot = Join-Path (Join-Path $stateRoot 'profiles') 'personal'
    Assert-True (Test-Path -LiteralPath (Join-Path $personalRoot 'codex-home') -PathType Container) 'profile creation did not create codex-home'
    Assert-False (Test-Path -LiteralPath (Join-Path $personalRoot 'codex-home\auth.json')) 'profile creation copied the ordinary Codex credential'
    $profileEnvironmentProbe = @'
$env:AGENT_TEST_PROFILE_ONLY = 'selected account only'
$AgentShellProfileLeakVariable = 'must stay local'
function AgentShellProfileLeakFunction { 'must stay local' }
Set-Alias -Name AgentShellProfileLeakAlias -Value AgentShellProfileLeakFunction
'@
    [IO.File]::AppendAllText((Join-Path $personalRoot 'env.ps1'), "`r`n$profileEnvironmentProbe`r`n", (New-Object Text.UTF8Encoding($true)))

    # Direct command shims can opt into the same explicit workstation wrapper
    # contract used by the Bash runtime.
    $wrapperProbe = Join-Path $testRoot 'codex wrapper probe.ps1'
    $escapedNativeDirectory = $nativeDirectory.Replace("'", "''")
    $wrapperSource = @"
param(
    [string]`$Tool,
    [Parameter(ValueFromRemainingArguments = `$true)][string[]]`$Arguments
)
`$native = Join-Path '$escapedNativeDirectory' (`$Tool + '.exe')
& `$native '--wrapper-used' @Arguments
exit `$LASTEXITCODE
"@
    [IO.File]::WriteAllText($wrapperProbe, $wrapperSource, (New-Object Text.UTF8Encoding($true)))
    $missingWrapper = $env:AGENT_SHELL_CODEX_WRAPPER
    $env:AGENT_SHELL_CODEX_WRAPPER = $wrapperProbe
    $env:AGENT_SHELL_USE_CODEX_WRAPPER = '1'
    $agentCodexCommand = (Get-Command agent-codex -CommandType Application, ExternalScript | Select-Object -First 1).Source
    Invoke-AgentCommand $agentCodexCommand @('--account', 'personal', '--version') | Out-Null
    $wrapperInvocation = Read-NativeInvocation
    Assert-Equal 'codex' $wrapperInvocation.Tool 'direct shim wrapper target'
    Assert-Sequence @('--wrapper-used', '--version') $wrapperInvocation.Arguments 'direct shim wrapper argv'
    Assert-AccountEnvironment $wrapperInvocation 'personal' (Join-Path $personalRoot 'codex-home')
    $env:AGENT_SHELL_CODEX_WRAPPER = $missingWrapper
    $env:AGENT_SHELL_USE_CODEX_WRAPPER = '0'

    # Reject traversal, path aliases, DOS device names, and case-only profile
    # aliases. These checks are necessary on Windows' case-insensitive filesystems.
    foreach ($invalid in @('../escape', 'bad name', '.leading', (('a' * 65) -join ''), 'personal.', 'CON', 'nul', 'COM1', 'LPT9.txt')) {
        Invoke-AgentCommand $agentProfileCommand @('create', $invalid) -ExpectFailure | Out-Null
    }
    Invoke-AgentCommand $agentProfileCommand @('create', 'CaseProfile') | Out-Null
    Invoke-AgentCommand $agentProfileCommand @('create', 'caseprofile') -ExpectFailure | Out-Null
    Assert-False (Test-Path -LiteralPath (Join-Path $testRoot 'escape')) 'invalid profile escaped the isolated state root'

    # Load the installed helper exactly as an interactive PowerShell profile
    # would. Capture a pre-existing workstation function, not only an
    # executable, so account routing cannot silently bypass local wrappers.
    $global:AgentShellTestNativeCodex = (Get-Command codex -CommandType Application | Select-Object -First 1).Source
    $global:AgentShellTestCodexCalls = 0
    function codex {
        $global:AgentShellTestCodexCalls++
        & $global:AgentShellTestNativeCodex @args
    }
    Set-Alias -Name codexr -Value codexr.exe -Scope Global -Force
    . $helperPath
    Push-Location $workDirectory
    $locationPushed = $true

    $statusOutput = @(agentshell status)
    Assert-False ($statusOutput.Count -gt 0 -and $statusOutput[$statusOutput.Count - 1] -is [int]) 'interactive agentshell must not print its internal exit code'
    Assert-Equal 0 $LASTEXITCODE 'interactive agentshell status exit code'
    Assert-True (@(agentshell --version) -contains 'AgentShell 0.4.0') 'installed AgentShell version'

    $env:CODEX_HOME = Join-Path $testRoot 'Ordinary Codex Home'
    $env:CODEX_SQLITE_HOME = Join-Path $testRoot 'Ordinary SQLite Home'
    foreach ($name in @(
        'CODEX_API_KEY', 'CODEX_ACCESS_TOKEN', 'OPENAI_API_KEY',
        'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN',
        'GEMINI_API_KEY', 'GOOGLE_API_KEY', 'GOOGLE_APPLICATION_CREDENTIALS',
        'COPILOT_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN',
        'CODEX_SESSION_ID', 'CODEX_THREAD_ID', 'CODEX_CI'
    )) {
        [Environment]::SetEnvironmentVariable($name, ('ordinary inherited ' + $name), 'Process')
    }

    $invocation = Invoke-AndReadNative { codex '--version' }
    Assert-Equal 'codex' $invocation.Tool 'ordinary codex target'
    Assert-Sequence @('--version') $invocation.Arguments 'ordinary codex argv'
    Assert-PathEqual $workDirectory $invocation.Cwd 'ordinary codex working directory'
    Assert-Equal 'ordinary inherited OPENAI_API_KEY' $invocation.Values['env.OPENAI_API_KEY'] 'ordinary codex must retain inherited authentication'
    Assert-PathEqual $env:CODEX_HOME $invocation.Values['env.CODEX_HOME'] 'ordinary codex must retain CODEX_HOME'
    Assert-Equal 1 $global:AgentShellTestCodexCalls 'ordinary codex must use the captured workstation wrapper'

    $invocation = Invoke-AndReadNative { codexr '--all' 'session with spaces' }
    Assert-Equal 'codexr' $invocation.Tool 'ordinary codexr target'
    Assert-Sequence @('--all', 'session with spaces') $invocation.Arguments 'ordinary codexr argv'
    Assert-PathEqual $workDirectory $invocation.Cwd 'ordinary codexr working directory'
    Assert-Equal 'Function' (Get-Command codexr).CommandType.ToString() 'AgentShell must replace a captured alias with its routing function'

    $oldPath = Join-Path $testRoot 'Old project 旧'
    $newPath = Join-Path $testRoot 'New project 新'
    $invocation = Invoke-AndReadNative { codexmv $oldPath $newPath '--no-resume' }
    Assert-Equal 'codexmv' $invocation.Tool 'ordinary codexmv target'
    Assert-Sequence @($oldPath, $newPath, '--no-resume') $invocation.Arguments 'ordinary codexmv argv'

    # Native Codex -p/--profile is not an AgentShell selector, and an account
    # option occurring later in argv belongs to native Codex unchanged.
    $invocation = Invoke-AndReadNative { codex '-p' 'native-profile' '--account' 'later-native-value' 'prompt with spaces' }
    Assert-Equal 'codex' $invocation.Tool 'native -p target'
    Assert-Sequence @('-p', 'native-profile', '--account', 'later-native-value', 'prompt with spaces') $invocation.Arguments 'native -p and later --account argv'
    Assert-Equal $null $invocation.Values['env.AGENT_SHELL_ACCOUNT'] 'later --account must not activate AgentShell'
    Assert-Equal 'ordinary inherited OPENAI_API_KEY' $invocation.Values['env.OPENAI_API_KEY'] 'later --account must remain an ordinary invocation'

    $privateSqliteHome = Join-Path $personalRoot 'codex-home'
    $invocation = Invoke-AndReadNative { codex '--account' 'personal' '-p' 'native-profile' 'Unicode 日本語 prompt' }
    Assert-Equal 'codex' $invocation.Tool 'account codex target'
    Assert-Sequence @('-p', 'native-profile', 'Unicode 日本語 prompt') $invocation.Arguments 'spaced --account argv'
    Assert-PathEqual $workDirectory $invocation.Cwd 'account codex working directory'
    Assert-AccountEnvironment $invocation 'personal' $privateSqliteHome
    Assert-True ($global:AgentShellTestCodexCalls -ge 2) 'account codex must use the captured workstation wrapper'
    Assert-Equal $null $env:AGENT_TEST_PROFILE_ONLY 'account env.ps1 variables must not leak into the ordinary shell'
    Assert-Equal $null (Get-Variable AgentShellProfileLeakVariable -ErrorAction SilentlyContinue) 'account env.ps1 variables must stay in child scope'
    Assert-Equal $null (Get-Command AgentShellProfileLeakFunction -ErrorAction SilentlyContinue) 'account env.ps1 functions must stay in child scope'
    Assert-Equal $null (Get-Alias AgentShellProfileLeakAlias -ErrorAction SilentlyContinue) 'account env.ps1 aliases must stay in child scope'

    $invocation = Invoke-AndReadNative { codex '--account=personal' '--version' }
    Assert-Sequence @('--version') $invocation.Arguments 'equals --account argv'
    Assert-AccountEnvironment $invocation 'personal' $privateSqliteHome

    $invocation = Invoke-AndReadNative { codex '--project' 'personal' '--search' 'project alias prompt' }
    Assert-Sequence @('--search', 'project alias prompt') $invocation.Arguments 'spaced --project argv'
    Assert-AccountEnvironment $invocation 'personal' $privateSqliteHome

    $invocation = Invoke-AndReadNative { codex '--project=personal' '--version' }
    Assert-Sequence @('--version') $invocation.Arguments 'equals --project argv'
    Assert-AccountEnvironment $invocation 'personal' $privateSqliteHome

    # Account codexr and codexmv preserve the native/workstation applications
    # captured before the PowerShell functions were installed.
    $invocation = Invoke-AndReadNative { codexr '--account' 'personal' '--all' 'named session' }
    Assert-Equal 'codexr' $invocation.Tool 'account codexr target'
    Assert-Sequence @('--all', 'named session') $invocation.Arguments 'account codexr argv'
    Assert-AccountEnvironment $invocation 'personal' $privateSqliteHome

    $invocation = Invoke-AndReadNative { codexmv '--project=personal' $oldPath $newPath '--latest' }
    Assert-Equal 'codexmv' $invocation.Tool 'account codexmv target'
    Assert-Sequence @($oldPath, $newPath, '--latest') $invocation.Arguments 'account codexmv argv'
    Assert-AccountEnvironment $invocation 'personal' $privateSqliteHome

    # Shared history keeps authentication profile-local while making the
    # SQLite index and source-rollout tree coherent.
    Invoke-AgentCommand $agentProfileCommand @('history', 'personal', 'shared') | Out-Null
    $invocation = Invoke-AndReadNative { codex '--account' 'personal' '--version' }
    $sharedCodexView = Join-Path $personalRoot 'codex-shared-home'
    Assert-AccountEnvironment $invocation 'personal' $sharedSqliteHome $sharedCodexView
    Assert-True (Test-Path -LiteralPath (Join-Path $sharedCodexView 'sessions') -PathType Container) 'shared history view must expose sessions'
    Assert-False (Test-Path -LiteralPath (Join-Path $sharedCodexView 'auth.json')) 'shared history must not copy the ordinary Codex credential'
    Assert-True (Test-Path -LiteralPath (Join-Path $sharedCodexView '.history-root-v1') -PathType Leaf) 'shared history view must record its source root'

    Invoke-AgentCommand $agentProfileCommand @('history', 'personal', 'private') | Out-Null
    $invocation = Invoke-AndReadNative { codex '--account' 'personal' '--version' }
    Assert-AccountEnvironment $invocation 'personal' $privateSqliteHome

    Assert-PathEqual $workDirectory (Get-Location).Path 'all profile launches must preserve caller cwd'
    Write-Host 'AgentShell Windows PowerShell 5.1 tests passed.'
}
finally {
    if ($locationPushed) {
        Pop-Location
    }

    foreach ($name in $functionNames) {
        Remove-Item -LiteralPath ('Function:\' + $name) -Force -ErrorAction SilentlyContinue
        if ($savedFunctions.ContainsKey($name)) {
            Set-Item -LiteralPath ('Function:\' + $name) -Value $savedFunctions[$name]
        }
    }

    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }

    if (Test-Path -LiteralPath $testRoot) {
        $fullTestRoot = [IO.Path]::GetFullPath($testRoot)
        $fullTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($fullTestRoot.StartsWith($fullTempRoot, [StringComparison]::OrdinalIgnoreCase) -and $fullTestRoot.Length -gt $fullTempRoot.Length) {
            Remove-Item -LiteralPath $fullTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Variable -Name AgentShellTestNativeCodex, AgentShellTestCodexCalls -Scope Global -Force -ErrorAction SilentlyContinue
}
