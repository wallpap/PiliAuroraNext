param(
    [string]$OutputDirectory = 'build/playback-android-focus/competitor'
)

$ErrorActionPreference = 'Stop'
$sdk = $env:ANDROID_HOME ?? $env:ANDROID_SDK_ROOT
if (!$sdk) { throw '请设置 ANDROID_HOME 或 ANDROID_SDK_ROOT。' }
$tools = Join-Path $sdk 'build-tools/36.0.0'
$platform = Join-Path $sdk 'platforms/android-36/android.jar'
$source = Join-Path $PSScriptRoot 'fixtures/android_audio_focus'
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$classes = Join-Path $output 'classes'
$dex = Join-Path $output 'dex'
New-Item -ItemType Directory -Force $classes, $dex | Out-Null

& javac --release 8 -cp $platform -d $classes (Join-Path $source 'FocusActivity.java')
if ($LASTEXITCODE) { throw 'javac 编译失败。' }
$activity = Join-Path $classes 'local/piliaurora/audiofocusfixture/FocusActivity.class'
& (Join-Path $tools 'd8.bat') --min-api 26 --lib $platform --output $dex $activity
if ($LASTEXITCODE) { throw 'D8 装配失败。' }

$unsigned = Join-Path $output 'unsigned.apk'
$aligned = Join-Path $output 'aligned.apk'
$apk = Join-Path $output 'focus-competitor.apk'
& (Join-Path $tools 'aapt2.exe') link -I $platform --manifest (Join-Path $source 'AndroidManifest.xml') -o $unsigned
if ($LASTEXITCODE) { throw 'aapt2 装配失败。' }
& jar --update --file $unsigned -C $dex classes.dex
if ($LASTEXITCODE) { throw 'DEX 写入失败。' }
& (Join-Path $tools 'zipalign.exe') -f 4 $unsigned $aligned
if ($LASTEXITCODE) { throw 'APK 对齐失败。' }

$keystore = Join-Path $output 'fixture-debug.jks'
if (!(Test-Path -LiteralPath $keystore)) {
    & keytool -genkeypair -keystore $keystore -storepass android -keypass android -alias fixture -keyalg RSA -keysize 2048 -validity 3650 -dname 'CN=Pili Audio Focus Fixture'
    if ($LASTEXITCODE) { throw '测试密钥生成失败。' }
}
$signer = Join-Path $tools 'apksigner.bat'
& $signer sign --ks $keystore --ks-pass pass:android --key-pass pass:android --out $apk $aligned
if ($LASTEXITCODE) { throw '测试 APK 签名失败。' }
& $signer verify $apk
if ($LASTEXITCODE) { throw '测试 APK 签名校验失败。' }
$apk
