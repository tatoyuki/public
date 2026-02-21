# pomodoro.ps1
# 目的:
#   仕事(Work)と休憩(Break)を交互に繰り返すポモドーロタイマー。
#   切り替え時にWAV音を同期再生(PlaySync)して通知する。
#
# 実行例:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\pomodoro.ps1 `
#     -WorkSec 25 -BreakSec 5
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\pomodoro.ps1 `
#     -WorkBeeps 2 -BreakBeeps 1 -GapMs 200
#
# PowerShellを知らない人向けメモ(C++/Python感覚):
#   - param(...) は「コマンドライン引数 + デフォルト値」の定義
#   - function ... は関数定義 (戻り値は return か、最後の式が返る)
#   - $xxx は変数 (型を [int] などで付けられる)
#   - -eq / -lt / -ge は比較演算子 (==, <, >= 相当)
#   - if (...) { ... } else { ... } は普通の条件分岐
#   - while ($true) は無限ループ
#   - try/catch は例外処理
#   - .NET のクラスは [Console]::Write(...) のように呼ぶ (静的メソッド)

param(
  # 作業時間(秒)。デフォルト1500秒=25分
  [int]$WorkSec = 1500,

  # 休憩時間(秒)。デフォルト300秒=5分
  [int]$BreakSec = 300,

  # 作業開始/再開時に鳴らすWAVファイルパス
  [string]$WorkWav = "C:\Windows\Media\Alarm02.wav",

  # 休憩開始時に鳴らすWAVファイルパス
  [string]$BreakWav = "C:\Windows\Media\Alarm03.wav",

  # 作業開始時の「繰り返し回数」(同じWAVを何回鳴らすか)
  [int]$WorkBeeps = 1,

  # 休憩開始時の「繰り返し回数」
  [int]$BreakBeeps = 1,

  # 複数回鳴らす場合の間隔(ミリ秒)
  [int]$GapMs = 500
)

# StrictMode: 未定義変数の参照などをエラーにして、バグを早めに潰す。
#   Pythonでいう「未定義変数を使ったら例外」みたいな厳格さを上げる設定。
Set-StrictMode -Version Latest

# 何かコマンドが失敗したときに「警告」ではなく例外で止める。
#   つまり「失敗は即throw」という方針。
$ErrorActionPreference = "Stop"

function Assert-File([string]$path, [string]$name) {
  # Test-Path: ファイル/ディレクトリが存在するかチェック
  # -LiteralPath: ワイルドカード解釈をしない(そのままの文字列として扱う)
  if (-not (Test-Path -LiteralPath $path)) {
    # throw: 例外を投げて停止
    throw "$name not found: $path"
  }
}

function Fmt([int]$sec) {
  # 秒→"mm:ss"に整形するユーティリティ関数
  if ($sec -lt 0) { $sec = 0 }      # マイナスは0扱いに丸める

  # [int](...) はC++のintキャスト/ Pythonのint(...)相当
  $m = [int]($sec / 60)             # 分
  $s = $sec % 60                    # 秒(余り)

  # "{0:00}:{1:00}" -f $m, $s
  #   これは format で、Pythonの f"{m:02d}:{s:02d}" に近い
  return "{0:00}:{1:00}" -f $m, $s
}

function Invoke-WavSync([string]$path, [int]$count, [int]$gapMs) {
  # WAVを同期再生する(鳴り終わるまで待つ)。
  # count回繰り返し、間はgapMsだけ待つ。
  if ($count -lt 1) { $count = 1 }
  for ($i = 0; $i -lt $count; $i++) {
    # New-Object System.Media.SoundPlayer $path
    #   .NETのSoundPlayerを生成してWAVを読み込み、PlaySync()で同期再生。
    try {
      (New-Object System.Media.SoundPlayer $path).PlaySync()
    }
    catch {
      Write-Host "WAV play failed: $path"
      Write-Host "  $($_.Exception.GetType().FullName): $($_.Exception.Message)"
      throw
    }
    # 最後の1回の後は待たない
    if ($i -lt $count - 1) { Start-Sleep -Milliseconds $gapMs }
  }
}

function Main() {

  # 引数で渡されたWAVが存在するか事前チェック(なければ即終了)
  Assert-File $WorkWav  "WorkWav"
  Assert-File $BreakWav "BreakWav"

  # ここから実行ログを表示
  Write-Host "Pomodoro started. Press Ctrl+C to stop."
  Write-Host "work=$WorkSec s, break=$BreakSec s"
  Write-Host "work_wav=$WorkWav"
  Write-Host "break_wav=$BreakWav"
  Write-Host "work_beeps=$WorkBeeps, break_beeps=$BreakBeeps, gap_ms=$GapMs"
  Write-Host ""

  # 起動直後はWORKから開始
  $phase = "WORK"              # 現在フェーズ: "WORK" or "BREAK"
  $phaseTotal = $WorkSec       # 今フェーズの総秒数
  $phaseStart = Get-Date       # 今フェーズ開始時刻(DateTime)

  # 初回WORK開始のログ + 音を鳴らす
  $ts = (Get-Date).ToString("yyyy/MM/dd H:mm:ss")
  Write-Host "$ts [WORK] start - wav(sync) x$WorkBeeps"
  Invoke-WavSync $WorkWav $WorkBeeps $GapMs

  try {
    while ($true) {
      # 現在時刻
      $now = Get-Date

      # 経過秒: (now - phaseStart) は TimeSpan になるので TotalSeconds を使う
      $elapsed = [int]($now - $phaseStart).TotalSeconds

      # 残り秒 = 総秒数 - 経過秒
      # $remain = $phaseTotal - $elapsed

      # 表示用の1行文字列を作る
      # バッククォート ` は「行継続」(Pythonの \ みたいなもの)
      # remain={3}, (Fmt $remain)
      $line = "{0} [{1}] elapsed={2}" -f `
        $now.ToString("yyyy/MM/dd H:mm:ss"), $phase, (Fmt $elapsed)

      # 同じ行を更新表示する(コンソールのカーソルを行頭に戻す)
      # "`r" は carriage return。末尾に空白を足して残骸(前回の長い文字)を消す。
      [Console]::Write($line + (" " * 20) + "`r")

      # 1秒待つ (ループの刻み)
      Start-Sleep -Seconds 1

      # フェーズ終了判定
      if ($elapsed -ge $phaseTotal) {
        # 行を確定させるために改行
        [Console]::Write("`n")

        if ($phase -eq "WORK") {
          # WORK→BREAKへ切り替え
          $phase = "BREAK"
          $phaseTotal = $BreakSec
          $phaseStart = Get-Date

          $ts = (Get-Date).ToString("yyyy/MM/dd H:mm:ss")
          Write-Host "$ts [BREAK] start - wav(sync) x$BreakBeeps"
          Invoke-WavSync $BreakWav $BreakBeeps $GapMs
        }
        else {
          # BREAK→WORKへ切り替え
          $phase = "WORK"
          $phaseTotal = $WorkSec
          $phaseStart = Get-Date

          $ts = (Get-Date).ToString("yyyy/MM/dd H:mm:ss")
          Write-Host "$ts [WORK] start - wav(sync) x$WorkBeeps"
          Play-WavSync $WorkWav $WorkBeeps $GapMs
        }
      }
    }
  }
  catch [System.Management.Automation.StopException] {
    # Ctrl+C で停止すると StopException として捕まる
    [Console]::Write("`n")
    Write-Host "Stopped."
  }
  catch {
    # その他の例外
    [Console]::Write("`n")
    Write-Host "ERROR: $($_.Exception.Message)"
    throw  # 呼び出し元に再スロー(詳細を残す)
  }

}

Main
