$ErrorActionPreference = 'Stop'

# Local credential loader for Android builds.
# Reads local_*.env (git-ignored) and injects Dart defines so that
# String.fromEnvironment picks them up during flutter build.
function Read-LocalEnv {
    $file = Join-Path $PSScriptRoot '..\local_dandan_credentials.env'
    if (-not (Test-Path -LiteralPath $file)) {
        Write-Warning "Missing $file ; building without dart defines."
        return @{}
    }
    $map = @{}
    Get-Content -LiteralPath $file | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
            $map[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $map
}

$envVars = Read-LocalEnv

$defines = @()
foreach ($k in @('DANDANAPI_APPID', 'DANDANAPI_KEY')) {
    if ($envVars.ContainsKey($k) -and $envVars[$k]) {
        $defines += "--dart-define=$k=$($envVars[$k])"
    }
}

$argsList = @('build', 'apk', '--release') + $defines
Write-Host "Running: flutter $($argsList -join ' ')"
& flutter @argsList
exit $LASTEXITCODE