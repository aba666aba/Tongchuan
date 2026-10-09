@echo off
echo Uninstalling LAN Sync Shell Extension...

:: 删除右键菜单 - 文件
reg delete "HKEY_CLASSES_ROOT\*\shell\LAN Sync" /f 2>nul

:: 删除右键菜单 - 文件夹
reg delete "HKEY_CLASSES_ROOT\Directory\shell\LAN Sync" /f 2>nul

:: 删除右键菜单 - 背景
reg delete "HKEY_CLASSES_ROOT\Directory\Background\shell\LAN Sync" /f 2>nul

echo.
echo Shell extension uninstalled successfully!
echo You may need to restart Explorer for changes to take effect.
echo.
pause