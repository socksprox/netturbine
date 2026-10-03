@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cl /EHsc /W3 /O2 "%~dp0fan_helper.cpp" advapi32.lib /link /out:"%~dp0fan_helper_new.exe"
