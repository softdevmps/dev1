@echo off
setlocal DisableDelayedExpansion
set "sfBuildConfig=Debug"
set "sfBuildExit=1"
if not "%~1"=="" set "sfBuildConfig=%~1"
if /i "%sfBuildConfig%"=="Debug" goto CheckWindows
if /i "%sfBuildConfig%"=="Release" goto CheckWindows
echo Configuracion invalida. Usa Debug o Release.
goto Finish

:CheckWindows
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" goto FindTools
if /i "%PROCESSOR_ARCHITEW6432%"=="AMD64" goto FindTools
echo Este proyecto requiere Windows x64. No es un driver ARM64.
goto Finish

:FindTools
set "sfVsWhere=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%sfVsWhere%" goto MissingTools
set "sfMsBuild="
for /f "usebackq delims=" %%B in (`call "%sfVsWhere%" -latest -version "[17.0,18.0)" -products * -requires Microsoft.Component.MSBuild Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find "MSBuild\**\Bin\MSBuild.exe"`) do set "sfMsBuild=%%B"
if not defined sfMsBuild goto MissingTools
if not exist "%sfMsBuild%" goto MissingTools
if not exist "%~dp0out" mkdir "%~dp0out"
if not exist "%~dp0out" (
    echo No se pudo crear la carpeta de resultados. Extrae el ZIP en una carpeta donde puedas escribir.
    goto Finish
)
set "sfBuildLog=%~dp0out\compilacion-%sfBuildConfig%.log"
echo Compilando el controlador y Checker para Windows x64...
echo El resultado se guardara en "%sfBuildLog%".
"%sfMsBuild%" "%~dp0StorageFilter.sln" /m:2 /t:Build /p:Configuration=%sfBuildConfig% /p:Platform=x64 /p:RunCodeAnalysis=true /v:minimal >"%sfBuildLog%" 2>&1
set "sfBuildExit=%ERRORLEVEL%"
type "%sfBuildLog%"
if not "%sfBuildExit%"=="0" goto BuildFailed
if not exist "%~dp0out\x64\%sfBuildConfig%\driver\StorageFilter.sys" goto MissingOutput
if not exist "%~dp0out\x64\%sfBuildConfig%\checker\Checker.exe" goto MissingOutput
echo.
echo COMPILACION CORRECTA:
echo Driver: "%~dp0out\x64\%sfBuildConfig%\driver\StorageFilter.sys"
echo Checker: "%~dp0out\x64\%sfBuildConfig%\checker\Checker.exe"
echo El driver aun requiere firma oficial antes de poder instalarlo.
echo Consulta COMENZAR-WINDOWS.txt para los siguientes pasos.
goto Finish

:MissingTools
echo Faltan Visual Studio 2022 o sus herramientas C++.
echo Abre COMENZAR-WINDOWS.txt e instala tambien SDK y WDK compatibles.
goto Finish

:BuildFailed
echo.
echo La compilacion fallo. No se ha confirmado un driver valido.
echo Log completo: "%sfBuildLog%"
echo Si aparece MSB8020, falta el WDK o su integracion con Visual Studio.
echo Consulta COMENZAR-WINDOWS.txt. Conserva el primer error del log.
goto Finish

:MissingOutput
set "sfBuildExit=1"
echo MSBuild termino pero falta StorageFilter.sys o Checker.exe. Revisa "%sfBuildLog%".

:Finish
echo.
echo Pulsa una tecla para cerrar esta ventana.
pause >nul
exit /b %sfBuildExit%
