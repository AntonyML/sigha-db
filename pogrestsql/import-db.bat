@echo off
set CONTAINER=notifuse-postgres-1
set DB_USER=postgres
set BACKUP_FILE=backup_all.sql

if not exist %BACKUP_FILE% (
    echo No se encontro el archivo %BACKUP_FILE%.
    pause
    exit /b
)

echo Restaurando todas las bases de datos...
docker exec -i %CONTAINER% psql -U %DB_USER% -f - < %BACKUP_FILE%

if %errorlevel%==0 (
    echo Respaldo importado correctamente.
) else (
    echo Error al importar el respaldo.
)
pause
