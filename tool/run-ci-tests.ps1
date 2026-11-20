[CmdletBinding(DefaultParameterSetName = 'Host')]
param(
    [ValidateSet("fvm", "path")]
    [string]$FlutterTool = "fvm",
    [Parameter(ParameterSetName = 'Host')]
    [switch]$PlatformOnly,
    [Parameter(Mandatory, ParameterSetName = 'NativeImages')]
    [switch]$NativeImages,
    [switch]$List,
    [ValidateRange(1, 256)]
    [int]$Concurrency
)

$ErrorActionPreference = "Stop"
$Workspace = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Workspace

$inventory = @(
    Get-ChildItem -LiteralPath test -Recurse -File -Filter '*_test.dart' |
        ForEach-Object { [IO.Path]::GetRelativePath($Workspace, $_.FullName).Replace('\', '/') } |
        Sort-Object
)
$registry = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-platforms.json') -Raw | ConvertFrom-Json -AsHashtable
$classifications = @{}
foreach ($category in @('windows', 'androidHost', 'bothHosts', 'nativeImages')) {
    foreach ($path in $registry[$category]) {
        $matches = if ($path.EndsWith('/')) {
            @($inventory | Where-Object { $_.StartsWith($path, [StringComparison]::Ordinal) })
        } else {
            @($inventory | Where-Object { $_ -ceq $path })
        }
        if (-not $matches) {
            throw "Test classification matches no files: $category -> $path"
        }
        foreach ($file in $matches) {
            if ($classifications.ContainsKey($file)) {
                throw "Test has more than one platform classification: $file"
            }
            $classifications[$file] = $category
        }
    }
}

if ($NativeImages -and -not $IsWindows) {
    throw 'Native region image tests require Windows.'
}
$ciTests = @($inventory | Where-Object {
    $category = $classifications[$_]
    if ($NativeImages) { return $category -eq 'nativeImages' }
    if ($category -eq 'windows') { return $IsWindows }
    if ($category -eq 'androidHost') { return $IsLinux }
    if ($category -eq 'nativeImages') { return $false }
    if ($PlatformOnly) { return $category -eq 'bothHosts' -and ($IsWindows -or $IsLinux) }
    return $true
})
if ($List) {
    $ciTests
    return
}
if (-not $ciTests) {
    throw 'No tests were selected for this host and scope.'
}
if ($NativeImages) {
    $env:REGION_TEST_REQUIRED = '1'
}
Write-Information -InformationAction Continue "Running the CI test suite ($($ciTests.Count) paths)..."
$testArguments = @('test', '--no-pub')
if ($PSBoundParameters.ContainsKey('Concurrency')) {
    $testArguments += @('--concurrency', $Concurrency)
}

$batches = [System.Collections.Generic.List[object]]::new()
if ($IsWindows) {
    # Flutter/FVM 的 Windows 入口是批处理，预留空间给 SDK 路径及其他参数。
    $maxBatchCharacters = 6000
    $batch = [System.Collections.Generic.List[string]]::new()
    $batchCharacters = 0
    foreach ($path in $ciTests) {
        $pathCharacters = $path.Length + 3
        if ($pathCharacters -gt $maxBatchCharacters) {
            throw "CI test path exceeds the Windows command budget: $path"
        }
        if ($batch.Count -gt 0 -and $batchCharacters + $pathCharacters -gt $maxBatchCharacters) {
            $batches.Add($batch.ToArray())
            $batch.Clear()
            $batchCharacters = 0
        }
        $batch.Add($path)
        $batchCharacters += $pathCharacters
    }
    if ($batch.Count -gt 0) {
        $batches.Add($batch.ToArray())
    }
}
else {
    $batches.Add([string[]]$ciTests)
}

$failedBatches = [System.Collections.Generic.List[string]]::new()
for ($index = 0; $index -lt $batches.Count; $index++) {
    $batch = [string[]]$batches[$index]
    Write-Information -InformationAction Continue "Running CI test batch $($index + 1)/$($batches.Count) ($($batch.Count) paths)..."
    if ($FlutterTool -eq "fvm") {
        & fvm flutter @testArguments @batch
    }
    else {
        & flutter @testArguments @batch
    }
    if ($LASTEXITCODE -ne 0) {
        $failedBatches.Add("$($index + 1) (exit $LASTEXITCODE)")
    }
}

if ($failedBatches.Count -gt 0) {
    throw "CI test batches failed: $($failedBatches -join ', ')"
}

Write-Information -InformationAction Continue "Local CI tests completed successfully."
