#!/usr/bin/env python3
"""dl.tsv に書かれた zip を Safari 経由でダウンロードし、カレントディレクトリに保存する。

dl.tsv は m.289.tsv のサブセット（file name, URL, size の TSV）。
Safari のダウンロード先はデフォルトの ~/Downloads を前提とし、
完了済みファイルを検知してカレントディレクトリへ移動する。

使い方:
    python3 download.py                 # dl.tsv を 6 並列で処理
    python3 download.py -p 3 my.tsv     # 3 並列、別のTSVを指定

注意:
- 初回のみ Safari が「"archive.org" からのダウンロードを許可しますか?」と
  聞いてくるので、手動で「許可」すること（サイト単位で1回だけ）。
- 再実行すると、カレントディレクトリに既にあるファイルはスキップされる。
"""

import argparse
import os
import re
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

POLL_INTERVAL = 1.0        # 監視間隔（秒）
STABLE_REQUIRED = 3        # サイズが何回連続で不変なら完了とみなすか
OPEN_TIMEOUT = 180         # Safari発火後、ファイルが出現するまでの待ち上限（秒）
DOWNLOAD_TIMEOUT = 600     # 1ファイルあたりのダウンロード待ち上限（秒）
RETRIES = 2                # 失敗時のリトライ回数
PROGRESS_INTERVAL = 10     # 進捗表示間隔（秒）

# "005.zip" の重複保存名 "005 (1).zip" に対応
DUPLICATE_RE = re.compile(r"^(.+) \(\d+\)(\.[^.]*)$")


def load_tsv(path: str):
    """TSV（またはスペース区切り）を読み (file name, url, size) のリストを返す。"""
    entries = []
    with open(path, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("file name"):
                continue  # 空行とヘッダー
            cols = line.split("\t") if "\t" in line else line.split()
            if len(cols) < 2:
                print(f"[warn] {path}:{lineno}: 列が足りません: {line!r}", file=sys.stderr)
                continue
            name, url = cols[0], cols[1]
            size = cols[2] if len(cols) > 2 else ""
            entries.append((name, url, size))
    return entries


def open_in_safari(url: str) -> None:
    subprocess.run(
        ["osascript", "-e", f'tell application "Safari" to open location "{url}"'],
        check=True, capture_output=True, timeout=30,
    )


def find_candidates(downloads: Path, name: str):
    """~/Downloads にある name の本体/重複保存名/途中ファイル(.download)を列挙する。"""
    final, partial = [], []
    try:
        entries = list(downloads.iterdir())
    except FileNotFoundError:
        return final, partial

    def is_mine(n: str) -> bool:
        base = n[:-len(".download")] if n.endswith(".download") else n
        return base == name or (lambda m: bool(m) and m.group(1) == os.path.splitext(name)[0]
                                and m.group(2) == os.path.splitext(name)[1])(DUPLICATE_RE.match(base))

    for p in entries:
        if is_mine(p.name):
            (partial if p.name.endswith(".download") else final).append(p)
    return final, partial


def wait_and_fetch(name: str, downloads: Path):
    """Safari のダウンロード完了を待ち、確定したファイルの Path を返す。"""
    started = time.time()
    stable_count = 0
    last_size = -1
    appeared = None

    while True:
        elapsed = time.time() - started
        finals, partials = find_candidates(downloads, name)

        if finals and not partials:
            # 「name (1).zip」等が複数ある場合は最新を採用
            target = max(finals, key=lambda p: p.stat().st_mtime)
            size = target.stat().st_size
            if size == last_size:
                stable_count += 1
                if stable_count >= STABLE_REQUIRED:
                    return target
            else:
                stable_count = 0
                last_size = size
        elif finals and partials:
            appeared = True  # 途中ファイルあり → まだ書き込み中
            stable_count = 0
        elif not finals and appeared:
            # 一度出現した本体が消えた（Safariがリネーム中の可能性）→ リセット
            stable_count = 0
            last_size = -1

        if elapsed > (OPEN_TIMEOUT if appeared is None else DOWNLOAD_TIMEOUT):
            raise TimeoutError(f"{name}: {elapsed:.0f}秒で完了しませんでした")
        time.sleep(POLL_INTERVAL)


class Progress:
    """10秒ごとに「並列実行数 / 完了率」を表示する。"""

    def __init__(self, total: int):
        self.total = total
        self.done = 0
        self.active = 0
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        started = time.time()
        while not self._stop.wait(PROGRESS_INTERVAL):
            with self._lock:
                pct = 100 * self.done / self.total if self.total else 0
                print(f"[progress {time.time() - started:5.0f}s] "
                      f"実行中 {self.active} / 完了 {self.done}/{self.total} ({pct:.0f}%)", flush=True)

    def start(self):
        self._thread.start()

    def finish(self):
        self._stop.set()
        self._thread.join(timeout=2)

    def begin_item(self):
        with self._lock:
            self.active += 1

    def end_item(self, success: bool):
        with self._lock:
            self.active -= 1
            if success:
                self.done += 1


def download_one(name: str, url: str, size: str, downloads: Path, progress: Progress) -> str:
    dest = Path(name)
    if dest.exists():
        return "skip (exists)"
    progress.begin_item()

    for attempt in range(1, RETRIES + 1):
        try:
            open_in_safari(url)
            fetched = wait_and_fetch(name, downloads)
            fetched.rename(dest.resolve())
            progress.end_item(True)
            return f"ok ({size})"
        except (subprocess.SubprocessError, TimeoutError, OSError) as e:
            if attempt == RETRIES:
                progress.end_item(False)
                return f"FAIL: {e}"
            time.sleep(5)
    progress.end_item(False)
    return "FAIL: unreachable"


def main():
    ap = argparse.ArgumentParser(description="Safari経由でdl.tsvのzipをダウンロードしカレントディレクトリに保存する")
    ap.add_argument("tsv", nargs="?", default="dl.tsv", help="入力TSV (既定: dl.tsv)")
    ap.add_argument("-p", "--parallel", type=int, default=6, help="並列数 (既定: 6)")
    ap.add_argument("--downloads", default=os.path.expanduser("~/Downloads"),
                    help="Safariのダウンロード先 (既定: ~/Downloads)")
    args = ap.parse_args()

    if not os.path.isfile(args.tsv):
        sys.exit(f"TSVがありません: {args.tsv}\n例: awk -F'\\t' 'NR<=6' m.289.tsv > dl.tsv")
    downloads = Path(args.downloads)
    if not downloads.is_dir():
        sys.exit(f"ダウンロード先がありません: {downloads}")

    entries = load_tsv(args.tsv)
    print(f"{len(entries)} 件を {args.parallel} 並列で処理します")

    progress = Progress(len(entries))
    progress.start()
    ok = skip = fail = 0
    with ThreadPoolExecutor(max_workers=args.parallel) as pool:
        futures = {pool.submit(download_one, n, u, s, downloads, progress): n for n, u, s in entries}
        for fut in as_completed(futures):
            name = futures[fut]
            status = fut.result()
            if status.startswith("FAIL"):
                fail += 1
                mark = "✗"
            elif status.startswith("skip"):
                skip += 1
                mark = "="
            else:
                ok += 1
                mark = "✓"
            print(f"{mark} {name}: {status}", flush=True)
    progress.finish()

    print(f"完了: ok={ok} skip={skip} fail={fail}")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
