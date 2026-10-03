@echo off
rem Builds fan_helper.exe with any MSVC toolchain (VS dev prompt or vcvars64).
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if errorlevel 1 (
  echo vcvars64 not found - run this from a "x64 Native Tools" prompt instead
  cl /EHsc /W3 /O2 "%~dp0fan_helper.cpp" advapi32.lib
  exit /b %errorlevel%
)
cl /EHsc /W3 /O2 "%~dp0fan_helper.cpp" advapi32.lib
