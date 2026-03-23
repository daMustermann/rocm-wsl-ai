@echo off
color 0b
setlocal
echo ==========================================================
echo       ROCm AI Toolkit - WSL2 ^& Ubuntu Setup Wizard
echo ==========================================================
echo.

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    color 0c
    echo [ERROR] Administrator Privileges Required!
    echo Please right-click this file and select "Run as administrator".
    echo.
    pause
    exit /b
)

echo [NOTE] This wizard will install the Windows Subsystem for Linux (WSL2)
echo        and automatically configure Ubuntu 24.04 for you.
echo.
pause
echo.

echo [1/3] Installing the Windows Subsystem for Linux Core...
wsl --install --no-distribution
echo.

echo [2/3] Forcing WSL to update to the latest kernel version...
wsl --update
echo.

echo [3/3] Downloading and Installing Ubuntu 24.04...
wsl --install -d Ubuntu-24.04
echo.

color 0a
echo ==========================================================
echo                 READY FOR AI GENERATION!
echo ==========================================================
echo.
echo IMPORTANT NEXT STEPS:
echo 1. If Windows prompts you to restart your computer, please do so now.
echo 2. Open your Start Menu, search for "Ubuntu 24.04", and launch it.
echo 3. It will ask you to create a UNIX username and password.
echo 4. Once inside Ubuntu, you can clone the ROCm toolkit and run menu.sh!
echo.
pause
