#!/usr/bin/env python3
"""
launch_parallel.py - full_adder_mc Monte Carlo on parallel single-threaded ngspice copies, with a
live terminal dashboard and Spot VM preemption handling.

Python rewrite of launch_parallel.sh, using the same command-line format as
launch_parallel.py. Same runs/<run_id>/ layout and params file as the bash version, so a
run started by either one can be resumed or checked by the other.

Usage
  ./launch_parallel.py run <total_trials> [-w WORKERS] [--sync DEST] [--chunk N] [--seed S]
  ./launch_parallel.py resume <run_id|latest> [-w WORKERS] [--sync DEST]
  ./launch_parallel.py status [run_id]

  e.g.  tmux new -s mc
        ./launch_parallel.py run 10000 -w 384 --sync gs://my-bucket/mc

Dashboard keys (single keypress, no Enter)
  q        drain: finish the chunks that are running, start no new ones, then stop. Press again to cancel.
  k        kill now: stop all workers immediately (in-flight chunks are lost). Ctrl-C does the same.
  + / -    one more / one fewer worker        ] / [    ten more / ten fewer workers
           Fewer workers never kills a running chunk; new ones just wait until fewer are running.
  Every way of stopping leaves the run resumable.

The dashboard is used when stdin and stdout are both a terminal. Otherwise (nohup, output redirected,
or --plain) a plain progress line is printed every --progress-every seconds. If the SSH session drops
(SIGHUP) the run keeps going without a screen; everything it prints is also saved to
runs/<run_id>/console.log. tmux is still the recommended way to run it.

Options can also come from environment variables, as in the bash version:
  SYNC_DEST, CHUNK, BASE_SEED, PROGRESS_EVERY.

Spot VMs
  --sync DEST   copies every finished chunk off the VM as soon as it finishes (gs:// via gcloud/gsutil,
                s3:// via the aws CLI, or a local/mounted directory). Use it on Spot: a VM whose
                termination action is DELETE takes its disk with it.
  A background thread polls the GCP or AWS metadata server every 5 s for a preemption notice. On a
  notice, or on the SIGTERM sent at shutdown, all workers are stopped, the session is logged as
  "preempted" and a final sync (capped at 20 s; GCP gives ~30 s) pushes the logs.
  Resume on the same VM:  ./launch_parallel.py resume latest -w 384
  Resume on a new VM:     copy this script and ../cell_lib.sp over, then
                          ./launch_parallel.py resume <run_id> -w 384 --sync gs://my-bucket/mc
                          (finished chunks are downloaded first; the run's own netlist.sp snapshot is used)

Layout of runs/<run_id>/
  params                       TOTAL, CHUNK, BASE_SEED
  netlist.sp                   the exact netlist this run uses (snapshot from when the run started)
  chunks/chunk_<k>.txt         one finished chunk; only appears once it fully succeeded
  progress.txt                 latest progress line
  console.log                  everything printed, every session
  run_info.txt                 log of every session of this run
  work/                        per-chunk netlists, logs and timings (scratch; never uploaded)
  full_adder_mc_merged.txt     all chunks merged, written once every chunk is done
runs/timing_log.csv            one row per session (host, CPU, trials, trials/s, status ...)
timing_results.txt             one human-readable line per session
"""

import argparse
import concurrent.futures as cf
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

import termios

SCRIPT_DIR = Path(__file__).resolve().parent
SRC = Path("full_adder_mc.sp")         # the Monte Carlo netlist
OUT = "full_adder_mc.txt"              # file named in the netlist's wrdata line
MERGED = "full_adder_mc_merged.txt"
RUNS = Path("runs")
LOG_CSV = RUNS / "timing_log.csv"
MAX_CHUNK = 500                        # full adder trials are short; matches the bash default cap
MARK = b"MC_TRIAL_DONE"                # printed by ngspice after every trial (injected below)
HOST = os.uname().nodename


# ==================================================================================== small helpers

def cpu_model():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return "unknown"


def hms(sec):
    sec = int(max(sec, 0))
    return f"{sec // 3600}h {sec % 3600 // 60:02d}m {sec % 60:02d}s"


def now_human():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def read_params(run_dir):
    p = {}
    for line in (run_dir / "params").read_text().splitlines():
        if "=" in line:
            key, val = line.split("=", 1)
            p[key.strip()] = int(val)
    return p["TOTAL"], p["CHUNK"], p["BASE_SEED"]


def n_chunks(total, chunk):
    return (total + chunk - 1) // chunk


def chunk_trials(k, total, chunk):
    n = n_chunks(total, chunk)
    return chunk if k < n - 1 else total - chunk * (n - 1)


def data_rows(path):
    """Data rows in a wrdata file (lines minus the header)."""
    with open(path, "rb") as f:
        return max(sum(1 for _ in f) - 1, 0)


def commit_chunk(part, dest):
    """Move a finished chunk into chunks/ so it survives a sudden power-off (a Spot VM is hard-stopped
    ~30 s after the notice). Flush the data, rename (atomic: the file is either absent or complete),
    then flush the directory so the rename itself is on disk."""
    with open(part, "rb") as f:
        os.fsync(f.fileno())
    os.replace(part, dest)
    fd = os.open(dest.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def newest_run(unfinished=False):
    if not RUNS.is_dir():
        return None
    for d in sorted((p for p in RUNS.iterdir() if (p / "params").is_file()), reverse=True):
        if unfinished and (d / MERGED).exists():
            continue
        return d.name
    return None


def ngspice_running():
    n = 0
    for p in Path("/proc").iterdir():
        if p.name.isdigit():
            try:
                n += (p / "comm").read_text().strip() == "ngspice"
            except OSError:
                pass
    return n


def exit_code(status):
    return os.WEXITSTATUS(status) if os.WIFEXITED(status) else -os.WTERMSIG(status)


# ==================================================================================== netlist

def build_template(netlist):
    """Run snapshot -> template. Relative .include paths become absolute (chunk netlists live in
    work/), and a marker is echoed after every trial so progress can be counted inside a chunk."""
    lines, marked = [], False
    for line in netlist.read_text().splitlines():
        toks = line.split()
        if len(toks) >= 2 and toks[0].lower() == ".include" and not toks[1].startswith("/"):
            line = f"{toks[0]} {SCRIPT_DIR / toks[1]}"
        lines.append(line)
        if re.match(r"\s*let current_run = current_run \+ 1\s*$", line):
            lines.append("  echo " + MARK.decode())
            marked = True
    text = "\n".join(lines) + "\n"
    missing = [what for what, ok in [
        ("'let mc_runs = ...'", re.search(r"(?m)^\s*let mc_runs\s*=", text)),
        (f"'wrdata {OUT}'", f"wrdata {OUT}" in text),
        ("'.control'", re.search(r"(?im)^\.control", text)),
    ] if not ok]
    if missing:
        sys.exit(f"{netlist}: can't find {', '.join(missing)} - is this the right netlist?")
    return text, marked


def chunk_netlist(template, trials, seed, part):
    t = re.sub(r"(?m)^(\s*)let mc_runs\s*=.*$", lambda m: f"{m.group(1)}let mc_runs = {trials}", template, count=1)
    t = t.replace(f"wrdata {OUT}", f"wrdata {part}")
    return re.sub(r"(?im)^(\.control.*)$", lambda m: f"{m.group(1)}\nset rndseed={seed}", t, count=1)


# ==================================================================================== off-VM sync

class Sync:
    """Copies results to SYNC_DEST. Single files go through a small thread pool so uploads never
    hold up the scheduler; whole-run mirrors are used for resume (down) and at the end (up)."""

    def __init__(self, dest):
        self.dest = (dest or "").rstrip("/")
        self.tool = self._pick_tool() if self.dest else None
        self.pool = cf.ThreadPoolExecutor(max_workers=4) if self.dest else None
        self.futures, self.failed, self.uploaded = [], [], 0
        self.lock = threading.Lock()

    def _pick_tool(self):
        if self.dest.startswith("gs://"):
            return "gcloud" if shutil.which("gcloud") else "gsutil" if shutil.which("gsutil") else None
        if self.dest.startswith("s3://"):
            return "aws" if shutil.which("aws") else None
        return "local"

    @staticmethod
    def _cmd(cmd, timeout):
        try:
            return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                  timeout=timeout).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def put(self, rel, timeout=120):
        """Upload runs/<rel> to <dest>/<rel>."""
        if not self.dest:
            return True
        src, dst = RUNS / rel, f"{self.dest}/{rel}"
        if self.tool == "local":
            try:
                Path(dst).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
                return True
            except OSError:
                return False
        return self._cmd({
            "gcloud": ["gcloud", "storage", "cp", "--quiet", str(src), dst],
            "gsutil": ["gsutil", "-q", "cp", str(src), dst],
            "aws":    ["aws", "s3", "cp", "--only-show-errors", str(src), dst],
        }[self.tool], timeout)

    def put_async(self, rel):
        if not self.dest:
            return

        def job():
            ok = self.put(rel)
            with self.lock:
                if ok:
                    self.uploaded += 1
                else:
                    self.failed.append(rel)
        self.futures.append(self.pool.submit(job))

    def pending(self):
        return sum(not f.done() for f in self.futures)

    def wait(self, timeout=None):
        if self.futures:
            cf.wait(self.futures, timeout=timeout)

    def shutdown(self):
        if self.pool:
            self.pool.shutdown(wait=False, cancel_futures=True)

    def mirror(self, direction, run_id, timeout=None):
        """Whole run dir (minus work/) up to or down from dest."""
        if not self.dest:
            return True
        local, remote = RUNS / run_id, f"{self.dest}/{run_id}"
        local.mkdir(parents=True, exist_ok=True)
        a, b = (str(local), remote) if direction == "up" else (remote, str(local))
        if self.tool == "local":
            src = Path(a)
            if not src.is_dir():
                return False
            try:
                shutil.copytree(src, b, dirs_exist_ok=True,
                                ignore=lambda d, names: ["work"] if Path(d) == src else [])
                return True
            except (OSError, shutil.Error):
                return False
        return self._cmd({
            "gcloud": ["gcloud", "storage", "rsync", "--recursive", "--quiet", "--exclude=^work/", a, b],
            "gsutil": ["gsutil", "-q", "-m", "rsync", "-r", "-x", "^work/", a, b],
            "aws":    ["aws", "s3", "sync", "--only-show-errors", "--exclude", "work/*", a, b],
        }[self.tool], timeout)


# ==================================================================================== preemption watcher

class PreemptionWatcher(threading.Thread):
    """Detects GCP/AWS from the metadata server, then polls for a Spot preemption notice."""

    GCP = "http://metadata.google.internal/computeMetadata/v1/instance/"
    AWS = "http://169.254.169.254/latest/"

    def __init__(self):
        super().__init__(daemon=True)
        self.cloud = "detecting"
        self.noticed = threading.Event()
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # never via a proxy

    def _get(self, url, method="GET", headers=None):
        try:
            req = urllib.request.Request(url, method=method, headers=headers or {})
            with self.opener.open(req, timeout=2) as r:
                return r.status, r.read().decode(errors="replace")
        except urllib.error.HTTPError as e:
            return e.code, ""
        except Exception:
            return None, ""

    def _aws_token(self):
        code, body = self._get(self.AWS + "api/token", "PUT", {"X-aws-ec2-metadata-token-ttl-seconds": "60"})
        return body if code == 200 else None

    def _gcp_preempted(self):
        return self._get(self.GCP + "preempted", headers={"Metadata-Flavor": "Google"})[1].strip() == "TRUE"

    def _aws_preempted(self):
        tok = self._aws_token()
        return bool(tok) and self._get(self.AWS + "meta-data/spot/instance-action",
                                       headers={"X-aws-ec2-metadata-token": tok})[0] == 200

    def run(self):
        if self._get(self.GCP + "id", headers={"Metadata-Flavor": "Google"})[0] == 200:
            self.cloud, check = "GCP", self._gcp_preempted
        elif self._aws_token():
            self.cloud, check = "AWS", self._aws_preempted
        else:
            self.cloud = "none"
            return
        while True:
            time.sleep(5)
            if check():
                self.noticed.set()
                return


# ==================================================================================== terminal

class Terminal:
    """Dashboard output plus single-key input.

    termios puts the terminal in non-canonical, no-echo mode: each keypress is readable on its own
    (no Enter) and isn't printed. ISIG stays on, so Ctrl-C still sends SIGINT. The original settings
    are saved and always restored on the way out, including after an exception.

    Drawing: log lines scroll normally; the dashboard ("footer") sits below them. To redraw, the
    cursor moves up over the old footer (ESC[nF) and clears to the end of the screen (ESC[J)."""

    def __init__(self, dashboard, console_log):
        self.dashboard = dashboard
        self.dead = False                   # terminal went away (SIGHUP / EIO)
        self.footer_rows, self.footer = 0, []
        self.console = open(console_log, "a", buffering=1)
        self.fd = self.saved = None
        if dashboard:
            self.fd = sys.stdin.fileno()
            self.saved = termios.tcgetattr(self.fd)
            new = termios.tcgetattr(self.fd)
            new[3] &= ~(termios.ICANON | termios.ECHO)     # lflags: no line buffering, no echo
            new[6][termios.VMIN] = 1                        # read() returns after 1 byte...
            new[6][termios.VTIME] = 0                       # ...with no inter-byte timeout
            termios.tcsetattr(self.fd, termios.TCSAFLUSH, new)
            self._write("\x1b[?25l")                        # hide cursor while drawing

    def _write(self, s):
        if self.dead:
            return
        try:
            sys.stdout.write(s)
            sys.stdout.flush()
        except OSError:                                     # EIO: the terminal is gone
            self.dead = True

    def _erase_footer(self):
        return f"\x1b[{self.footer_rows}F\x1b[J" if self.footer_rows else ""

    def draw(self, lines):
        self.footer = lines
        if not self.dashboard or self.dead:
            return
        width = shutil.get_terminal_size((100, 24)).columns
        body = "".join(line[:width - 1] + "\n" for line in lines)
        self._write(self._erase_footer() + body)
        self.footer_rows = len(lines)

    def log(self, msg):
        self.console.write(msg + "\n")
        if self.dashboard and not self.dead:
            self._write(self._erase_footer() + msg + "\n")
            self.footer_rows = 0
            self.draw(self.footer)
        else:
            self._write(msg + "\n")

    def keys(self, timeout):
        """Wait up to `timeout` s for keypresses; returns them (possibly '')."""
        if not self.dashboard or self.dead:
            time.sleep(timeout)
            return ""
        try:
            ready, _, _ = select.select([self.fd], [], [], timeout)
            if not ready:
                return ""
            data = os.read(self.fd, 64)
        except OSError:
            data = b""
        if not data:                                       # EOF: terminal hung up
            self.hangup()
            return ""
        return data.decode(errors="ignore")

    def hangup(self):
        self.dead = True
        self._restore()

    def _restore(self):
        if self.saved is not None:
            try:
                termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)
            except termios.error:
                pass
            self.saved = None

    def close(self):
        """Leave the last dashboard on screen, show the cursor, restore the terminal."""
        if self.dashboard:
            self._write("\x1b[?25h")
            self._restore()
            self.dashboard = False
            self.footer_rows = 0


# ==================================================================================== one session

class Job:
    def __init__(self, k, trials, attempt, proc, log_path, log_fh, part):
        self.k, self.trials, self.attempt = k, trials, attempt
        self.proc, self.log_path, self.log_fh, self.part = proc, log_path, log_fh, part
        self.start = time.monotonic()
        self.marks, self.offset, self.tail = 0, 0, b""

    def read_marks(self):
        """Count trial markers written since the last call, handling a marker split across reads."""
        try:
            with open(self.log_path, "rb") as f:
                f.seek(self.offset)
                data = f.read()
        except OSError:
            return
        if data:
            buf = self.tail + data
            self.marks += buf.count(MARK)
            self.tail = buf[-(len(MARK) - 1):]
            self.offset += len(data)


SIGNALS = {"int": 0, "term": False, "hup": False}


def install_signal_handlers():
    def on_int(*_):  SIGNALS["int"] += 1
    def on_term(*_): SIGNALS["term"] = True
    def on_hup(*_):  SIGNALS["hup"] = True
    signal.signal(signal.SIGINT, on_int)
    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGHUP, on_hup)


def ensure_single_threaded_ngspice():
    init = Path(".spiceinit")
    lines = init.read_text().splitlines() if init.exists() else []
    lines = [l for l in lines if not l.startswith("set num_threads")] + ["set num_threads=1"]
    init.write_text("\n".join(lines) + "\n")


def run_session(run_id, workers, sync, mode, args):
    run_dir = RUNS / run_id
    total, chunk, base_seed = read_params(run_dir)
    nch = n_chunks(total, chunk)
    chunk_dir, work_dir = run_dir / "chunks", run_dir / "work"
    chunk_dir.mkdir(parents=True, exist_ok=True)
    work_dir.mkdir(parents=True, exist_ok=True)

    template, marked = build_template(run_dir / "netlist.sp")
    ensure_single_threaded_ngspice()
    env = dict(os.environ, OMP_NUM_THREADS="1")

    pending = [(k, 0) for k in range(nch) if not (chunk_dir / f"chunk_{k}.txt").exists()]
    for k, _ in pending:     # logs of unfinished chunks are stale; clear so in-flight counts start at 0
        (work_dir / f"chunk_{k}.log").unlink(missing_ok=True)
    base_trials = sum(data_rows(p) for p in chunk_dir.glob("chunk_*.txt"))
    done_chunks = nch - len(pending)

    use_dashboard = not args.plain and sys.stdin.isatty() and sys.stdout.isatty()
    term = Terminal(use_dashboard, run_dir / "console.log")
    watcher = PreemptionWatcher()
    watcher.start()

    start_mono, start_human = time.monotonic(), now_human()
    running, failed, timings = [], [], []
    session_trials = 0
    stop, reason = None, None            # stop: None | "drain" | "kill"

    def info(msg):
        term.log(msg)
        with open(run_dir / "run_info.txt", "a") as f:
            f.write(msg + "\n")

    def counts():
        partial = sum(j.marks for j in running)
        return base_trials + session_trials + partial, session_trials + partial

    def rate_eta():
        done, this_session = counts()
        elapsed = time.monotonic() - start_mono
        rate = this_session / elapsed if elapsed > 0 else 0.0
        eta = hms((total - done) / rate) if rate > 0 else "--"
        return done, rate, eta, elapsed

    def progress_line():
        done, rate, eta, elapsed = rate_eta()
        return (f"[{datetime.now():%H:%M:%S}] {done}/{total} trials ({100 * done / total:.1f}%) | "
                f"{done_chunks}/{nch} chunks | {len(running)} busy | {rate:.3f} trials/s | "
                f"elapsed {hms(elapsed)} | ETA {eta}")

    def dashboard():
        done, rate, eta, elapsed = rate_eta()
        frac = done / total
        width = shutil.get_terminal_size((100, 24)).columns
        bar_w = max(10, min(50, width - 35))
        fill = int(round(frac * bar_w))
        bar = "█" * fill + "░" * (bar_w - fill)
        state = {None: "running", "drain": "DRAINING - no new chunks (q to cancel)", "kill": "STOPPING"}[stop]
        sync_txt = "off" if not sync.dest else (
            f"{sync.uploaded} up, {sync.pending()} pending" + (f", {len(sync.failed)} FAILED" if sync.failed else ""))
        return [
            "",
            f" full_adder Monte Carlo · run {run_id} · seed {base_seed} · {HOST}",
            f" {bar} {100 * frac:5.1f}%   {done}/{total} trials",
            f" chunks {done_chunks}/{nch} done · {len(running)} running · {len(pending)} queued"
            + (f" · {len(failed)} FAILED" if failed else ""),
            f" {rate:.3f} trials/s · elapsed {hms(elapsed)} · ETA {eta}",
            f" workers {workers} · cloud {watcher.cloud} · sync {sync_txt}",
            f" [{state}]   q drain · k kill · +/- workers · ]/[ ±10",
        ]

    def start_chunk(k, attempt):
        trials = chunk_trials(k, total, chunk)
        sp, part = work_dir / f"chunk_{k}.sp", work_dir / f"chunk_{k}.part"
        log_path = work_dir / f"chunk_{k}.log"
        sp.write_text(chunk_netlist(template, trials, base_seed + k, part.resolve()))
        part.unlink(missing_ok=True)
        fh = open(log_path, "wb")
        # Own session: Ctrl-C in the terminal reaches only this script, which then stops workers itself.
        proc = subprocess.Popen(["ngspice", str(sp.resolve())], stdin=subprocess.DEVNULL, stdout=fh,
                                stderr=subprocess.STDOUT, env=env, start_new_session=True)
        running.append(Job(k, trials, attempt, proc, log_path, fh, part))

    def finish(job, status, rusage):
        nonlocal session_trials, done_chunks
        job.log_fh.close()
        rc = exit_code(status)
        job.proc.returncode = rc                       # we reaped it ourselves (os.wait4)
        elapsed = time.monotonic() - job.start
        if rusage is not None:
            (work_dir / f"chunk_{job.k}.time").write_text(
                f"{elapsed:.2f} {rusage.ru_utime:.2f} {rusage.ru_stime:.2f} {rusage.ru_maxrss}\n")
        if rc == 0 and job.part.exists() and data_rows(job.part) == job.trials:
            commit_chunk(job.part, chunk_dir / f"chunk_{job.k}.txt")
            session_trials += job.trials
            done_chunks += 1
            if rusage is not None:
                timings.append((elapsed, rusage.ru_utime, rusage.ru_maxrss))
            sync.put_async(f"{run_id}/chunks/chunk_{job.k}.txt")
            term.log(f"  chunk {job.k} done ({job.trials} trials, {hms(elapsed)}) at {datetime.now():%H:%M:%S}")
        elif stop == "kill":
            pass                                       # we killed it; it stays pending for resume
        else:
            term.log(f"  chunk {job.k} FAILED (exit {rc}) - see {job.log_path}")
            if job.attempt < args.retries:
                term.log(f"  retrying chunk {job.k} (attempt {job.attempt + 2})")
                pending.insert(0, (job.k, job.attempt + 1))
            else:
                failed.append(job.k)

    def reap(block=False):
        for job in list(running):
            try:
                pid, status, ru = os.wait4(job.proc.pid, 0 if block else os.WNOHANG)
            except ChildProcessError:
                pid, status, ru = job.proc.pid, 1 << 8, None
            if pid == 0:
                job.read_marks()
                continue
            job.read_marks()
            running.remove(job)
            finish(job, status, ru)

    def kill_all():
        for job in running:
            try:
                os.killpg(job.proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 5
        while running and time.monotonic() < deadline:
            reap()
            time.sleep(0.1)
        for job in running:
            try:
                os.killpg(job.proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        reap(block=True)

    # ---------------------------------------------------------------- session start
    try:
        info(f"== Session on {HOST} ({cpu_model()}), {mode}, {start_human}")
        info(f"Run {run_id}: {total} trials in {nch} chunks of {chunk}, base seed {base_seed}")
        info(f"{nch - len(pending)} chunks already done, {len(pending)} to go, {workers} workers")
        if not marked:
            term.log("Note: couldn't add per-trial markers - progress will update per chunk only")
        term.log(f"Syncing finished chunks to {sync.dest}/{run_id}/ (via {sync.tool})" if sync.dest else
                 "Note: no --sync destination - results live only on this VM's disk. On Spot, use --sync gs://...")
        for rel in ("params", "netlist.sp", "run_info.txt"):
            sync.put_async(f"{run_id}/{rel}")

        install_signal_handlers()
        last_draw = last_progress = 0.0
        cloud_reported = False
        keys = ""

        # ------------------------------------------------------------ main loop
        while True:
            if not cloud_reported and watcher.cloud != "detecting":
                cloud_reported = True
                term.log({"GCP": "GCP detected - watching for Spot preemption notices",
                          "AWS": "AWS detected - watching for Spot interruption notices"}.get(
                    watcher.cloud, "No cloud metadata server found - preemption watcher off (SIGTERM is still handled)"))
            if SIGNALS["hup"]:
                SIGNALS["hup"] = False
                term.hangup()
                term.log("Terminal disconnected (SIGHUP) - continuing without a screen")
            if stop != "kill":
                if watcher.noticed.is_set():
                    stop, reason = "kill", "preempted"
                    term.log("*** Preemption notice received ***")
                elif SIGNALS["term"]:
                    stop, reason = "kill", "interrupted"
                elif SIGNALS["int"]:
                    stop, reason = "kill", "interrupted"

            for ch in keys:
                if stop == "kill":
                    break
                if ch == "q":
                    if stop is None:
                        stop, reason = "drain", "stopped"
                        info(f"Draining at {now_human()}: finishing {len(running)} running chunks, starting no new ones")
                    else:
                        stop, reason = None, None
                        info(f"Drain cancelled at {now_human()}")
                elif ch == "k":
                    stop, reason = "kill", "interrupted"
                elif ch in "+=-_[]":
                    step = {"+": 1, "=": 1, "-": -1, "_": -1, "]": 10, "[": -10}[ch]
                    workers = max(1, workers + step)
                    info(f"Workers -> {workers} at {now_human()}")
            keys = ""

            if stop == "kill":
                term.log(f"Stopping workers ({reason})...")
                kill_all()
                break

            reap()
            while stop is None and pending and len(running) < workers:
                start_chunk(*pending.pop(0))
            if not running and (not pending or stop == "drain"):
                break

            t = time.monotonic()
            if t - last_draw >= 0.5:
                last_draw = t
                if term.dashboard:
                    term.draw(dashboard())
            if args.progress_every > 0 and t - last_progress >= args.progress_every:
                if last_progress:                       # skip the empty line at t=0
                    line = progress_line()
                    (run_dir / "progress.txt").write_text(line + "\n")
                    sync.put_async(f"{run_id}/progress.txt")
                    if not term.dashboard:
                        term.log(line)
                last_progress = t
            keys = term.keys(0.25)

        # ---------------------------------------------------------------- wrap up
        if term.dashboard:
            term.draw(dashboard())
    finally:
        term.close()                                   # terminal restored even on an exception
        for job in running:                            # only non-empty after an exception
            try:
                os.killpg(job.proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    line = progress_line()
    (run_dir / "progress.txt").write_text(line + "\n")
    term.log(line)

    if timings:
        e = sum(t[0] for t in timings) / len(timings)
        u = sum(t[1] for t in timings) / len(timings)
        info(f"Chunk timing: {len(timings)} chunks, {e:.1f} s mean elapsed, {u:.1f} s mean user, "
             f"{max(t[2] for t in timings) / 1024:.0f} MB max peak")

    done_chunks = len(list(chunk_dir.glob("chunk_*.txt")))
    status = reason or ("ok" if done_chunks == nch and not failed else "failed")
    elapsed = time.monotonic() - start_mono
    spt = elapsed / session_trials if session_trials else 0.0
    tps = session_trials / elapsed if elapsed > 0 else 0.0
    if not LOG_CSV.exists():
        LOG_CSV.write_text("run_id,host,cpu,workers,trials,base_seed,start,end,elapsed_s,s_per_trial,trials_per_s,status\n")
    with open(LOG_CSV, "a") as f:
        f.write(f'{run_id},{HOST},"{cpu_model()}",{workers},{session_trials},{base_seed},{start_human},'
                f'{now_human()},{elapsed:.1f},{spt:.4f},{tps:.2f},{status}\n')
    summary = (f"{run_id} on {HOST}: {session_trials} trials finished this session, {workers} workers, "
               f"{hms(elapsed)} elapsed ({spt:.4f} s/trial, {tps:.2f} trials/s) [{status}]")
    with open("timing_results.txt", "a") as f:
        f.write(summary + "\n")
    info(summary)
    info(f"Progress: {done_chunks} of {nch} chunks done. Finished: {now_human()}")

    # Merge once everything is in. Column 1 is a duplicate of tplh_cout (wrdata's scale column).
    complete = done_chunks == nch
    if complete:
        merged = run_dir / MERGED
        with open(merged, "wb") as out:
            for k in range(nch):
                with open(chunk_dir / f"chunk_{k}.txt", "rb") as f:
                    header = f.readline()
                    if k == 0:
                        out.write(header)
                    shutil.copyfileobj(f, out)
        rows = data_rows(merged)
        info(f"Merged {rows} of {total} trials into {merged}")
        if rows != total:
            term.log("WARNING: row count doesn't match - check the chunk logs")
    else:
        term.log(f"Not merged yet: {nch - done_chunks} chunks missing.")

    # Push everything off the VM. When stopping for preemption, cap it: the VM is about to go away.
    if sync.dest:
        cap = 20 if reason in ("preempted", "interrupted") else None
        sync.wait(timeout=cap)
        if sync.mirror("up", run_id, timeout=cap):
            term.log(f"Synced to {sync.dest}/{run_id}/")
        else:
            term.log("Final sync didn't finish" + (" (chunks were uploaded as they completed)" if cap else ""))
        sync.shutdown()

    if not complete:
        term.log(f"Resume with:  ./{Path(__file__).name} resume {run_id} -w {workers}"
                 + (f" --sync {sync.dest}" if sync.dest else ""))
    return 0 if status == "ok" else 1


# ==================================================================================== commands

def cmd_status(args):
    run_id = args.run_id or newest_run()
    if not run_id or not (RUNS / run_id / "params").is_file():
        sys.exit(f"No run found{' named ' + args.run_id if args.run_id else ''}")
    run_dir = RUNS / run_id
    total, chunk, _ = read_params(run_dir)
    chunks = list((run_dir / "chunks").glob("chunk_*.txt"))
    done = sum(data_rows(c) for c in chunks)
    for log in (run_dir / "work").glob("chunk_*.log"):
        if not (run_dir / "chunks" / f"chunk_{log.stem.split('_', 1)[1]}.txt").exists():
            try:
                done += log.read_bytes().count(MARK)
            except OSError:
                pass
    print(f"Run {run_id}: {done} / {total} trials ({100 * done / total:.1f}%), "
          f"{len(chunks)} / {n_chunks(total, chunk)} chunks done, {ngspice_running()} ngspice running")
    prog = run_dir / "progress.txt"
    if prog.exists():
        age = int(time.time() - prog.stat().st_mtime)
        print(f"Last progress line ({age}s ago): {prog.read_text().strip()}")
    if (run_dir / MERGED).exists():
        print(f"Finished: {run_dir / MERGED}")


def make_sync(dest):
    sync = Sync(dest)
    if sync.dest and not sync.tool:
        sys.exit(f"--sync {sync.dest}: no gcloud/gsutil/aws CLI found for it")
    return sync


def cmd_run(args):
    if not SRC.exists():
        sys.exit(f"Missing {SRC}")
    total, workers = args.total, args.workers
    chunk = args.chunk or max(1, min(MAX_CHUNK, -(-total // (workers * 4))))
    if n_chunks(total, chunk) < workers:
        print(f"Warning: only {n_chunks(total, chunk)} chunks for {workers} workers - some will sit idle. Lower --chunk.")
    seed = args.seed if args.seed is not None else int.from_bytes(os.urandom(4), "little") % 2_000_000_000
    sync = make_sync(args.sync)

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    while (RUNS / run_id).exists():
        time.sleep(1)
        run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = RUNS / run_id
    run_dir.mkdir(parents=True)
    (run_dir / "params").write_text(f"TOTAL={total}\nCHUNK={chunk}\nBASE_SEED={seed}\n")
    shutil.copy2(SRC, run_dir / "netlist.sp")
    return run_session(run_id, workers, sync, "new", args)


def cmd_resume(args):
    run_id = args.run_id
    if run_id == "latest":
        run_id = newest_run(unfinished=True)
        if not run_id:
            sys.exit("No unfinished run in runs/ to resume")
    sync = make_sync(args.sync)
    if sync.dest:
        print(f"Pulling {run_id} from {sync.dest} ...")
        if not sync.mirror("down", run_id):
            print(f"Warning: download from {sync.dest} failed - using local files only")
    run_dir = RUNS / run_id
    if not (run_dir / "params").is_file():
        sys.exit(f"No run to resume at {run_dir} (missing params file)")
    if not (run_dir / "netlist.sp").exists():          # run started by an older launcher
        if not SRC.exists():
            sys.exit(f"Missing {run_dir}/netlist.sp and {SRC} - can't resume")
        shutil.copy2(SRC, run_dir / "netlist.sp")
    return run_session(run_id, args.workers, sync, "resumed", args)


def main():
    os.chdir(SCRIPT_DIR)
    env = os.environ.get

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("-w", "--workers", type=int, default=os.cpu_count(),
                        help="parallel ngspice copies (default: all cores)")
    common.add_argument("--sync", default=env("SYNC_DEST"), metavar="DEST",
                        help="copy results to gs://..., s3://... or a directory (env SYNC_DEST)")
    common.add_argument("--progress-every", type=float, default=float(env("PROGRESS_EVERY", 60)), metavar="S",
                        help="seconds between progress.txt updates / plain progress lines (default 60)")
    common.add_argument("--retries", type=int, default=1, help="retries for a failed chunk (default 1)")
    common.add_argument("--plain", action="store_true", help="plain line output instead of the dashboard")

    ap = argparse.ArgumentParser(description="Parallel full_adder Monte Carlo launcher.",
                                 epilog="See the top of this file for keys, Spot VM notes and the output layout.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", parents=[common], help="start a new run")
    r.add_argument("total", type=int, help="total Monte Carlo trials")
    r.add_argument("--chunk", type=int, default=int(env("CHUNK", 0)) or None,
                   help=f"trials per chunk (default: ~4 chunks per worker, max {MAX_CHUNK}; env CHUNK)")
    r.add_argument("--seed", type=int, default=int(env("BASE_SEED")) if env("BASE_SEED") else None,
                   help="base seed; chunk k uses seed+k (env BASE_SEED)")
    s = sub.add_parser("resume", parents=[common], help="finish an interrupted run")
    s.add_argument("run_id", help="run id, or 'latest' for the newest unfinished local run")
    st = sub.add_parser("status", help="show progress of a run (default: newest)")
    st.add_argument("run_id", nargs="?")
    args = ap.parse_args()

    if args.cmd == "status":
        return cmd_status(args)
    if not shutil.which("ngspice"):
        sys.exit("ngspice not found on PATH")
    if args.workers < 1:
        sys.exit("--workers must be at least 1")
    return cmd_run(args) if args.cmd == "run" else cmd_resume(args)


if __name__ == "__main__":
    sys.exit(main() or 0)
