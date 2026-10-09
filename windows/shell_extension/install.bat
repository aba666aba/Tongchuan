@echo off
echo Installing LAN Sync Shell Extension...

:: 获取当前目录
set CURRENT_DIR=%~dp0
set EXE_PATH=%CURRENT_DIR%..\..\build\windows\x64\runner\Release\lan_sync.exe

:: 检查exe是否存在
if not exist "%EXE_PATH%" (
    echo Error: lan_sync.exe not found. Please build the project first.
    echo Run: flutter build windows --release
    pause
    exit /b 1
)

:: 添加右键菜单 - 文件
reg add "HKEY_CLASSES_ROOT\*\shell\LAN Sync" /ve /d "Send via LAN Sync" /f
reg add "HKEY_CLASSES_ROOT\*\shell\LAN Sync" /v "Icon" /d "\"%EXE_PATH%\"" /f
reg add "HKEY_CLASSES_ROOT\*\shell\LAN Sync\command" /ve /d "\"%EXE_PATH%\" --send \"%1\"" /f

:: 添加右键菜单 - 文件夹
reg add "HKEY_CLASSES_ROOT\Directory\shell\LAN Sync" /ve /d "Sync folder via LAN Sync" /f
reg add "HKEY_CLASSES_ROOT\Directory\shell\LAN Sync" /v "Icon" /d "\"%EXE_PATH%\"" /f
reg add "HKEY_CLASSES_ROOT\Directory\shell\LAN Sync\command" /ve /d "\"%EXE_PATH%\" --send-folder \"%1\"" /f

:: 添加右键菜单 - 背景（文件夹内空白处）
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\LAN Sync" /ve /d "Sync this folder via LAN Sync" /f
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\LAN Sync" /v "Icon" /d "\"%EXE_PATH%\"" /f
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\LAN Sync\command" /ve /d "\"%EXE_PATH%\" --send-folder \"%V\"" /f

echo.
echo Shell extension installed successfully!
echo You may need to restart Explorer for changes to take effect.
echo.
pause