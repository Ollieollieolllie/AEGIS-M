@echo off
rem Releases AEGIS-M (see release.ps1). Arguments are passed on: release -Bump patch -Draft
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0release.ps1" %*
