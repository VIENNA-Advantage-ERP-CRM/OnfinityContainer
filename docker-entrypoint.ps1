$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Set permissions
Write-Host "Setting permissions on C:\inetpub\wwwroot..."
try {
    & icacls "C:\inetpub\wwwroot" /grant "IIS_IUSRS:(OI)(CI)F" /T /C
    & icacls "C:\inetpub\wwwroot" /grant "IUSR:(OI)(CI)F" /T /C
    & icacls "C:\inetpub\wwwroot" /grant "NETWORK SERVICE:(OI)(CI)F" /T /C
    Write-Host "Permissions set successfully"
} catch {
    Write-Host "Warning: Could not set permissions: $_"
}

# Set database environment variables with defaults
if (!$env:POSTGRES_HOST) { $env:POSTGRES_HOST = 'postgres' }
if (!$env:POSTGRES_USER) { $env:POSTGRES_USER = 'viennacrmuser' }
if (!$env:POSTGRES_PASSWORD) { $env:POSTGRES_PASSWORD = 'changeme' }
if (!$env:POSTGRES_DB) { $env:POSTGRES_DB = 'onfinitydb' }
if (!$env:DB_PORT) { $env:DB_PORT = '5432' }

Write-Host "Using PostgreSQL connection settings:"
Write-Host "  Host: $env:POSTGRES_HOST"
Write-Host "  User: $env:POSTGRES_USER"
Write-Host "  Database: $env:POSTGRES_DB"
Write-Host "  Port: $env:DB_PORT"

$env:PGPASSWORD = $env:POSTGRES_PASSWORD

# Wait for PostgreSQL to accept connections before touching it (the bundled
# container in docker-compose.yml can take a few seconds after "docker
# compose up" before it's ready).
Write-Host "Waiting for PostgreSQL at $($env:POSTGRES_HOST):$($env:DB_PORT)..."
$pgReady = $false
for ($i = 0; $i -lt 30; $i++) {
    & pg_isready -h $env:POSTGRES_HOST -p $env:DB_PORT -U $env:POSTGRES_USER -d $env:POSTGRES_DB *> $null
    if ($LASTEXITCODE -eq 0) { $pgReady = $true; break }
    Start-Sleep -Seconds 2
}
if ($pgReady) {
    Write-Host "PostgreSQL is ready."
} else {
    Write-Host "Warning: PostgreSQL was not reachable after 60s; import/connection may fail."
}

# Import database if it exists and is not already imported
# Note: onfinitycommunity.sql is a PostgreSQL *custom-format* dump
# (pg_dump -Fc), not plain SQL text, so it must be loaded with pg_restore -
# psql -f cannot parse it.
$dbImportFile = 'C:\app\db\onfinitycommunity.sql'
$dbImportMarker = 'C:\inetpub\wwwroot\.db-imported'

if ((Test-Path $dbImportFile) -and (-not (Test-Path $dbImportMarker))) {
    Write-Host "Importing database from $dbImportFile..."
    try {
        # Check if database has tables (simple check)
        $checkTablesQuery = "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema');"

        $tableCount = & psql -h $env:POSTGRES_HOST -U $env:POSTGRES_USER -d $env:POSTGRES_DB -p $env:DB_PORT -t -c $checkTablesQuery 2>$null | Select-Object -First 1

        if ([string]::IsNullOrWhiteSpace($tableCount) -or [int]$tableCount -eq 0) {
            Write-Host "Database is empty. Restoring schema and data with pg_restore..."
            # pg_restore reports harmless per-statement issues (e.g. the
            # "public" schema already existing) on stderr and keeps going.
            # With $ErrorActionPreference = 'Stop' (set above), merging that
            # stderr into the pipeline via 2>&1 turns the very first such
            # line into a terminating exception, aborting the restore after
            # only a few objects. Relax it just for this call so pg_restore
            # can run to completion; actual success is verified afterward by
            # re-checking the table count, not by this call's exit code.
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & pg_restore -h $env:POSTGRES_HOST -U $env:POSTGRES_USER -d $env:POSTGRES_DB -p $env:DB_PORT --no-owner --no-privileges -j 4 $dbImportFile 2>&1 | ForEach-Object { Write-Host $_ }
            $ErrorActionPreference = $prevEAP

            # pg_restore reports a non-zero exit / "errors ignored" for
            # harmless things like the pre-existing "public" schema, so
            # verify success by re-checking the table count instead of
            # trusting its exit code alone.
            $tableCountAfter = & psql -h $env:POSTGRES_HOST -U $env:POSTGRES_USER -d $env:POSTGRES_DB -p $env:DB_PORT -t -c $checkTablesQuery 2>$null | Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace($tableCountAfter) -and [int]$tableCountAfter -gt 0) {
                Write-Host "Database import completed successfully ($([int]$tableCountAfter) tables)"
                New-Item -Path $dbImportMarker -ItemType File -Force | Out-Null
            } else {
                Write-Host "Warning: pg_restore ran but no tables were found afterward - import did not take effect. Will retry on next container start."
            }
        } else {
            Write-Host "Database already has tables ($tableCount found). Skipping import."
            New-Item -Path $dbImportMarker -ItemType File -Force | Out-Null
        }
    } catch {
        Write-Host "Warning: Could not import database: $_"
    }
} elseif (-not (Test-Path $dbImportFile)) {
    Write-Host "Database SQL file not found at $dbImportFile"
}

# Update web.config with connection string
$configPath = 'C:\inetpub\wwwroot\web.config'
if (Test-Path $configPath) {
    $xml = [xml](Get-Content $configPath)
    $connectionString = "Server=$env:POSTGRES_HOST;Port=$env:DB_PORT;MaxPoolSize=100;SearchPath=public;User Id=$env:POSTGRES_USER;Password=$env:POSTGRES_PASSWORD;Database=$env:POSTGRES_DB"
    
    $xml.configuration.appSettings.add | Where-Object { $_.key -eq 'postgresqlConnectionString' } | ForEach-Object {
        $_.value = $connectionString
    }
    
    $xml.Save($configPath)
    Write-Host "Updated web.config with PostgreSQL connection string"
} else {
    Write-Host "Warning: web.config not found at $configPath"
}

# Configure IIS Application Pool
Write-Host "Configuring IIS Application Pool..."
try {
    Import-Module WebAdministration
    Set-ItemProperty IIS:\AppPools\DefaultAppPool -Name managedRuntimeVersion -Value "v4.0"
    Set-ItemProperty IIS:\AppPools\DefaultAppPool -Name processModel.identityType -Value "NetworkService"
    Set-ItemProperty IIS:\AppPools\DefaultAppPool -Name processModel.idleTimeout -Value ([TimeSpan]::FromMinutes(20))
    Write-Host "IIS Application Pool configured"
} catch {
    Write-Host "Warning: Could not configure IIS: $_"
}

# Start IIS
Write-Host "Starting IIS..."
Start-Service W3SVC

Write-Host "IIS started successfully. Container is running."

# Keep container running
while ($true) { Start-Sleep -Seconds 3600 }
