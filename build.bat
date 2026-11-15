@echo off
rem P3-10: switch to this script's directory so debug_info is always written here.
cd /d "%~dp0"

rem B-14/B-16：发布质量门禁 —— 版本号与规则基线不平就不构建。
python "%~dp0tools\check_version.py"
if errorlevel 1 (
  echo [ERROR] 版本号未同步，请先运行 python tools\stamp_version.py --fix
  exit /b 1
)
python "%~dp0tools\check_rules.py"
if errorlevel 1 (
  echo [ERROR] 规则门禁未通过，见上方明细。
  exit /b 1
)

rem Close any running app instance first: on Windows a running exe cannot be
rem overwritten, so rebuilding while the app is open failed with
rem "LNK1104: cannot open file <app>.exe". The helper also aborts early with a
rem clear message when it has no permission to close the process.
python "%~dp0tools\stop_app_instances.py"
if errorlevel 1 (
  echo [ERROR] A running app instance still locks the output exe. See message above.
  exit /b 1
)

rem P2-61: paths are overridable via environment variables (for machines where VS
rem or Flutter live elsewhere); the defaults match this development machine.
if not defined CMS_VS_VCVARS set "CMS_VS_VCVARS=D:\Program Files\VS\VSP2026\VC\Auxiliary\Build\vcvarsall.bat"
if not defined CMS_FLUTTER (
  for /f "delims=" %%i in ('where flutter 2^>nul') do set "CMS_FLUTTER=%%i"
)
if not exist "%CMS_VS_VCVARS%" (
  echo [ERROR] vcvarsall.bat not found: %CMS_VS_VCVARS%
  echo         Set CMS_VS_VCVARS to your Visual Studio path and retry.
  exit /b 1
)
if not exist "%CMS_FLUTTER%" (
  echo [ERROR] Flutter not found: %CMS_FLUTTER%
  echo         Set CMS_FLUTTER to your Flutter SDK path and retry.
  exit /b 1
)
call "%CMS_VS_VCVARS%" x64
if errorlevel 1 (
  echo [ERROR] Failed to initialize VS build environment.
  exit /b 1
)
echo Building with obfuscation...
"%CMS_FLUTTER%" build windows --release --obfuscate --split-debug-info=./debug_info
if errorlevel 1 (
  echo [ERROR] Build failed with error level %errorlevel%.
  exit /b 1
)
echo Build completed successfully.
