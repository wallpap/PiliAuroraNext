#requires -Version 7.0
[CmdletBinding()]
param([string]$AnalyzerModulePath = '')

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $workspace
try {
    & uv run --locked ruff check tool
    if ($LASTEXITCODE -ne 0) { throw 'Python Ruff 检查失败。' }
    & uv run --locked python -m compileall -q tool
    if ($LASTEXITCODE -ne 0) { throw 'Python 编译检查失败。' }
    & uv run --locked python third_party/nativeapi/package.py verify
    if ($LASTEXITCODE -ne 0) {
        throw 'cnativeapi 预编译包与当前源码不一致，请运行 third_party/nativeapi/build.ps1 重建。'
    }

    # 模块只缓存到 build，不改变用户的 PowerShell 模块环境。
    if (-not $AnalyzerModulePath) {
        $moduleCache = Join-Path $workspace 'build/tooling/modules'
        $AnalyzerModulePath = Join-Path $moduleCache 'PSScriptAnalyzer/1.25.0/PSScriptAnalyzer.psd1'
        if (-not (Test-Path -LiteralPath $AnalyzerModulePath)) {
            Save-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0 -Path $moduleCache `
                -Repository PSGallery -Force -AcceptLicense
        }
    }
    Import-Module -Name $AnalyzerModulePath -Force
    $settings = Join-Path $workspace 'PSScriptAnalyzerSettings.psd1'
    $scripts = @(Get-ChildItem -LiteralPath @('tool', 'lib/scripts') -Recurse -File -Filter '*.ps1')
    $failures = @()
    foreach ($script in $scripts) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) {
            $failures += $parseErrors | ForEach-Object { "$($script.FullName): $_" }
        }
        $failures += Invoke-ScriptAnalyzer -Path $script.FullName -Settings $settings -Severity Warning,Error
    }
    if ($failures.Count) {
        $failures | Out-String | Write-Information -InformationAction Continue
        throw "PowerShell 检查发现 $($failures.Count) 个问题。"
    }
    Write-Information -InformationAction Continue "Python 语法及 Ruff、PowerShell 语法及静态分析通过（$($scripts.Count) 个 PowerShell 脚本）。"
}
finally {
    Pop-Location
}
