# 25秒, 5秒サイクル
# python pomodoro_windows.py --work 25 --break 5
import argparse
import os
import time
import winsound
import threading
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    work_sound_path: str
    break_sound_path: str
    work_sec: int
    break_sec: int
    work_beeps: int
    break_beeps: int
    beep_gap_sec: float


def fmt_hhmmss(sec: float) -> str:
    if sec < 0:
        sec = 0
    s = int(sec)
    h = s // 3600
    m = (s % 3600) // 60
    s = s % 60
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def play_wav_sync(path: str, times: int, gap_sec: float) -> None:
    for i in range(times):
        winsound.PlaySound(path, winsound.SND_FILENAME)
        if i != times - 1:
            time.sleep(gap_sec)


def play_wav_async(path: str, times: int, gap_sec: float) -> None:
    th = threading.Thread(
        target=play_wav_sync,
        args=(path, times, gap_sec),
        daemon=True,
    )
    th.start()


def tick_sleep_until_inline(
    target: float,
    phase: str,
    phase_start: float,
    phase_total: int,
) -> None:
    last_print_sec = None
    last_len = 0

    while True:
        now = time.monotonic()
        remain = target - now
        if remain <= 0:
            return

        elapsed = now - phase_start
        elapsed_s = int(elapsed)

        if last_print_sec is None or elapsed_s != last_print_sec:
            last_print_sec = elapsed_s
            ts = time.strftime("%Y-%m-%d %H:%M:%S")
            msg = (
                f"{ts} [{phase}] elapsed={fmt_hhmmss(elapsed)} "
                f"remain={fmt_hhmmss(phase_total - elapsed)}"
            )

            pad = ""
            if len(msg) < last_len:
                pad = " " * (last_len - len(msg))
            last_len = len(msg)

            print(msg + pad, end="\r", flush=True)

        next_boundary = (elapsed_s + 1) - elapsed
        time.sleep(min(remain, max(0.01, next_boundary)))


def align_cycle_start(now: float, base: float, cycle_len: int) -> float:
    """
    過ぎた分のイベントはスキップして、次に合流する。
    base は「現在サイクルの開始時刻候補」。
    """
    if now < base + cycle_len:
        return base

    skip = int((now - base) // cycle_len) + 1
    return base + skip * cycle_len


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Pomodoro notifier: WORK start (Alarm02) / BREAK start (Alarm03)."
    )
    parser.add_argument(
        "--work-sound",
        default=r"C:\Windows\Media\Alarm02.wav",
        help=r"WAV for WORK start. default: C:\Windows\Media\Alarm02.wav",
    )
    parser.add_argument(
        "--break-sound",
        default=r"C:\Windows\Media\Alarm03.wav",
        help=r"WAV for BREAK start. default: C:\Windows\Media\Alarm03.wav",
    )
    parser.add_argument(
        "--work",
        type=int,
        default=25 * 60,
        help="Work seconds (default: 1500)",
    )
    parser.add_argument(
        "--break",
        dest="break_",
        type=int,
        default=5 * 60,
        help="Break seconds (default: 300)",
    )
    parser.add_argument(
        "--gap",
        type=float,
        default=0.5,
        help="Gap seconds between multiple beeps (default: 0.5)",
    )
    args = parser.parse_args()

    cfg = Config(
        work_sound_path=args.work_sound,
        break_sound_path=args.break_sound,
        work_sec=args.work,
        break_sec=args.break_,
        work_beeps=1,   # ★WORK開始は1回
        break_beeps=1,  # ★BREAK開始は1回
        beep_gap_sec=args.gap,
    )

    if not os.path.isfile(cfg.work_sound_path):
        raise FileNotFoundError(f"WAV not found: {cfg.work_sound_path}")
    if not os.path.isfile(cfg.break_sound_path):
        raise FileNotFoundError(f"WAV not found: {cfg.break_sound_path}")

    print("Pomodoro started. Press Ctrl+C to stop.")
    print(f"work_sound={cfg.work_sound_path}")
    print(f"break_sound={cfg.break_sound_path}")
    print(f"work={cfg.work_sec}s, break={cfg.break_sec}s, gap={cfg.beep_gap_sec}s")

    cycle_len = cfg.work_sec + cfg.break_sec

    # 起動直後を WORK開始とみなす
    cycle_start = time.monotonic()
    print()
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"{ts} [WORK] start -> Alarm02 x1")
    play_wav_async(cfg.work_sound_path, cfg.work_beeps, cfg.beep_gap_sec)

    try:
        while True:
            now = time.monotonic()
            cycle_start = align_cycle_start(now, cycle_start, cycle_len)

            t_break_start = cycle_start + cfg.work_sec
            t_work_next_start = cycle_start + cycle_len

            now2 = time.monotonic()

            if now2 < t_break_start:
                # WORK中（次はBREAK開始）
                tick_sleep_until_inline(
                    target=t_break_start,
                    phase="WORK",
                    phase_start=cycle_start,
                    phase_total=cfg.work_sec,
                )
                print()
                ts = time.strftime("%Y-%m-%d %H:%M:%S")
                print(f"{ts} [BREAK] start -> Alarm03 x1")
                play_wav_async(cfg.break_sound_path, cfg.break_beeps, cfg.beep_gap_sec)

            elif now2 < t_work_next_start:
                # BREAK中（次は次WORK開始）
                tick_sleep_until_inline(
                    target=t_work_next_start,
                    phase="BREAK",
                    phase_start=t_break_start,
                    phase_total=cfg.break_sec,
                )
                print()
                ts = time.strftime("%Y-%m-%d %H:%M:%S")
                print(f"{ts} [WORK] start -> Alarm02 x1")
                play_wav_async(cfg.work_sound_path, cfg.work_beeps, cfg.beep_gap_sec)

                # 次サイクルへ
                cycle_start += cycle_len

            else:
                # 予定を過ぎている → スキップして合流
                cycle_start = align_cycle_start(now2, cycle_start, cycle_len)

    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
