@echo off
setlocal
set "DART=%LOCALAPPDATA%\..\src\flutter\bin\cache\dart-sdk\bin\dart.bat"
if not exist "%DART%" set "DART=dart"
pushd "%~dp0"
"%DART%" run bin\server.dart
popd