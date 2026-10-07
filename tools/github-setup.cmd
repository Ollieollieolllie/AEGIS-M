@echo off
rem One-time: puts this repository on GitHub and pushes the current branch (see github-setup.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0github-setup.ps1" %*
