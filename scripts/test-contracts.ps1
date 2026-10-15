$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pythonCommand = Join-Path $projectRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonCommand)) { throw 'Create .venv and install requirements.txt first.' }
Push-Location -LiteralPath $projectRoot
try {
    & $pythonCommand scripts/sync_swift_contracts.py --check
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $pythonCommand -m unittest discover -v
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally { Pop-Location }
