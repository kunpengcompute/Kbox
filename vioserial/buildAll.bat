@echo off
call ..\tools\build.bat vioser.sln "Win8 Win10" %*
if errorlevel 1 goto :eof
call ..\tools\build.bat sys\vioser.vcxproj "Win10_SDV" %*
