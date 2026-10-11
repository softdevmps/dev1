@echo off
setlocal
cd /d "%~dp0"
set "HUELLA_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "HUELLA_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%HUELLA_PS%" -NoLogo -NoProfile -STA -File "%~dp0Run-Huella.ps1"
if errorlevel 1 (
  echo.
  echo Huella no pudo iniciarse. Conserva el error que aparece arriba.
  echo Si Windows requiere scripts firmados, revisa README.md.
  pause
)
endlocal
