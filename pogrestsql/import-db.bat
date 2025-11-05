@echo off
SETLOCAL EnableDelayedExpansion

set CONTAINER=notifuse-postgres-1
set DB_USER=postgres
set BACKUP_FILE=backup_all.sql
set TEMP_DB_LIST=temp_dbs.txt

:: Verificar que el archivo de backup exista
if not exist %BACKUP_FILE% (
    echo No se encontro el archivo %BACKUP_FILE%.
    pause
    exit /b
)

echo -----------------------------------------------
echo Detectando bases de datos en el backup...
echo -----------------------------------------------

:: Extraer nombres de bases de datos del backup (busca CREATE DATABASE)
findstr /R /C:"CREATE DATABASE" %BACKUP_FILE% > %TEMP_DB_LIST%

:: Preparar cada base de datos
for /f "tokens=3" %%a in (%TEMP_DB_LIST%) do (
    set DB_NAME=%%a
    :: Limpiar caracteres extras (; y ")
    set DB_NAME=!DB_NAME:;=!
    set DB_NAME=!DB_NAME:"=!
    
    echo -----------------------------------------------
    echo Preparando base de datos: !DB_NAME!
    echo -----------------------------------------------
    
    :: Crear la base si no existe (ignora error si ya existe)
    docker exec -i %CONTAINER% psql -U %DB_USER% -d postgres -c "CREATE DATABASE !DB_NAME!;" 2>nul
)

:: Eliminar archivo temporal
del %TEMP_DB_LIST%

echo -----------------------------------------------
echo Importando backup completo (ignorando errores de duplicados)...
echo -----------------------------------------------

:: Importar backup usando ON_ERROR_STOP=off para continuar ante errores
docker exec -i %CONTAINER% psql -U %DB_USER% -v ON_ERROR_STOP=off -f - < %BACKUP_FILE%

if %errorlevel%==0 (
    echo -----------------------------------------------
    echo Respaldo importado correctamente.
    echo -----------------------------------------------
) else (
    echo -----------------------------------------------
    echo Respaldo importado con advertencias (algunos objetos ya existian).
    echo -----------------------------------------------
)

pause
ENDLOCAL
