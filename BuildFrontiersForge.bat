@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem =====================================================================================
rem Generated with ChatGPT-5.2
rem File:        BuildFrontiersForge.bat
rem Description: Builds UiForge (git submodule), then copies UiForge/scripts -> scripts/.
rem              Optional: bundle a release zip.
rem
rem Usage:
rem   BuildFrontiersForge.bat
rem   BuildFrontiersForge.bat -zip -version 1.2.3
rem   BuildFrontiersForge.bat -package -version 1.2.3
rem   BuildFrontiersForge.bat -package 1.2.3
rem
rem Notes:
rem   - Requires the UiForge toolchain as configured by UiForge/build_uiforge.bat
rem   - Robocopy exit codes 0-7 are success; >=8 is failure
rem =====================================================================================

set "ROOT=%~dp0"
pushd "%ROOT%" >nul

set "DO_ZIP=0"
set "SKIP_BUILD=0"
set "SKIP_SYNC=0"
set "VERSION="

:parse_args
if "%~1"=="" goto args_done

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="/?" goto usage

if /I "%~1"=="-zip"  set "DO_ZIP=1" & shift & goto parse_args
if /I "%~1"=="/zip"  set "DO_ZIP=1" & shift & goto parse_args
if /I "%~1"=="--zip" set "DO_ZIP=1" & shift & goto parse_args

if /I "%~1"=="-package"  set "DO_ZIP=1" & set "SKIP_BUILD=1" & shift & goto parse_args
if /I "%~1"=="/package"  set "DO_ZIP=1" & set "SKIP_BUILD=1" & shift & goto parse_args
if /I "%~1"=="--package" set "DO_ZIP=1" & set "SKIP_BUILD=1" & shift & goto parse_args

if /I "%~1"=="-nobuild"   set "SKIP_BUILD=1" & shift & goto parse_args
if /I "%~1"=="--nobuild"  set "SKIP_BUILD=1" & shift & goto parse_args
if /I "%~1"=="-skipbuild" set "SKIP_BUILD=1" & shift & goto parse_args
if /I "%~1"=="--skipbuild" set "SKIP_BUILD=1" & shift & goto parse_args

if /I "%~1"=="-nosync"   set "SKIP_SYNC=1" & shift & goto parse_args
if /I "%~1"=="--nosync"  set "SKIP_SYNC=1" & shift & goto parse_args
if /I "%~1"=="-skipsync" set "SKIP_SYNC=1" & shift & goto parse_args
if /I "%~1"=="--skipsync" set "SKIP_SYNC=1" & shift & goto parse_args

if /I "%~1"=="-version"  set "VERSION=%~2" & shift & shift & goto parse_args
if /I "%~1"=="/version"  set "VERSION=%~2" & shift & shift & goto parse_args
if /I "%~1"=="--version" set "VERSION=%~2" & shift & shift & goto parse_args
if /I "%~1"=="-v"        set "VERSION=%~2" & shift & shift & goto parse_args

rem Convenience: a single positional version implies -zip
if "%VERSION%"=="" (
  set "VERSION=%~1"
  set "DO_ZIP=1"
  shift
  goto parse_args
)

echo ERROR: Unknown argument: %~1
goto usage_fail

:args_done
if "%DO_ZIP%"=="1" if "%VERSION%"=="" (
  echo ERROR: -zip requires -version x.x.x
  goto usage_fail
)

set "UIFORGE_DIR=%ROOT%UiForge"
if not exist "%UIFORGE_DIR%\" (
  echo ERROR: Missing UiForge submodule at "%UIFORGE_DIR%"
  echo        Did you clone with submodules? Try: git submodule update --init --recursive
  exit /b 1
)

if "%SKIP_BUILD%"=="1" (
  echo.
  echo === Skipping UiForge build - packaging pre-built files ===
) else (
  set "UIFORGE_BUILD_SCRIPT="
  if exist "%UIFORGE_DIR%\build_uiforge.bat" set "UIFORGE_BUILD_SCRIPT=build_uiforge.bat"

  rem NOTE: This block runs under parentheses; use delayed expansion for vars set inside.
  if "!UIFORGE_BUILD_SCRIPT!"=="" (
    echo ERROR: Could not find UiForge build script in "%UIFORGE_DIR%"
    exit /b 1
  )

  echo.
  echo === Building UiForge: !UIFORGE_BUILD_SCRIPT! ===
  pushd "%UIFORGE_DIR%" >nul
  call "!UIFORGE_BUILD_SCRIPT!"
  set "BUILD_RC=!ERRORLEVEL!"
  popd >nul
  if not "!BUILD_RC!"=="0" (
    echo ERROR: UiForge build failed with exit code !BUILD_RC!
    exit /b !BUILD_RC!
  )
)

if "%SKIP_SYNC%"=="1" (
  echo.
  echo === Skipping scripts sync ===
) else (
  echo.
  echo === Syncing scripts: UiForge\scripts to scripts ===
  if not exist "%UIFORGE_DIR%\scripts\" (
    echo ERROR: Missing "%UIFORGE_DIR%\scripts\"; cannot sync scripts
    exit /b 1
  )
  if not exist "%ROOT%scripts\" mkdir "%ROOT%scripts" >nul 2>&1
  robocopy "%UIFORGE_DIR%\scripts" "%ROOT%scripts" /E /R:2 /W:1 /NP /NFL /NDL /NJH /NJS
  set "ROBO_RC=!ERRORLEVEL!"
  if !ROBO_RC! GEQ 8 (
    echo ERROR: Robocopy failed with exit code !ROBO_RC!
    exit /b !ROBO_RC!
  )
)

if "%DO_ZIP%"=="1" (
  call :bundle_zip "%VERSION%"
  exit /b %ERRORLEVEL%
)

echo.
echo Done.
exit /b 0

:bundle_zip
setlocal
set "VER=%~1"
set "RELEASES_DIR=%ROOT%releases"
set "STAGING_DIR=%RELEASES_DIR%\_staging\FrontiersForge-v%VER%"
set "ZIP_PATH=%RELEASES_DIR%\FrontiersForge-v%VER%.zip"

echo.
echo === Bundling release zip (v%VER%) ===

if not exist "%RELEASES_DIR%\" mkdir "%RELEASES_DIR%" >nul 2>&1
if exist "%STAGING_DIR%\" rmdir /S /Q "%STAGING_DIR%"

mkdir "%STAGING_DIR%" >nul
mkdir "%STAGING_DIR%\scripts" >nul
mkdir "%STAGING_DIR%\UiForge\bin" >nul

copy /Y "%ROOT%LICENSE.txt" "%STAGING_DIR%\LICENSE.txt" >nul
copy /Y "%ROOT%README.md" "%STAGING_DIR%\README.md" >nul
copy /Y "%ROOT%config" "%STAGING_DIR%\config" >nul
copy /Y "%ROOT%StartFrontiersForge.bat" "%STAGING_DIR%\StartFrontiersForge.bat" >nul

if not exist "%ROOT%scripts\" (
  echo ERROR: Missing "%ROOT%scripts\". Run without -nosync, or create/sync scripts first.
  exit /b 1
)

robocopy "%ROOT%scripts" "%STAGING_DIR%\scripts" /E /R:2 /W:1 /NP /NFL /NDL /NJH /NJS
if %ERRORLEVEL% GEQ 8 (
  echo ERROR: Failed copying scripts into staging directory
  exit /b 1
)

if not exist "%ROOT%UiForge\UiForge.exe" (
  echo ERROR: Missing "%ROOT%UiForge\UiForge.exe"
  exit /b 1
)
if not exist "%ROOT%UiForge\bin\uiforge_core.dll" (
  echo ERROR: Missing "%ROOT%UiForge\bin\uiforge_core.dll"
  exit /b 1
)

copy /Y "%ROOT%UiForge\UiForge.exe" "%STAGING_DIR%\UiForge\UiForge.exe" >nul
copy /Y "%ROOT%UiForge\bin\uiforge_core.dll" "%STAGING_DIR%\UiForge\bin\uiforge_core.dll" >nul

if exist "%ZIP_PATH%" del /Q "%ZIP_PATH%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path '%STAGING_DIR%\*' -DestinationPath '%ZIP_PATH%' -Force" >nul
if not "%ERRORLEVEL%"=="0" (
  echo ERROR: Compress-Archive failed
  exit /b 1
)

echo Created: %ZIP_PATH%
if exist "%RELEASES_DIR%\_staging\" (
  attrib -R "%RELEASES_DIR%\_staging\*" /S /D >nul 2>&1
  rmdir /S /Q "%RELEASES_DIR%\_staging" >nul 2>&1
)
exit /b 0

:usage
echo.
echo Usage:
echo   BuildFrontiersForge.bat
echo   BuildFrontiersForge.bat -zip -version 1.2.3
echo   BuildFrontiersForge.bat -package -version 1.2.3
echo   BuildFrontiersForge.bat -nobuild -zip -version 1.2.3
echo   BuildFrontiersForge.bat -nosync -package -version 1.2.3
echo   BuildFrontiersForge.bat 1.2.3
exit /b 0

:usage_fail
echo.
echo Run with --help for usage.
exit /b 1
