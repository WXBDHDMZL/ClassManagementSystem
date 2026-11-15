@echo off
cd /d "%~dp0"

rem Close any running app instance first: a running exe cannot be overwritten on
rem Windows, which would make packaging/overwriting the output fail.
python "%~dp0..\tools\stop_app_instances.py"
if errorlevel 1 (
  echo [ERROR] A running app instance still locks the output. See message above.
  exit /b 1
)

echo Looking for Inno Setup...
for /f "delims=" %%i in ('where iscc 2^>nul') do (
    echo Found iscc at: %%i
    "%%i" installer.iss
    goto :done
)
echo iscc not found in PATH, searching common locations...
if exist "C:\Program Files (x86)\Inno Setup 6\iscc.exe" (
    rem Fix: an unquoted (x86) in an echo line inside this block closes the
    rem block early and breaks parsing (cmd reports a syntax error).
    echo Found iscc at: "C:\Program Files (x86)\Inno Setup 6\iscc.exe"
    "C:\Program Files (x86)\Inno Setup 6\iscc.exe" installer.iss
    goto :done
)
if exist "C:\Program Files\Inno Setup 6\iscc.exe" (
    echo Found iscc at: "C:\Program Files\Inno Setup 6\iscc.exe"
    "C:\Program Files\Inno Setup 6\iscc.exe" installer.iss
    goto :done
)
if exist "C:\Program Files (x86)\Inno Setup 7\iscc.exe" (
    echo Found iscc at: "C:\Program Files (x86)\Inno Setup 7\iscc.exe"
    "C:\Program Files (x86)\Inno Setup 7\iscc.exe" installer.iss
    goto :done
)
if exist "C:\Program Files\Inno Setup 7\iscc.exe" (
    echo Found iscc at: "C:\Program Files\Inno Setup 7\iscc.exe"
    "C:\Program Files\Inno Setup 7\iscc.exe" installer.iss
    goto :done
)
echo Inno Setup not found! Please install Inno Setup first.
pause
exit /b 1

:done
if errorlevel 1 (
  echo [ERROR] Inno Setup compile failed.
  pause
  exit /b 1
)
rem 2026-10-17: keep only the newest installer in output; delete older installers.
powershell -NoProfile -Command "$files = Get-ChildItem -LiteralPath 'output' -Filter '*.exe' -File | Sort-Object LastWriteTime -Descending; $files | Select-Object -Skip 1 | Remove-Item -Force"
echo Build completed!
pause
