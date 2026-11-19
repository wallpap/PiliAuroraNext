$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$packageConfigPath = Join-Path $workspace '.dart_tool/package_config.json'
if (-not (Test-Path -LiteralPath $packageConfigPath)) {
    throw '先在仓库根目录运行 fvm flutter pub get --enforce-lockfile。'
}

$config = Get-Content -LiteralPath $packageConfigPath -Raw | ConvertFrom-Json
$configUri = [Uri]::new($packageConfigPath)
foreach ($package in $config.packages) {
    $package.rootUri = [Uri]::new($configUri, $package.rootUri).AbsoluteUri
}

$build = (New-Item -ItemType Directory -Path (Join-Path $workspace 'build') -Force).FullName
$scratch = (New-Item -ItemType Directory -Path (Join-Path $build "protocol-analysis-$([Guid]::NewGuid())")).FullName
try {
    New-Item -ItemType Directory -Path (Join-Path $scratch '.dart_tool') | Out-Null
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $scratch '.dart_tool/package_config.json') -Encoding utf8
    Set-Content -LiteralPath (Join-Path $scratch 'pubspec.yaml') -Value 'name: pili_aurora_protocol_analysis' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $scratch 'analysis_options.yaml') -Value 'analyzer: {}' -Encoding utf8
    Copy-Item -LiteralPath (Join-Path $workspace 'lib/generated/bilibili') -Destination (Join-Path $scratch 'lib') -Recurse

    Push-Location -LiteralPath $scratch
    try {
        fvm dart analyze lib
        if ($LASTEXITCODE -ne 0) { throw "协议静态分析失败，退出码 $LASTEXITCODE。" }
    }
    finally {
        Pop-Location
    }
}
finally {
    $resolvedScratch = (Resolve-Path -LiteralPath $scratch).Path
    if ([IO.Path]::GetDirectoryName($resolvedScratch) -eq (Resolve-Path -LiteralPath $build).Path) {
        Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
    }
}
