@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Основной скрипт лежит рядом с тестами.
set "ARCHIVER=%~dp0archive_logs.bat"
if not exist "%ARCHIVER%" (
    echo Error: archive_logs.bat was not found.
    exit /b 2
)

rem Создаём отдельную папку для тестовых данных.
:choose_test_root
set "TEST_ROOT=%TEMP%\lab1-windows-test-%RANDOM%-%RANDOM%"
if exist "%TEST_ROOT%" goto choose_test_root
for %%D in ("%TEST_ROOT%") do set "TEST_ROOT=%%~fD"

mkdir "%TEST_ROOT%"
if errorlevel 1 (
    echo Error: could not create the test folder.
    exit /b 1
)

set "LOG_DIR=%TEST_ROOT%\log"
set "BACKUP_DIR=%TEST_ROOT%\backup"
set "LAB1_MAX_COMPRESSION="
set "PASSED=0"
set "FAILED=0"

rem Проверяем пути до удаления временных папок.
for %%D in ("%LOG_DIR%\..") do if /I not "%%~fD"=="%TEST_ROOT%" exit /b 1
for %%D in ("%BACKUP_DIR%\..") do if /I not "%%~fD"=="%TEST_ROOT%" exit /b 1

echo Testing archive_logs.bat
echo Test data: "%TEST_ROOT%"


rem ==================================================
rem Тест 1. Порог не превышен
rem 520 МиБ из 600 МиБ меньше порога 90%.
rem ==================================================

echo Test 1: threshold not exceeded
set "OK=1"
mkdir "%LOG_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"
mkdir "%BACKUP_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"

call :make_file "%LOG_DIR%\file1.log" 260
if errorlevel 1 set "OK=0"
call :make_file "%LOG_DIR%\file2.log" 260
if errorlevel 1 set "OK=0"

call "%ARCHIVER%" "%LOG_DIR%" "%BACKUP_DIR%" 90 600 > "%TEST_ROOT%\output.txt" 2>&1
if errorlevel 1 set "OK=0"

if not exist "%LOG_DIR%\file1.log" set "OK=0"
if not exist "%LOG_DIR%\file2.log" set "OK=0"

set /a "LOG_BYTES=0"
for %%F in ("%LOG_DIR%\*.log") do if exist "%%~fF" set /a "LOG_BYTES+=%%~zF" >nul
if not "%LOG_BYTES%"=="545259520" set "OK=0"

for %%F in ("%BACKUP_DIR%\*") do if exist "%%~fF" set "OK=0"

if "%OK%"=="1" (
    echo PASS: no archive; both files remain.
    set /a "PASSED+=1" >nul
) else (
    echo FAIL: threshold not exceeded.
    type "%TEST_ROOT%\output.txt"
    set /a "FAILED+=1" >nul
)

rmdir /s /q "%LOG_DIR%" >nul 2>&1
rmdir /s /q "%BACKUP_DIR%" >nul 2>&1


rem ==================================================
rem Тест 2. Порог превышен
rem 600 МиБ из 600 МиБ больше порога 70%.
rem ==================================================

echo Test 2: threshold exceeded
set "OK=1"
mkdir "%LOG_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"
mkdir "%BACKUP_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"

call :make_file "%LOG_DIR%\file1.log" 300
if errorlevel 1 set "OK=0"
call :make_file "%LOG_DIR%\file2.log" 300
if errorlevel 1 set "OK=0"

call "%ARCHIVER%" "%LOG_DIR%" "%BACKUP_DIR%" 70 600 > "%TEST_ROOT%\output.txt" 2>&1
if errorlevel 1 set "OK=0"

set "ARCHIVE="
set "ARCHIVE_COUNT=0"
for %%F in ("%BACKUP_DIR%\*.tar.gz") do if exist "%%~fF" (
    set /a "ARCHIVE_COUNT+=1" >nul
    set "ARCHIVE=%%~fF"
)
if not "%ARCHIVE_COUNT%"=="1" set "OK=0"

set "REMOVED="
if not exist "%LOG_DIR%\file1.log" if exist "%LOG_DIR%\file2.log" set "REMOVED=file1.log"
if exist "%LOG_DIR%\file1.log" if not exist "%LOG_DIR%\file2.log" set "REMOVED=file2.log"
if not defined REMOVED set "OK=0"

if defined ARCHIVE (
    tar -tzf "%ARCHIVE%" >nul 2>&1
    if errorlevel 1 set "OK=0"
)
if defined ARCHIVE if defined REMOVED (
    tar -tf "%ARCHIVE%" | findstr /L /X /C:"%REMOVED%" >nul
    if errorlevel 1 set "OK=0"
)

set /a "LOG_BYTES=0"
for %%F in ("%LOG_DIR%\*.log") do if exist "%%~fF" set /a "LOG_BYTES+=%%~zF" >nul
if %LOG_BYTES% GTR 440401920 set "OK=0"

if "%OK%"=="1" (
    echo PASS: one file archived; folder size is below the threshold.
    set /a "PASSED+=1" >nul
) else (
    echo FAIL: threshold exceeded.
    type "%TEST_ROOT%\output.txt"
    set /a "FAILED+=1" >nul
)

rmdir /s /q "%LOG_DIR%" >nul 2>&1
rmdir /s /q "%BACKUP_DIR%" >nul 2>&1


rem ==================================================
rem Тест 3. Другой порог меняет результат
rem Те же 520 МиБ, но теперь порог 80%.
rem ==================================================

echo Test 3: different threshold
set "OK=1"
mkdir "%LOG_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"
mkdir "%BACKUP_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"

call :make_file "%LOG_DIR%\file1.log" 260
if errorlevel 1 set "OK=0"
call :make_file "%LOG_DIR%\file2.log" 260
if errorlevel 1 set "OK=0"

call "%ARCHIVER%" "%LOG_DIR%" "%BACKUP_DIR%" 80 600 > "%TEST_ROOT%\output.txt" 2>&1
if errorlevel 1 set "OK=0"

set "ARCHIVE="
set "ARCHIVE_COUNT=0"
for %%F in ("%BACKUP_DIR%\*.tar.gz") do if exist "%%~fF" (
    set /a "ARCHIVE_COUNT+=1" >nul
    set "ARCHIVE=%%~fF"
)
if not "%ARCHIVE_COUNT%"=="1" set "OK=0"

set "REMOVED="
if not exist "%LOG_DIR%\file1.log" if exist "%LOG_DIR%\file2.log" set "REMOVED=file1.log"
if exist "%LOG_DIR%\file1.log" if not exist "%LOG_DIR%\file2.log" set "REMOVED=file2.log"
if not defined REMOVED set "OK=0"

if defined ARCHIVE (
    tar -tzf "%ARCHIVE%" >nul 2>&1
    if errorlevel 1 set "OK=0"
)
if defined ARCHIVE if defined REMOVED (
    tar -tf "%ARCHIVE%" | findstr /L /X /C:"%REMOVED%" >nul
    if errorlevel 1 set "OK=0"
)

set /a "LOG_BYTES=0"
for %%F in ("%LOG_DIR%\*.log") do if exist "%%~fF" set /a "LOG_BYTES+=%%~zF" >nul
if %LOG_BYTES% GTR 503316480 set "OK=0"

if "%OK%"=="1" (
    echo PASS: threshold 80 causes archiving.
    set /a "PASSED+=1" >nul
) else (
    echo FAIL: different threshold.
    type "%TEST_ROOT%\output.txt"
    set /a "FAILED+=1" >nul
)

rmdir /s /q "%LOG_DIR%" >nul 2>&1
rmdir /s /q "%BACKUP_DIR%" >nul 2>&1


rem ==================================================
rem Тест 4. Выбираются самые старые файлы
rem Даты и размеры такие же, как у Арины.
rem ==================================================

echo Test 4: oldest files
set "OK=1"
mkdir "%LOG_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"
mkdir "%BACKUP_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"

call :make_file "%LOG_DIR%\old.log" 100
if errorlevel 1 set "OK=0"
call :make_file "%LOG_DIR%\middle.log" 100
if errorlevel 1 set "OK=0"
call :make_file "%LOG_DIR%\new.log" 100
if errorlevel 1 set "OK=0"
call :make_file "%LOG_DIR%\big.log" 300
if errorlevel 1 set "OK=0"

powershell -NoProfile -Command "(Get-Item -LiteralPath (Join-Path $env:LOG_DIR 'old.log')).LastWriteTime=[datetime]::new(2020,1,1,10,0,0)"
if errorlevel 1 set "OK=0"
powershell -NoProfile -Command "(Get-Item -LiteralPath (Join-Path $env:LOG_DIR 'middle.log')).LastWriteTime=[datetime]::new(2021,1,1,10,0,0)"
if errorlevel 1 set "OK=0"
powershell -NoProfile -Command "(Get-Item -LiteralPath (Join-Path $env:LOG_DIR 'new.log')).LastWriteTime=[datetime]::new(2022,1,1,10,0,0)"
if errorlevel 1 set "OK=0"
powershell -NoProfile -Command "(Get-Item -LiteralPath (Join-Path $env:LOG_DIR 'big.log')).LastWriteTime=[datetime]::new(2023,1,1,10,0,0)"
if errorlevel 1 set "OK=0"

call "%ARCHIVER%" "%LOG_DIR%" "%BACKUP_DIR%" 70 600 > "%TEST_ROOT%\output.txt" 2>&1
if errorlevel 1 set "OK=0"

set "ARCHIVE="
set "ARCHIVE_COUNT=0"
for %%F in ("%BACKUP_DIR%\*.tar.gz") do if exist "%%~fF" (
    set /a "ARCHIVE_COUNT+=1" >nul
    set "ARCHIVE=%%~fF"
)
if not "%ARCHIVE_COUNT%"=="1" set "OK=0"

if exist "%LOG_DIR%\old.log" set "OK=0"
if exist "%LOG_DIR%\middle.log" set "OK=0"
if not exist "%LOG_DIR%\new.log" set "OK=0"
if not exist "%LOG_DIR%\big.log" set "OK=0"

if defined ARCHIVE (
    tar -tzf "%ARCHIVE%" >nul 2>&1
    if errorlevel 1 set "OK=0"

    tar -tf "%ARCHIVE%" | findstr /L /X /C:"old.log" >nul
    if errorlevel 1 set "OK=0"
    tar -tf "%ARCHIVE%" | findstr /L /X /C:"middle.log" >nul
    if errorlevel 1 set "OK=0"

    tar -tf "%ARCHIVE%" | findstr /L /X /C:"new.log" >nul
    if not errorlevel 1 set "OK=0"
    tar -tf "%ARCHIVE%" | findstr /L /X /C:"big.log" >nul
    if not errorlevel 1 set "OK=0"
)

set /a "LOG_BYTES=0"
for %%F in ("%LOG_DIR%\*.log") do if exist "%%~fF" set /a "LOG_BYTES+=%%~zF" >nul
if %LOG_BYTES% GTR 440401920 set "OK=0"

if "%OK%"=="1" (
    echo PASS: old and middle were archived; new and big remain.
    set /a "PASSED+=1" >nul
) else (
    echo FAIL: oldest files.
    type "%TEST_ROOT%\output.txt"
    set /a "FAILED+=1" >nul
)

rmdir /s /q "%LOG_DIR%" >nul 2>&1
rmdir /s /q "%BACKUP_DIR%" >nul 2>&1


rem ==================================================
rem Тест 5. Ошибка подготовки папки архивов
rem Вместо папки передаётся обычный файл.
rem ==================================================

echo Test 5: backup folder error
set "OK=1"
mkdir "%LOG_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"
mkdir "%BACKUP_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"

call :make_file "%LOG_DIR%\file1.log" 300
if errorlevel 1 set "OK=0"
call :make_file "%LOG_DIR%\file2.log" 300
if errorlevel 1 set "OK=0"

set "BAD_BACKUP=%TEST_ROOT%\not_a_directory"
type nul > "%BAD_BACKUP%"
if errorlevel 1 set "OK=0"

call "%ARCHIVER%" "%LOG_DIR%" "%BAD_BACKUP%" 70 600 > "%TEST_ROOT%\output.txt" 2>&1
if not errorlevel 1 set "OK=0"

if not exist "%BAD_BACKUP%" set "OK=0"
if not exist "%LOG_DIR%\file1.log" set "OK=0"
if not exist "%LOG_DIR%\file2.log" set "OK=0"

set /a "LOG_BYTES=0"
for %%F in ("%LOG_DIR%\*.log") do if exist "%%~fF" set /a "LOG_BYTES+=%%~zF" >nul
if not "%LOG_BYTES%"=="629145600" set "OK=0"

if "%OK%"=="1" (
    echo PASS: error returned; original files remain.
    set /a "PASSED+=1" >nul
) else (
    echo FAIL: backup folder error.
    type "%TEST_ROOT%\output.txt"
    set /a "FAILED+=1" >nul
)

rmdir /s /q "%LOG_DIR%" >nul 2>&1
rmdir /s /q "%BACKUP_DIR%" >nul 2>&1
del /q "%BAD_BACKUP%" >nul 2>&1


rem ==================================================
rem Тест 6. LZMA
rem 600 МиБ и порог 70%, как в тесте Арины.
rem ==================================================

echo Test 6: LZMA
set "OK=1"
mkdir "%LOG_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"
mkdir "%BACKUP_DIR%" >nul 2>&1
if errorlevel 1 set "OK=0"

call :make_file "%LOG_DIR%\file1.log" 300
if errorlevel 1 set "OK=0"
call :make_file "%LOG_DIR%\file2.log" 300
if errorlevel 1 set "OK=0"

set "LAB1_MAX_COMPRESSION=1"
call "%ARCHIVER%" "%LOG_DIR%" "%BACKUP_DIR%" 70 600 > "%TEST_ROOT%\output.txt" 2>&1
if errorlevel 1 set "OK=0"
set "LAB1_MAX_COMPRESSION="

set "ARCHIVE="
set "ARCHIVE_COUNT=0"
for %%F in ("%BACKUP_DIR%\*.tar.lzma") do if exist "%%~fF" (
    set /a "ARCHIVE_COUNT+=1" >nul
    set "ARCHIVE=%%~fF"
)
if not "%ARCHIVE_COUNT%"=="1" set "OK=0"

if defined ARCHIVE (
    tar -t --lzma -f "%ARCHIVE%" >nul 2>&1
    if errorlevel 1 set "OK=0"
)

set "REMOVED="
if not exist "%LOG_DIR%\file1.log" if exist "%LOG_DIR%\file2.log" set "REMOVED=file1.log"
if exist "%LOG_DIR%\file1.log" if not exist "%LOG_DIR%\file2.log" set "REMOVED=file2.log"
if not defined REMOVED set "OK=0"

set /a "LOG_BYTES=0"
for %%F in ("%LOG_DIR%\*.log") do if exist "%%~fF" set /a "LOG_BYTES+=%%~zF" >nul
if %LOG_BYTES% GTR 440401920 set "OK=0"

if "%OK%"=="1" (
    echo PASS: LZMA archive is readable; folder size is below the threshold.
    set /a "PASSED+=1" >nul
) else (
    echo FAIL: LZMA.
    type "%TEST_ROOT%\output.txt"
    set /a "FAILED+=1" >nul
)

rmdir /s /q "%LOG_DIR%" >nul 2>&1
rmdir /s /q "%BACKUP_DIR%" >nul 2>&1
del /q "%TEST_ROOT%\output.txt" >nul 2>&1
rmdir "%TEST_ROOT%" >nul 2>&1
if exist "%TEST_ROOT%\." (
    echo Error: test data could not be removed: "%TEST_ROOT%".
    exit /b 1
)

echo Passed: %PASSED%
echo Failed: %FAILED%
if not "%FAILED%"=="0" exit /b 1
echo All 6 tests passed.
exit /b 0


:make_file
rem Создаём файл указанного размера в МиБ.
set "FILE_PATH=%~1"
set "FILE_MIB=%~2"
powershell -NoProfile -Command "try { $f=[IO.File]::Create($env:FILE_PATH); try { $f.SetLength([long]$env:FILE_MIB * 1MB) } finally { $f.Dispose() } } catch { Write-Error $_; exit 1 }" >nul
exit /b %errorlevel%