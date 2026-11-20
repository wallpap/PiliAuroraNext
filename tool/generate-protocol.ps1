param(
    [ValidateSet('fvm', 'path')]
    [string]$DartTool = 'fvm',
    [switch]$Write
)

$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$protocol = Join-Path $PSScriptRoot 'protocol'
$schema = Join-Path $protocol 'schema'
$generated = Join-Path $workspace 'lib/generated'
$version = '34.1'
$architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
$platform = if ($IsWindows -and $architecture -eq 'X64') {
    @{ Name = 'win64'; Sha256 = '6d7ebdc75e9c1f0026d4fb28f17ef1d0aae77d36744d83a9e052d79ba493724f' }
} elseif ($IsLinux -and $architecture -eq 'X64') {
    @{ Name = 'linux-x86_64'; Sha256 = 'af27ea66cd26938fe48587804ca7d4817457a08350021a1c6e23a27ccc8c6904' }
} else {
    throw "当前生成入口支持 Windows 和 Linux x64。当前架构为 $architecture。"
}

function Invoke-Dart {
    if ($DartTool -eq 'path') { dart @args }
    else { fvm dart @args }
    if ($LASTEXITCODE -ne 0) { throw "Dart 命令失败，退出码 $LASTEXITCODE。" }
}

$build = (New-Item -ItemType Directory -Path (Join-Path $workspace 'build') -Force).FullName
$scratch = (New-Item -ItemType Directory -Path (Join-Path $build "protocol-$([Guid]::NewGuid())")).FullName
try {
    $asset = "protoc-$version-$($platform.Name).zip"
    $archive = Join-Path $build $asset
    if (-not (Test-Path -LiteralPath $archive)) {
        $download = Join-Path $scratch $asset
        Invoke-WebRequest "https://github.com/protocolbuffers/protobuf/releases/download/v$version/$asset" -OutFile $download
        if ((Get-FileHash -LiteralPath $download).Hash -ne $platform.Sha256) { throw "$asset SHA-256 不匹配。" }
        Copy-Item -LiteralPath $download -Destination $archive
    }
    if ((Get-FileHash -LiteralPath $archive).Hash -ne $platform.Sha256) { throw "$asset SHA-256 不匹配。" }
    $compiler = Join-Path $scratch 'protoc'
    Expand-Archive -LiteralPath $archive -DestinationPath $compiler
    $suffix = if ($IsWindows) { '.exe' } else { '' }
    $protoc = Join-Path $compiler "bin/protoc$suffix"
    if ($IsLinux) {
        chmod +x $protoc
        if ($LASTEXITCODE -ne 0) { throw '无法为 protoc 设置执行权限。' }
    }
    $plugin = Join-Path $scratch "protoc-gen-dart$suffix"
    Copy-Item -LiteralPath (Join-Path $protocol 'pubspec.yaml'), (Join-Path $protocol 'pubspec.lock') -Destination $scratch
    Set-Content -LiteralPath (Join-Path $scratch 'generator.dart') -Encoding utf8 -Value @'
import 'dart:io';

import 'package:protoc_plugin/protoc.dart';

void main() => CodeGenerator(stdin, stdout).generate();
'@
    Push-Location -LiteralPath $scratch
    try {
        Invoke-Dart pub get --enforce-lockfile
        Invoke-Dart compile exe generator.dart -o $plugin
    } finally {
        Pop-Location
    }
    $output = (New-Item -ItemType Directory -Path (Join-Path $scratch 'output')).FullName
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $schema 'bilibili') -File -Recurse -Filter '*.proto' |
        ForEach-Object { [IO.Path]::GetRelativePath($schema, $_.FullName).Replace('\', '/') })
    if ($sources.Count -eq 0) { throw '未找到协议定义。' }
    [Array]::Sort($sources, [StringComparer]::Ordinal)
    & $protoc "--plugin=protoc-gen-dart=$plugin" "--proto_path=$schema" `
        "--proto_path=$(Join-Path $compiler 'include')" "--dart_out=$output" @sources
    if ($LASTEXITCODE -ne 0) { throw "protoc 退出码 $LASTEXITCODE。" }

    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $changed = [Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $output 'bilibili') -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($output, $file.FullName)
        [void]$paths.Add($relative)
        $target = Join-Path $generated $relative
        if ((Test-Path -LiteralPath $target) -and
            ([IO.File]::ReadAllText($target).Replace("`r`n", "`n") -ceq [IO.File]::ReadAllText($file.FullName))) {
            continue
        }
        $changed.Add($relative)
        if ($Write) {
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
    $stale = @(Get-ChildItem -LiteralPath (Join-Path $generated 'bilibili') -File -Recurse |
        ForEach-Object { [IO.Path]::GetRelativePath($generated, $_.FullName) } |
        Where-Object { -not $paths.Contains($_) })
    if ($stale.Count -gt 0) {
        throw "请核对并移除过期产物： $($stale -join ', ')"
    }
    if ($changed.Count -gt 0 -and -not $Write) {
        throw "协议产物与定义不同。运行本脚本并传入 -Write： $($changed -join ', ')"
    }
    Write-Host "协议产物共 $($paths.Count) 个，更新 $($changed.Count) 个。"
} finally {
    $resolvedScratch = (Resolve-Path -LiteralPath $scratch).Path
    if ([IO.Path]::GetDirectoryName($resolvedScratch) -eq (Resolve-Path -LiteralPath $build).Path) {
        Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
    }
}
