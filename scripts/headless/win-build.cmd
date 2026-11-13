@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set "LIB=%LIB%;C:\Users\Public\nvenc"
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
set "RUBYFUNK_BUILD_VERSION=0.2.0-win-dev"
cd /d C:\Users\Public\rubyfunk-native
cargo build -r -p rubyfunk-host --features nvenc 2>&1
echo BUILD_EXIT=%ERRORLEVEL%
