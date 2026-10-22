#!/usr/bin/env python3
"""
Generate an ngspice Monte Carlo testbench for the 2:1 mux.

Two copies of the mux are simulated side by side: one with the select line
toggling (select delay) and one with an input toggling (input delay). Each run
applies a Gaussian (agauss) variation to the W and L of every listed
transistor, runs a transient, measures the propagation delays, and saves them
to a text file.

Usage:
    python gen.py                     # writes mux_mc.sp
    python gen.py -n 500 -o tb.sp     # 500 runs, custom filename
"""

import argparse

# ---------------------------------------------------------------------------
# Configuration: edit these to change the testbench
# ---------------------------------------------------------------------------

CELL_LIB = "../cell_lib.sp"
VDD = 3.3
LOAD_CAP = "10f"

# Instance path -> transistors to vary.
# Each instance gets its own nominal values captured before the loop,
# so instances with different sizing are still handled correctly.
MUX_DEVICES = ["mo0", "mo1"] + [f"m{i}" for i in range(10)]

INSTANCES = {
    "xselect": MUX_DEVICES,
    "xinput": MUX_DEVICES,
}

PARAMS = ["w", "l"]     # transistor parameters to vary
ABS_VARIATION = "18n"   # agauss absolute variation
SIGMA = 3               # variation is a SIGMA-sigma bound

# Transient settings: step, stop, start-saving
TRAN = ("10p", "150n", "40n")

# Delay measurements: name -> (trigger node, trigger edge, target node, target edge)
# Order here is the column order in the output file (scripts/mux_mc_histo.py
# expects select LH, select HL, input LH, input HL).
MEASUREMENTS = {
    "select_switch_lh": ("s_select", "fall", "out_select", "rise"),
    "select_switch_hl": ("s_select", "rise", "out_select", "fall"),
    "input_switch_lh":  ("a_input",  "rise", "out_input",  "rise"),
    "input_switch_hl":  ("a_input",  "fall", "out_input",  "fall"),
}

# The plot has no real scale vector, so wrdata uses the first vector created
# as column 1. Declaring this one first keeps that column the same as in the
# existing mux data files.
SCALE_VECTOR = "select_switch_hl"

DATA_FILE = "mux_mc_delays.txt"

# ---------------------------------------------------------------------------


def nominal_var(inst: str, dev: str, param: str) -> str:
    """Name of the vector holding a device's nominal value, e.g. nom_xselect_m0_w."""
    short_inst = inst.split(".")[-1]
    return f"nom_{short_inst}_{dev}_{param}"


def device_ref(inst: str, dev: str, param: str) -> str:
    """ngspice device-parameter reference, e.g. @m.xselect.m0[w]."""
    return f"@m.{inst}.{dev}[{param}]"


def build_netlist(mc_runs: int) -> str:
    half = VDD / 2
    lines = []
    add = lines.append

    # --- Circuit ---------------------------------------------------------
    add(f".include {CELL_LIB}")
    add("")
    add(".global vdd")
    add(".global vss")
    add(f"Vdd vdd 0 dc {VDD}v")
    add("Vss vss 0 dc 0")
    add("")
    add("* Select switch")
    add("Xselect a_select b_select s_select out_select mux2x1")
    add(f"Cload1 out_select vss {LOAD_CAP}")
    add("")
    add("* Input switch")
    add("Xinput a_input b_input s_input out_input mux2x1")
    add(f"Cload2 out_input vss {LOAD_CAP}")
    add("")
    add("* Select switch sources: A = 1, B = 0, S toggles 0 <-> 1")
    add("* So OUT goes low when S goes high, and high when S goes low")
    add(f"Va_select a_select 0 dc {VDD}")
    add("Vb_select b_select 0 dc 0")
    add(f"Vs_select s_select 0 PULSE(0v {VDD}v 50n 1n 1n 49n 100n)")
    add("")
    add("* Input switch sources: S = 0 (selects A), B = 0, A toggles 0 <-> 1")
    add(f"Va_input a_input 0 PULSE(0v {VDD}v 50n 1n 1n 49n 100n)")
    add("Vb_input b_input 0 dc 0")
    add("Vs_input s_input 0 dc 0")
    add("")

    # --- Control block: setup -------------------------------------------
    add(".control")
    add(f"let mc_runs = {mc_runs}")
    add("let current_run = 0")
    add("set curplot = new")
    add("set tran_meas = $curplot")
    for name in sorted(MEASUREMENTS, key=lambda n: n != SCALE_VECTOR):
        add(f"let {name} = vector(mc_runs)")
    add("")
    add("* agauss: absolute variation, rgauss: relative variation")
    add("define agauss(nom, avar, sig) (nom + avar/sig * sgauss(0))")
    add("define rgauss(nom, rvar, sig) (nom + nom*rvar/sig * sgauss(0))")
    add("")

    # Capture nominal sizes once, before anything is altered
    for inst, devices in INSTANCES.items():
        add(f"* Nominal sizes for {inst}")
        for dev in devices:
            for p in PARAMS:
                add(f"let {nominal_var(inst, dev, p)} = {device_ref(inst, dev, p)}")
        add("")

    # --- Control block: Monte Carlo loop --------------------------------
    add("dowhile current_run < mc_runs")
    for inst, devices in INSTANCES.items():
        for p in PARAMS:
            for dev in devices:
                add(f"  alter {device_ref(inst, dev, p)} = "
                    f"agauss({nominal_var(inst, dev, p)}, {ABS_VARIATION}, {SIGMA})")
            add("")

    step, stop, start = TRAN
    add(f"  tran {step} {stop} {start}")
    for name, (trig_node, trig_edge, targ_node, targ_edge) in MEASUREMENTS.items():
        add(f"  meas tran meas_{name} TRIG v({trig_node}) val={half:g} {trig_edge}=1 "
            f"targ v({targ_node}) val={half:g} {targ_edge}=1")
    add("")
    add("  set simplot = $curplot")
    add("  setplot $tran_meas")
    add("")
    for name in MEASUREMENTS:
        add(f"  let {name}[current_run] = {{$simplot}}.meas_{name}")
    add("")
    add("  destroy $simplot")
    add("  let current_run = current_run + 1")
    add("end")
    add("")

    # --- Output ----------------------------------------------------------
    vectors = " ".join(MEASUREMENTS)
    add(f"print {vectors}")
    add("")
    add("* write the scale column once, and add a header row of vector names")
    add("set wr_singlescale")
    add("set wr_vecnames")
    add(f"wrdata {DATA_FILE} {vectors}")
    add("")
    add("quit")
    add(".endc")
    add("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-n", "--runs", type=int, default=1000,
                        help="number of Monte Carlo runs (default: 1000)")
    parser.add_argument("-o", "--output", default="mux_mc.sp",
                        help="output netlist filename (default: mux_mc.sp)")
    args = parser.parse_args()

    netlist = build_netlist(args.runs)
    with open(args.output, "w") as f:
        f.write(netlist)
    print(f"Wrote {args.output} ({args.runs} runs, "
          f"{sum(len(d) for d in INSTANCES.values())} devices varied)")


if __name__ == "__main__":
    main()
