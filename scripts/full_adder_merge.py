#!/usr/bin/env python3
"""
Merge every full-adder Monte Carlo run into one file and summarize the compute
that produced it.

Expected layout:
    full_adder_runs/
        <group>/                      e.g. gcloud_4
            timing_log.csv            one row per session, run_id = run folder name
            <run_id>/
                full_adder_mc_merged.txt
                run_info.txt
                ...
        other_compute/                no timing log; files have the same format as
            *.txt                     full_adder_mc_merged.txt, different names

Outputs (written into full_adder_runs/):
    total_full_adder_mc_merged.txt    all trials, one header line, original text kept
    full_adder_mc_analysis.txt        the report also printed to the terminal
"""

import csv
from collections import defaultdict
from datetime import datetime
from pathlib import Path

# ---- Settings ---------------------------------------------------------------
RUNS_DIR = (Path(__file__).parent / ".." / "full_adder_runs").resolve()
MERGED_NAME = "full_adder_mc_merged.txt"

OTHER_COMPUTE_DIR_NAME = "other_compute"  # folder whose files have no timing log
OTHER_COMPUTE_GLOB = "*.txt"              # which files in it are data files

# The other_compute files were run on the m720q. Its speed is taken from any
# timing_log.csv row whose host or cpu contains this text (case-insensitive).
M720Q_MATCH = "m720q"
# Fallback if no timing log mentions the m720q: seconds per trial, e.g. 0.41.
M720Q_S_PER_TRIAL = None
M720Q_LABEL = "m720q"                     # compute-type name if the CPU is unknown

OUTPUT_MERGED = RUNS_DIR / "total_full_adder_mc_merged.txt"
OUTPUT_REPORT = RUNS_DIR / "full_adder_mc_analysis.txt"
# -----------------------------------------------------------------------------


def parse_time(text):
    return datetime.strptime(text, "%Y-%m-%d %H:%M:%S")


def fmt_duration(seconds):
    total = int(round(seconds))
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    return f"{h}h {m:02d}m {s:02d}s"


def new_run(label, path, compute):
    """One entry per data file. Fields that are unknown stay None."""
    return {
        "label": label, "path": path, "compute": compute,
        "host": None, "workers": None, "base_seed": None,
        "logged_trials": None, "elapsed_s": None,
        "start": None, "end": None, "status": None,
        "trials": 0, "estimated": False,
    }


def collect_runs(warnings):
    runs = []
    logged_paths = set()

    # 1. Runs listed in each group's timing_log.csv
    for log_path in sorted(RUNS_DIR.glob("*/timing_log.csv")):
        group = log_path.parent
        if group.name == OTHER_COMPUTE_DIR_NAME:
            continue

        # A run that was stopped and resumed logs one row per session,
        # so group the rows by run_id and add the sessions up.
        sessions = defaultdict(list)
        with log_path.open(newline="") as fh:
            for row in csv.DictReader(fh):
                sessions[row["run_id"]].append(row)

        for run_id, rows in sessions.items():
            data_path = group / run_id / MERGED_NAME
            label = f"{group.name}/{run_id}"
            if not data_path.is_file():
                warnings.append(f"{label}: in timing_log.csv but has no {MERGED_NAME}; skipped")
                continue

            first = rows[0]
            run = new_run(label, data_path, first["cpu"])
            run["host"] = first["host"]
            run["workers"] = int(first["workers"])
            run["base_seed"] = int(first["base_seed"])
            run["logged_trials"] = sum(int(r["trials"]) for r in rows)
            run["elapsed_s"] = sum(float(r["elapsed_s"]) for r in rows)
            run["start"] = min(parse_time(r["start"]) for r in rows)
            run["end"] = max(parse_time(r["end"]) for r in rows)
            run["status"] = ",".join(sorted({r["status"] for r in rows}))
            if len({r["host"] for r in rows}) > 1:
                warnings.append(f"{label}: sessions ran on more than one host; using {first['host']}")
            runs.append(run)
            logged_paths.add(data_path.resolve())

    # 2. Merged files that no timing log mentions: keep the data, time unknown
    for data_path in sorted(RUNS_DIR.glob(f"*/*/{MERGED_NAME}")):
        if data_path.parent.parent.name == OTHER_COMPUTE_DIR_NAME:
            continue
        if data_path.resolve() not in logged_paths:
            label = f"{data_path.parent.parent.name}/{data_path.parent.name}"
            warnings.append(f"{label}: no timing_log.csv entry; included with unknown time")
            runs.append(new_run(label, data_path, "unknown (no timing log)"))

    # 3. other_compute files (run on the m720q, no timing data)
    other_dir = RUNS_DIR / OTHER_COMPUTE_DIR_NAME
    for data_path in sorted(other_dir.glob(OTHER_COMPUTE_GLOB)):
        run = new_run(f"{OTHER_COMPUTE_DIR_NAME}/{data_path.name}", data_path, None)
        run["estimated"] = True
        runs.append(run)

    return runs


def merge_data(runs, warnings):
    """Read every file, count trials, and build the combined text."""
    header = None
    ncols = None
    out_rows = []

    for run in runs:
        lines = run["path"].read_text().splitlines()
        if not lines:
            warnings.append(f"{run['label']}: empty file; skipped")
            continue
        file_header = lines[0]
        rows = [line for line in lines[1:] if line.strip()]

        if header is None:
            header = file_header
            ncols = len(rows[0].split()) if rows else None
        elif file_header != header:
            warnings.append(f"{run['label']}: header differs from the first file")

        bad = sum(1 for line in rows if len(line.split()) != ncols)
        if bad:
            warnings.append(f"{run['label']}: {bad} rows do not have {ncols} columns")

        run["trials"] = len(rows)
        if run["logged_trials"] is not None and run["logged_trials"] != run["trials"]:
            warnings.append(f"{run['label']}: timing log says {run['logged_trials']} trials, "
                            f"file has {run['trials']}")
        out_rows.extend(rows)

    if header is None:
        raise FileNotFoundError(f"No data files found under {RUNS_DIR}")
    return header, out_rows


def fill_in_m720q(runs, warnings):
    """Estimate time for other_compute files from the m720q's measured speed."""
    m720q_runs = [r for r in runs if not r["estimated"] and r["elapsed_s"]
                  and (M720Q_MATCH in r["host"].lower() or M720Q_MATCH in r["compute"].lower())]

    if m720q_runs:
        s_per_trial = sum(r["elapsed_s"] for r in m720q_runs) / sum(r["trials"] for r in m720q_runs)
        compute = m720q_runs[0]["compute"]
        source = f"measured from {len(m720q_runs)} logged m720q run(s)"
    elif M720Q_S_PER_TRIAL is not None:
        s_per_trial = M720Q_S_PER_TRIAL
        compute = M720Q_LABEL
        source = "M720Q_S_PER_TRIAL setting"
    else:
        s_per_trial = None
        compute = M720Q_LABEL
        source = None

    for run in runs:
        if run["estimated"]:
            run["compute"] = compute
            if s_per_trial is not None:
                run["elapsed_s"] = run["trials"] * s_per_trial

    if s_per_trial is None and any(r["estimated"] for r in runs):
        warnings.append("No m720q timing found and M720Q_S_PER_TRIAL is not set; "
                        "other_compute time is unknown")
    return s_per_trial, source


def build_report(runs, s_per_trial, source, warnings):
    out = []
    total_trials = sum(r["trials"] for r in runs)

    out.append("FULL ADDER MONTE CARLO SUMMARY")
    out.append(f"Generated {datetime.now():%Y-%m-%d %H:%M:%S}")
    out.append(f"Data folder: {RUNS_DIR}")
    out.append("")

    # 1. Totals
    out.append("== 1. Total simulation runs ==")
    out.append(f"Runs (data files): {len(runs)}")
    out.append(f"Total trials:      {total_trials:,}")
    out.append("")
    out.append(f"{'run':<34} {'compute':<24} {'trials':>9} {'elapsed':>13}")
    for r in runs:
        elapsed = fmt_duration(r["elapsed_s"]) if r["elapsed_s"] is not None else "unknown"
        if r["estimated"] and r["elapsed_s"] is not None:
            elapsed += "*"
        out.append(f"{r['label']:<34} {r['compute'][:24]:<24} {r['trials']:>9,} {elapsed:>13}")
    if any(r["estimated"] for r in runs):
        out.append("* estimated from the m720q's speed")
    out.append("")

    # 2. Base seeds
    out.append("== 2. Base seeds ==")
    seeded = sorted((r for r in runs if r["base_seed"] is not None), key=lambda r: r["base_seed"])
    for r in seeded:
        out.append(f"{r['label']:<34} base_seed {r['base_seed']:>12}   trials {r['trials']:>9,}")
    unseeded = [r["label"] for r in runs if r["base_seed"] is None]
    if unseeded:
        out.append(f"No seed recorded: {', '.join(unseeded)}")

    # Overlap check, assuming trial i uses seed base_seed + i
    problems = []
    for a, b in zip(seeded, seeded[1:]):
        if a["base_seed"] == b["base_seed"]:
            problems.append(f"DUPLICATE base seed {a['base_seed']}: {a['label']} and {b['label']}")
        elif b["base_seed"] < a["base_seed"] + a["trials"]:
            problems.append(f"OVERLAP: {a['label']} seeds {a['base_seed']}..{a['base_seed'] + a['trials'] - 1} "
                            f"include {b['label']} base {b['base_seed']}")
    out.append("Seed ranges (assuming trial i uses base_seed + i): "
               + ("no duplicates or overlaps" if not problems else ""))
    out.extend("  " + p for p in problems)
    out.append("")

    # 3. Time spent
    out.append("== 3. Time spent ==")
    timed = [r for r in runs if r["elapsed_s"] is not None]
    measured = sum(r["elapsed_s"] for r in timed if not r["estimated"])
    estimated = sum(r["elapsed_s"] for r in timed if r["estimated"])
    out.append(f"Machine time, measured:  {fmt_duration(measured)} ({measured / 3600:.2f} h)")
    if estimated:
        out.append(f"Machine time, estimated: {fmt_duration(estimated)} ({estimated / 3600:.2f} h)")
        out.append(f"Machine time, total:     {fmt_duration(measured + estimated)} "
                   f"({(measured + estimated) / 3600:.2f} h)")
    worker_s = sum(r["elapsed_s"] * r["workers"] for r in timed if r["workers"])
    out.append(f"Worker time (elapsed x workers, logged runs): {worker_s / 3600:.2f} worker-hours")
    starts = [r["start"] for r in runs if r["start"]]
    ends = [r["end"] for r in runs if r["end"]]
    if starts:
        span = (max(ends) - min(starts)).total_seconds()
        out.append(f"Wall-clock span of logged runs: {min(starts):%Y-%m-%d %H:%M} to "
                   f"{max(ends):%Y-%m-%d %H:%M} ({fmt_duration(span)})")
        out.append("  Machine time can exceed the span because machines ran in parallel.")
    if s_per_trial is not None and any(r["estimated"] for r in runs):
        out.append(f"m720q speed used for estimates: {s_per_trial:.4f} s/trial ({source})")
    out.append("")

    # 4 and 5. Per compute type
    groups = defaultdict(list)
    for r in runs:
        groups[r["compute"]].append(r)

    out.append("== 4. Throughput per compute type ==")
    out.append(f"{'compute type':<28} {'runs':>5} {'trials':>10} {'machine time':>14} "
               f"{'trials/s':>9} {'trials/s/worker':>16}")
    for compute, rs in sorted(groups.items(), key=lambda kv: -sum(r["trials"] for r in kv[1])):
        trials = sum(r["trials"] for r in rs)
        timed_rs = [r for r in rs if r["elapsed_s"]]
        elapsed = sum(r["elapsed_s"] for r in timed_rs)
        rate = sum(r["trials"] for r in timed_rs) / elapsed if elapsed else None
        worked = [r for r in timed_rs if r["workers"]]
        w_s = sum(r["elapsed_s"] * r["workers"] for r in worked)
        per_worker = sum(r["trials"] for r in worked) / w_s if w_s else None
        mark = "*" if any(r["estimated"] for r in rs) else ""
        out.append(f"{compute[:28]:<28} {len(rs):>5} {trials:>10,} "
                   f"{(fmt_duration(elapsed) + mark) if elapsed else 'unknown':>14} "
                   f"{f'{rate:.2f}' if rate else '-':>9} {f'{per_worker:.3f}' if per_worker else '-':>16}")
    out.append("trials/s = trials / machine time for that type. * includes estimated time.")
    out.append("")

    out.append("== 5. Share of total output ==")
    for compute, rs in sorted(groups.items(), key=lambda kv: -sum(r["trials"] for r in kv[1])):
        trials = sum(r["trials"] for r in rs)
        pct = 100 * trials / total_trials if total_trials else 0
        bar = "#" * round(pct / 2)
        out.append(f"{compute[:28]:<28} {trials:>10,}  {pct:6.2f}%  {bar}")
    out.append("")

    if warnings:
        out.append("== Warnings ==")
        out.extend("- " + w for w in warnings)
        out.append("")

    return "\n".join(out)


def main():
    if not RUNS_DIR.is_dir():
        raise FileNotFoundError(f"{RUNS_DIR} does not exist")

    warnings = []
    runs = collect_runs(warnings)
    if not runs:
        raise FileNotFoundError(f"No runs found under {RUNS_DIR}")

    header, rows = merge_data(runs, warnings)
    runs = [r for r in runs if r["trials"] > 0 or r["logged_trials"]]
    s_per_trial, source = fill_in_m720q(runs, warnings)

    OUTPUT_MERGED.write_text(header + "\n" + "\n".join(rows) + "\n")

    report = build_report(runs, s_per_trial, source, warnings)
    report += f"\nWrote {len(rows):,} trials to {OUTPUT_MERGED.name}\n"
    OUTPUT_REPORT.write_text(report)
    print(report)


if __name__ == "__main__":
    main()
