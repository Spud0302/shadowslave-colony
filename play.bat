@echo off
rem Runs Shadow Slave Colony on Windows. Downloads Godot 4.3 the first time.
cd /d "%~dp0"
set BIN=.engine\Godot_v4.3-stable_win64.exe
if not exist "%BIN%" (
  echo Downloading Godot 4.3...
  mkdir .engine 2>nul
  powershell -Command "Invoke-WebRequest https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_win64.exe.zip -OutFile .engine\godot.zip; Expand-Archive .engine\godot.zip -DestinationPath .engine -Force; Remove-Item .engine\godot.zip"
)
"%BIN%" --path .
