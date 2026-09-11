# Downloads the two build inputs the Dockerfile needs but can't reliably
# fetch from inside a Windows container build step (some Docker hosts block
# outbound traffic from the container network even when the host itself is
# online):
#   - PostgreSQL Windows client tools (psql, pg_restore, pg_isready), used by
#     docker-entrypoint.ps1 for the automatic database import.
#   - The VC++ 2015-2022 x64 redistributable those client tools need to run
#     at all (they fail with STATUS_DLL_NOT_FOUND without it).
# Run this once, on a machine with internet access, before `docker compose
# build`.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$files = @(
    @{ Url = 'https://get.enterprisedb.com/postgresql/postgresql-15.7-1-windows-x64-binaries.zip'; Name = 'postgresql-client.zip' }
    @{ Url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'; Name = 'vc_redist.x64.exe' }
)

foreach ($f in $files) {
    $dest = Join-Path $PSScriptRoot $f.Name
    if (Test-Path $dest) {
        Write-Host "Already present: $dest (delete it first to re-download)"
        continue
    }
    Write-Host "Downloading $($f.Name)..."
    Invoke-WebRequest -Uri $f.Url -OutFile $dest
    Write-Host "Saved to $dest"
}
