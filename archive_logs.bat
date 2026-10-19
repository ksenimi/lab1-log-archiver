@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 1251 >nul

rem Аргументы: папка логов, папка архивов, порог в %, лимит в МиБ.
if "%~1"=="" goto bad_args
if "%~2"=="" goto bad_args
if "%~3"=="" goto bad_args
if "%~4"=="" goto bad_args
if not "%~5"=="" goto bad_args

if not exist "%~1\." (
    echo Error: the log folder does not exist.
    exit /b 2
)

echo(%~3| findstr /R /C:"^[0-9]$" /C:"^[1-9][0-9]$" /C:"^100$" >nul
if errorlevel 1 (
    echo Error: threshold must be an integer from 0 to 100.
    exit /b 2
)

echo(%~4| findstr /R /C:"^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo Error: limit must be a positive integer in MiB.
    exit /b 2
)

for %%D in ("%~1") do set "LOG_DIR=%%~fD"
for %%D in ("%~2") do set "BACKUP_DIR=%%~fD"
set "THRESHOLD=%~3"
set "LIMIT_MIB=%~4"

if /I "%LOG_DIR%"=="%BACKUP_DIR%" goto bad_backup
powershell -NoProfile -Command "$p=($env:LOG_DIR).TrimEnd('\') + '\'; if (($env:BACKUP_DIR).StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { exit 2 }"
if errorlevel 1 goto bad_backup

rem Временные списки нужны для сортировки и передачи имён программе tar.
:choose_work_name
set "WORK=%TEMP%\lab1_%RANDOM%_%RANDOM%"
set "CATALOG=%WORK%.txt"
if exist "%CATALOG%" goto choose_work_name
set "SORTED=%WORK%.sorted"
set "SELECTED=%WORK%.selected"

type nul > "%CATALOG%"
if errorlevel 1 goto work_error
type nul > "%SELECTED%"
if errorlevel 1 goto work_error

set "TOTAL_MIB=0"
set "TOTAL_REM=0"

rem /S обходит подпапки. В список попадают только файлы.
for /f "tokens=1-3,*" %%A in ('forfiles /P "%LOG_DIR%" /S /C "cmd /c if @isdir==FALSE echo @fdate @ftime @fsize @relpath" 2^>nul') do call :add_file "%%A" "%%B" "%%C" "%%~D"

rem Сравниваем размер с порогом без округления до целых МиБ.
set /a "TARGET100=LIMIT_MIB*THRESHOLD"
set /a "TARGET_MIB=TARGET100/100"
set /a "TARGET_REM=(TARGET100-TARGET_MIB*100)*1048576/100"
set /a "PERCENT=(TOTAL_MIB*100+TOTAL_REM*100/1048576)/LIMIT_MIB"

echo Folder size: %TOTAL_MIB% MiB and %TOTAL_REM% bytes.
echo Occupancy: %PERCENT%%%

if %TOTAL_MIB% LSS %TARGET_MIB% goto no_archive
if %TOTAL_MIB% EQU %TARGET_MIB% if %TOTAL_REM% LEQ %TARGET_REM% goto no_archive

rem Дата записана в начале строки как ГГГГММДДЧЧММСС.
rem Поэтому sort ставит самые старые файлы первыми.
sort "%CATALOG%" /O "%SORTED%"
if errorlevel 1 goto work_error

set "NEED_FILES=1"
for /f "usebackq tokens=1,2,3 delims=|" %%A in ("%SORTED%") do call :select_file "%%B" "%%C"
if not exist "%BACKUP_DIR%\." (
    mkdir "%BACKUP_DIR%"
    if errorlevel 1 goto backup_error
)

set "COMPRESS=-z"
set "EXT=.tar.gz"
if "%LAB1_MAX_COMPRESSION%"=="1" (
    set "COMPRESS=--lzma"
    set "EXT=.tar.lzma"
)

:choose_archive_name
set "ARCHIVE=%BACKUP_DIR%\logs_%RANDOM%_%RANDOM%%EXT%"
if exist "%ARCHIVE%" goto choose_archive_name

rem Все выбранные файлы попадают в один архив.
tar -c %COMPRESS% -f "%ARCHIVE%" -C "%LOG_DIR%" -T "%SELECTED%"
if errorlevel 1 goto archive_error
tar -t %COMPRESS% -f "%ARCHIVE%" >nul
if errorlevel 1 goto archive_error

rem Исходные файлы удаляются только после проверки архива.
for /f "usebackq delims=" %%F in ("%SELECTED%") do (
    del /f /q /a "%LOG_DIR%\%%F" >nul 2>&1
    if exist "%LOG_DIR%\%%F" goto delete_error
)

echo Archive complete: "%ARCHIVE%"
call :cleanup
exit /b 0

:no_archive
echo Threshold not exceeded. No archive created.
call :cleanup
exit /b 0

:bad_args
echo Usage: archive_logs.bat LOG_FOLDER BACKUP_FOLDER THRESHOLD LIMIT_MIB
exit /b 2

:bad_backup
echo Error: backup folder must be outside the log folder.
exit /b 2

:work_error
echo Error: could not prepare the file lists.
call :cleanup
exit /b 1

:backup_error
echo Error: could not create the backup folder.
call :cleanup
exit /b 1

:archive_error
echo Error: archive could not be created or read. Original files remain.
if exist "%ARCHIVE%" del /q "%ARCHIVE%" >nul
call :cleanup
exit /b 1

:delete_error
echo Error: archive exists, but an original file could not be deleted.
call :cleanup
exit /b 1

:cleanup
if exist "%CATALOG%" del /q "%CATALOG%" >nul
if exist "%SORTED%" del /q "%SORTED%" >nul
if exist "%SELECTED%" del /q "%SELECTED%" >nul
exit /b 0

:add_file
set "FILE_DATE=%~1"
set "FILE_TIME=%~2"
set "FILE_SIZE=%~3"
set "REL_PATH=%~4"

rem Превращаем ДД.ММ.ГГГГ в ГГГГММДД для сортировки.
set "KEY=%FILE_DATE:~6,4%%FILE_DATE:~3,2%%FILE_DATE:~0,2%%FILE_TIME:~0,2%%FILE_TIME:~3,2%%FILE_TIME:~6,2%"
>> "%CATALOG%" <nul set /p "=%KEY%|%REL_PATH%|%FILE_SIZE%"
>> "%CATALOG%" echo(

call :split_size "%FILE_SIZE%"
set /a "TOTAL_MIB+=FILE_MIB, TOTAL_REM+=FILE_REM"
if %TOTAL_REM% GEQ 1048576 set /a "TOTAL_MIB+=1, TOTAL_REM-=1048576"
exit /b 0

:select_file
if "%NEED_FILES%"=="0" exit /b 0
set "REL_PATH=%~1"
set "REL_PATH=%REL_PATH:~2%"

rem В списке tar храним путь относительно папки логов.
>> "%SELECTED%" <nul set /p "=%REL_PATH%"
>> "%SELECTED%" echo(

call :split_size "%~2"
set /a "TOTAL_MIB-=FILE_MIB, TOTAL_REM-=FILE_REM"
if %TOTAL_REM% LSS 0 set /a "TOTAL_MIB-=1, TOTAL_REM+=1048576"

if %TOTAL_MIB% LSS %TARGET_MIB% set "NEED_FILES=0"
if %TOTAL_MIB% EQU %TARGET_MIB% if %TOTAL_REM% LEQ %TARGET_REM% set "NEED_FILES=0"
exit /b 0

:split_size
rem Разбираем размер по цифрам, чтобы не переполнить арифметику cmd
rem при чтении файла размером более 2 ГиБ.
set "DIGITS=%~1"
set "FILE_MIB=0"
set "FILE_REM=0"

:next_digit
if not defined DIGITS exit /b 0
set "DIGIT=%DIGITS:~0,1%"
set /a "NEXT=FILE_REM*10+DIGIT"
set /a "PART=NEXT/1048576"
set /a "FILE_MIB=FILE_MIB*10+PART"
set /a "FILE_REM=NEXT-PART*1048576"
set "DIGITS=%DIGITS:~1%"
goto next_digit