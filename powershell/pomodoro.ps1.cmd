@echo off
setlocal

REM この .cmd 自身のあるフォルダへ移動（相対パスが崩れない）
cd /d "%~dp0"

REM PowerShell を NoProfile + ExecutionPolicy Bypass で実行
REM -WorkSec/-BreakSec は必要に応じて調整
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pomodoro.ps1" ^
  -WorkSec 1500 -BreakSec 300 -WorkBeeps 1 -BreakBeeps 1 -GapMs 500

REM 終了後にウィンドウを閉じたくないなら pause を有効化
REM pause
endlocal