# Uber course work: creates UberDB (OLTP) + UberDW (Data Warehouse) and loads data.
# Usage:  .\install.ps1                      (local default instance, Windows authentication)
#         .\install.ps1 -Server ".\SQLEXPRESS"
param(
    [string]$Server = "localhost"
)

$ErrorActionPreference = "Stop"
$scripts = @(
    "01_create_oltp.sql",
    "02_programmability.sql",
    "03_seed_data.sql",
    "04_create_dw.sql",
    "05_etl_load_dw.sql"
)

foreach ($s in $scripts) {
    Write-Host "==> $s" -ForegroundColor Cyan
    & sqlcmd -S $Server -E -b -f 65001 -i (Join-Path $PSScriptRoot $s)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error while running $s" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host "Done: UberDB and UberDW are created and loaded." -ForegroundColor Green
