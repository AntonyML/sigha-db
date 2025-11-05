@echo off
set CONTAINER=notifuse-postgres-1
set DB_USER=postgres
set BACKUP_FILE=backup_all.sql

echo Creando respaldo de todas las bases de datos...
docker exec -t %CONTAINER% pg_dumpall -U %DB_USER% > %BACKUP_FILE%

if %errorlevel%==0 (
    echo Respaldo completo creado correctamente: %BACKUP_FILE%
) else (
    echo Error al crear el respaldo.
)
pause
