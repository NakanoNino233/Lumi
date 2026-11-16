$ErrorActionPreference = 'Stop'
$keytoolCommand = if ($env:JAVA_HOME) {
    Join-Path $env:JAVA_HOME 'bin/keytool.exe'
} else {
    (Get-Command keytool -ErrorAction Stop).Source
}
if (-not (Test-Path -LiteralPath $keytoolCommand)) { throw 'Set JAVA_HOME to a JDK installation that includes keytool.' }
$signingRoot = Join-Path $PSScriptRoot '.signing'
New-Item -ItemType Directory -Path $signingRoot -Force | Out-Null
$keyFile = Join-Path $signingRoot 'lumi-android.jks'
$propertiesFile = Join-Path $signingRoot 'keystore.properties'
if ((Test-Path -LiteralPath $keyFile) -and (Test-Path -LiteralPath $propertiesFile)) { Write-Output 'Existing personal signing key preserved.'; exit 0 }
if ((Test-Path -LiteralPath $keyFile) -or (Test-Path -LiteralPath $propertiesFile)) { throw 'Signing setup is incomplete; preserve and inspect existing files before continuing.' }
$randomBytes = New-Object byte[] 32
$randomSource = [Security.Cryptography.RandomNumberGenerator]::Create()
$randomSource.GetBytes($randomBytes)
$randomSource.Dispose()
$signingPassword = [Convert]::ToBase64String($randomBytes)
& $keytoolCommand -genkeypair -keystore $keyFile -storetype PKCS12 -alias lumi-android -keyalg RSA -keysize 3072 -validity 10000 -storepass $signingPassword -keypass $signingPassword -dname 'CN=Lumi Android Personal Port'
if ($LASTEXITCODE -ne 0) { throw 'Could not generate signing key' }
[IO.File]::WriteAllText($propertiesFile, "storeFile=.signing/lumi-android.jks`nstorePassword=$signingPassword`nkeyAlias=lumi-android`nkeyPassword=$signingPassword`n", [Text.UTF8Encoding]::new($false))
Write-Output 'Created personal signing key. Keep the .signing folder for future APK updates.'
