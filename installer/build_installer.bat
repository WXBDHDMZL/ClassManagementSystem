@echo off
cd /d "%~dp0"

rem P1-10: never let a stale installer.iss version ship an old package.
python "%~dp0..\tools\check_version.py"
if errorlevel 1 (
  echo [ERROR] Version check failed. Fix version numbers before packaging.
  exit /b 1
)

rem Close any running app instance first: a running exe cannot be overwritten on
rem Windows, which would make packaging/overwriting the output fail.
python "%~dp0..\tools\stop_app_instances.py"
if errorlevel 1 (
  echo [ERROR] A running app instance still locks the output. See message above.
  exit /b 1
)

rem P0-2: the installer must ship the VC++ x64 runtime. Without it a clean
rem Windows shows "install succeeded" but the app cannot start (missing
rem MSVCP140.dll). Download the Microsoft-signed redistributable if absent;
rem fail the build if it still isn't available.
if not exist "%~dp0VC_redist.x64.exe" (
  echo VC_redist.x64.exe not found, downloading from Microsoft...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile '%~dp0VC_redist.x64.exe' -ErrorAction Stop } catch { Write-Host $_.Exception.Message; exit 1 }"
)
if not exist "%~dp0VC_redist.x64.exe" (
  echo [ERROR] VC_redist.x64.exe is required but was not downloaded.
  echo         Put the Microsoft VC++ x64 redistributable next to installer.iss.
  exit /b 1
)
for %%F in ("%~dp0VC_redist.x64.exe") do if %%~zF LSS 5000000 (
  echo [ERROR] VC_redist.x64.exe looks truncated: %%~zF bytes.
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
rem 审计 S-P1-9/P2-16：为刚生成的安装包写 .sha256，手工打包上传时客户端
rem 才有校验值可用（缺校验值时客户端会拒绝更新）。
powershell -NoProfile -Command "$f = Get-ChildItem -LiteralPath 'output' -Filter '*.exe' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($f) { $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower(); Set-Content -LiteralPath ($f.FullName + '.sha256') -Value ($h + '  ' + $f.Name) -Encoding ASCII }"
rem 2026-10-17: keep only the newest installer in output; delete older installers.
powershell -NoProfile -Command "$files = Get-ChildItem -LiteralPath 'output' -Filter '*.exe' -File | Sort-Object LastWriteTime -Descending; $files | Select-Object -Skip 1 | Remove-Item -Force"
echo Build completed!
pause
