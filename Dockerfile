# Stage 1: unpack PostgreSQL client tools (psql, pg_restore, pg_isready) used
# by docker-entrypoint.ps1 to import db/onfinitycommunity.sql at container
# start. Built from a locally vendored zip (see vendor/README.md) rather than
# downloading inside the container - some Docker hosts (this one included)
# block outbound traffic from the container network even though the host
# itself has internet access, so a build-time download from inside the
# container isn't reliable. Kept in a separate stage so only the bin/ folder
# we need ends up in the final image, not the full ~350MB distribution.
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8 AS pgclient
COPY vendor/postgresql-client.zip C:/pgclient.zip
RUN Expand-Archive -Path 'C:\pgclient.zip' -DestinationPath 'C:\pgclient-extract' -Force; Remove-Item 'C:\pgclient.zip' -Force

FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8

WORKDIR /inetpub/wwwroot

# Remove default IIS files
RUN powershell -Command Remove-Item -Recurse -Force C:\inetpub\wwwroot\*

# Copy ERP files
COPY publish/ .

# Copy database SQL file
COPY db/ /app/db/

# The PostgreSQL client binaries below need the VC++ 2015-2022 x64
# redistributable (vcruntime140.dll / msvcp140.dll), which this base image
# doesn't include - without it psql/pg_restore/pg_isready fail to start at
# all (STATUS_DLL_NOT_FOUND).
COPY vendor/vc_redist.x64.exe C:/vc_redist.x64.exe
RUN $p = Start-Process -FilePath 'C:\vc_redist.x64.exe' -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru; if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "vc_redist install failed with exit code $($p.ExitCode)" }; Remove-Item 'C:\vc_redist.x64.exe' -Force

# Bring in the PostgreSQL client tools built in the pgclient stage above
COPY --from=pgclient C:/pgclient-extract/pgsql/bin C:/pgsql/bin
RUN [Environment]::SetEnvironmentVariable('PATH', $env:PATH + ';C:\pgsql\bin', 'Machine')

# Enable detailed IIS error pages for debugging
RUN powershell -Command "Import-Module WebAdministration; Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter 'system.webServer/httpErrors' -name errorMode -value Detailed"

# W3SVC starts Automatic by default, which lets IIS begin serving the site
# (with the image's baked-in web.config) before docker-entrypoint.ps1 has
# rewritten the DB connection string. Switch it to Manual so the entrypoint
# script is the only thing that starts it, after configuration is correct.
RUN Set-Service -Name W3SVC -StartupType Manual

# Copy entrypoint script
COPY docker-entrypoint.ps1 /

EXPOSE 80

# Run entrypoint script to configure IIS and start services at container startup
ENTRYPOINT ["powershell", "-File", "/docker-entrypoint.ps1"]
