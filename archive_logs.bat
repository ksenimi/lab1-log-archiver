@echo off
setlocal

if "%~1"=="" (
    echo Error: specify the log folder.
    exit /b 2
)

if not exist "%~1\." (
    echo Error: the log folder does not exist.
    exit /b 2
)

if "%~2"=="" (
    echo Error: specify the backup folder.
    exit /b 2
)

if "%~3"=="" (
    echo Error: specify the threshold.
    exit /b 2
)

if "%~4"=="" (
    echo Error: specify the limit in MiB.
    exit /b 2
)

echo(%~3| findstr /R /C:"^[0-9]$" /C:"^[1-9][0-9]$" /C:"^100$" >nul
if errorlevel 1 (
    echo Error: threshold must be an integer from 0 to 100.
    exit /b 2
)
echo(%~4| findstr /R /C:"^[0-9]*[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo Error: limit must be a positive integer in MiB.
    exit /b 2
)
for %%D in ("%~1") do set "LOG_DIR=%%~fD"
for %%D in ("%~2") do set "BACKUP_DIR=%%~fD"
if /I "%LOG_DIR%"=="%BACKUP_DIR%" (
    echo Error: backup folder must be outside the log folder.
    exit /b 2
)
powershell -NoProfile -Command "$p=($env:LOG_DIR).TrimEnd('\') + '\'; if (($env:BACKUP_DIR).StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { exit 2 }"
if errorlevel 1 (
    echo Error: backup folder must be outside the log folder.
    exit /b 2
)
set "LIMIT_MIB=%~4"
set "THRESHOLD=%~3"
powershell -NoProfile -Command "try { $sum=[bigint]0; foreach ($f in Get-ChildItem -LiteralPath $env:LOG_DIR -Force -File -ErrorAction Stop) { if (-not ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $sum += [bigint]$f.Length } }; $limit=[bigint]$env:LIMIT_MIB * 1048576; $pct=[math]::Round([double]$sum * 100 / [double]$limit, 2); Write-Output ('Folder size: {0} bytes' -f $sum); Write-Output ('Occupancy: {0}%%' -f $pct); if ($sum * 100 -gt [bigint]$env:THRESHOLD * $limit) { exit 3 } else { exit 0 } } catch { Write-Error $_; exit 1 }"
set "CHECK_RESULT=%errorlevel%"
if "%CHECK_RESULT%"=="0" (
    echo Threshold not exceeded. No archive created.
    exit /b 0
)
if not "%CHECK_RESULT%"=="3" (
    echo Error: could not calculate folder size.
    exit /b 1
)
echo Threshold exceeded. Files selected for archive:
powershell -NoProfile -Command "try { $files=@(Get-ChildItem -LiteralPath $env:LOG_DIR -Force -File -ErrorAction Stop | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Sort-Object LastWriteTime, Name); $remaining=[bigint]0; foreach ($f in $files) { $remaining += [bigint]$f.Length }; $target=[bigint]$env:THRESHOLD * [bigint]$env:LIMIT_MIB * 1048576; foreach ($f in $files) { if ($remaining * 100 -le $target) { break }; Write-Output ('Selected: {0} ({1} bytes)' -f $f.Name, $f.Length); $remaining -= [bigint]$f.Length }; Write-Output ('Projected remaining after archive: {0} bytes' -f $remaining) } catch { Write-Error $_; exit 1 }"
if errorlevel 1 (
    echo Error: could not list log files.
    exit /b 1
)
if not exist "%BACKUP_DIR%\" (
    mkdir "%BACKUP_DIR%"
    if errorlevel 1 (
        echo Error: could not create backup folder.
        exit /b 1
    )
)
set "ARCHIVE_EXT=.tar.gz"
if "%LAB1_MAX_COMPRESSION%"=="1" set "ARCHIVE_EXT=.tar.lzma"
:choose_archive_name
set "ARCHIVE_PATH="
for /f %%G in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N')"') do set "ARCHIVE_PATH=%BACKUP_DIR%\logs_%%G%ARCHIVE_EXT%"
if not defined ARCHIVE_PATH (
    echo Error: could not create an archive name.
    exit /b 1
)
if exist "%ARCHIVE_PATH%" goto choose_archive_name
echo Archive path: "%ARCHIVE_PATH%"
powershell -NoProfile -Command "try { $archiveReady=$false; $files=@(Get-ChildItem -LiteralPath $env:LOG_DIR -Force -File -ErrorAction Stop | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Sort-Object LastWriteTime, Name); $remaining=[bigint]0; foreach ($f in $files) { $remaining += [bigint]$f.Length }; $target=[bigint]$env:THRESHOLD * [bigint]$env:LIMIT_MIB * 1048576; $selected=New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'; foreach ($f in $files) { if ($remaining * 100 -le $target) { break }; [void]$selected.Add($f); $remaining -= [bigint]$f.Length }; if ($selected.Count -eq 0) { throw 'No files selected' }; $names=[string[]]@($selected | ForEach-Object { $_.Name }); if ($env:LAB1_MAX_COMPRESSION -eq '1') { & tar.exe --lzma -cf $env:ARCHIVE_PATH -C $env:LOG_DIR -- @names } else { & tar.exe -czf $env:ARCHIVE_PATH -C $env:LOG_DIR -- @names }; if ($LASTEXITCODE -ne 0) { throw ('tar failed with code {0}' -f $LASTEXITCODE) }; $archive=Get-Item -LiteralPath $env:ARCHIVE_PATH -ErrorAction Stop; if ($archive.Length -eq 0) { throw 'Archive is empty' }; & tar.exe -tf $env:ARCHIVE_PATH | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Archive cannot be read' }; $archiveReady=$true; Write-Output ('Archive created and checked: {0}' -f $env:ARCHIVE_PATH); foreach ($f in $selected) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; Write-Output ('Deleted: {0}' -f $f.Name) } } catch { if (-not $archiveReady -and (Test-Path -LiteralPath $env:ARCHIVE_PATH)) { Remove-Item -LiteralPath $env:ARCHIVE_PATH -Force -ErrorAction SilentlyContinue }; Write-Error $_; exit 1 }"
if errorlevel 1 (
    echo Error: archiving failed.
    exit /b 1
)
echo Log folder: "%LOG_DIR%"
echo Backup folder: "%BACKUP_DIR%"
echo Threshold: %~3%%
echo Limit: %~4 MiB
echo Archive complete.
exit /b 0