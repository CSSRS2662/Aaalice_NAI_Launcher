[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runnerPath = Join-Path $PSScriptRoot '../.agents/skills/aaalice-dev-sessions/scripts/android_runner.ps1'
$parseTokens = $null
$parseErrors = $null
$runnerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $runnerPath).Path,
    [ref]$parseTokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) { throw 'Android runner has parse errors.' }
$helper = $runnerAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-AndroidEmulatorAvdName'
}, $true)
if ($null -eq $helper) { throw 'AVD lookup helper was not found.' }
# Load only the production lookup function, never the launcher or Flutter.
. ([scriptblock]::Create($helper.Extent.Text))

function Invoke-MockAdb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $script:Queries.Add(($Arguments -join ' '))
    $response = $script:Responses[$script:Queries.Count - 1]
    $global:LASTEXITCODE = $response.Code
    if ($null -ne $response.Output) { Write-Output $response.Output }
}
$adbCommand = 'Invoke-MockAdb'
$cases = @(
    @{Name='console'; Responses=@(@{Output=@('Aaalice_API35', 'OK'); Code=0}); Expected='Aaalice_API35'; Queries=1},
    @{Name='trim'; Responses=@(@{Output='  Aaalice_API35  '; Code=0}); Expected='Aaalice_API35'; Queries=1},
    @{Name='no output'; Responses=@(@{Output=$null; Code=0}, @{Output='Aaalice_API35'; Code=0}); Expected='Aaalice_API35'; Queries=2},
    @{Name='empty output'; Responses=@(@{Output=''; Code=0}, @{Output='Aaalice_API35'; Code=0}); Expected='Aaalice_API35'; Queries=2},
    @{Name='whitespace'; Responses=@(@{Output='  '; Code=0}, @{Output='Aaalice_API35'; Code=0}); Expected='Aaalice_API35'; Queries=2},
    @{Name='console failure'; Responses=@(@{Output='Aaalice_API35'; Code=1}, @{Output='Aaalice_API35'; Code=0}); Expected='Aaalice_API35'; Queries=2},
    @{Name='other emulator'; Responses=@(@{Output='Other_AVD'; Code=0}); Expected='Other_AVD'; Queries=1},
    @{Name='both empty'; Responses=@(@{Output=$null; Code=0}, @{Output=$null; Code=0}); Throws=$true; Queries=2},
    @{Name='both failed'; Responses=@(@{Output=$null; Code=1}, @{Output='Aaalice_API35'; Code=1}); Throws=$true; Queries=2}
)
foreach ($case in $cases) {
    $script:Responses = $case.Responses
    $script:Queries = [System.Collections.Generic.List[string]]::new()
    $failure = $null
    $actual = $null
    try { $actual = Get-AndroidEmulatorAvdName -DeviceId 'emulator-5554' }
    catch { $failure = $_.Exception.Message }
    if ($case.Throws) {
        if ($failure -notlike '*refusing to launch a possible duplicate*') {
            throw "Expected a clear lookup failure for '$($case.Name)', got: $failure"
        }
    }
    elseif ($failure -or $actual -ne $case.Expected) {
        throw "Lookup failed for '$($case.Name)': result='$actual', error='$failure'"
    }
    if ($script:Queries.Count -ne $case.Queries) { throw "Unexpected query count: $($case.Name)" }
    if ($case.Queries -eq 2 -and $script:Queries[1] -ne '-s emulator-5554 shell getprop ro.boot.qemu.avd_name') {
        throw 'Fallback must read the AVD name from the selected device.'
    }
    Write-Output "PASS: $($case.Name)"
}
$script:Queries.Clear()
if ($null -ne (Get-AndroidEmulatorAvdName -DeviceId $null) -or $script:Queries.Count -ne 0) {
    throw 'A missing device ID must not invoke ADB.'
}
$global:LASTEXITCODE = 0
Write-Output 'PASS: missing device ID'
Write-Output 'All 10 Android runner lookup tests passed (no devices launched).'
