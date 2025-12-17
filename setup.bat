@echo off
echo ========================================
echo   TWAP Hook Project Setup Script
echo ========================================
echo.

REM Step 1: Check if Foundry is installed
echo [Step 1] Checking Foundry installation...
forge --version >nul 2>&1
if errorlevel 1 (
    echo Foundry is NOT installed.
    echo.
    echo Please install Foundry first:
    echo   1. Open PowerShell as Administrator
    echo   2. Run: irm https://foundry.sh | iex
    echo   3. Or download from: https://getfoundry.sh
    echo.
    pause
    exit /b 1
)
echo Foundry found!
echo.

REM Step 2: Initialize git if needed
echo [Step 2] Initializing Git repository...
if not exist ".git" (
    git init
    echo Git initialized.
) else (
    echo Git already initialized.
)
echo.

REM Step 3: Install Foundry dependencies
echo [Step 3] Installing Foundry dependencies...
echo This may take a few minutes...
echo.

echo Installing forge-std...
forge install foundry-rs/forge-std --no-commit

echo Installing Uniswap v4-core...
forge install Uniswap/v4-core --no-commit

echo Installing Uniswap v4-periphery...
forge install Uniswap/v4-periphery --no-commit

echo Installing OpenZeppelin contracts...
forge install OpenZeppelin/openzeppelin-contracts --no-commit

echo.
echo [Step 4] Creating remappings...
forge remappings > remappings.txt
echo.

REM Step 5: Build the project
echo [Step 5] Building the project...
forge build

if errorlevel 1 (
    echo.
    echo Build failed! Check errors above.
    pause
    exit /b 1
)

echo.
echo ========================================
echo   Setup Complete!
echo ========================================
echo.
echo Next steps:
echo   1. Run tests:     forge test
echo   2. See gas usage: forge test --gas-report
echo.
pause
