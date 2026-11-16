param([ValidateSet('debug', 'check', 'release', 'device')][string]$Mode = 'debug')
$ErrorActionPreference = 'Stop'
# Use JAVA_HOME or the Java installation already on PATH.
Push-Location $PSScriptRoot
try {
    [string[]]$gradleTasks = @(switch ($Mode) {
        'debug' { @(':app:assembleDebug') }
        'check' { @(':app:testDebugUnitTest', ':app:lintDebug') }
        'release' { @(':app:assembleRelease') }
        'device' { @(':app:connectedDebugAndroidTest') }
    })
    & .\gradlew.bat @gradleTasks --console=plain
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally { Pop-Location }
