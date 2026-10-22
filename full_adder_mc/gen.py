#!/usr/bin/env python3
"""
Generate an ngspice Monte Carlo testbench for the full adder.

Each run applies a Gaussian (agauss) variation to the W and L of every
listed transistor, runs a transient, measures the cin->cout and cin->out
propagation delays, and saves them to a text file.

Usage:
    python gen_mc_testbench.py                     # writes full_adder_mc.sp
    python gen_mc_testbench.py -n 500 -o tb.sp     # 500 runs, custom filename
"""

import argparse

# ---------------------------------------------------------------------------
# Configuration: edit these to change the testbench
# ---------------------------------------------------------------------------

CELL_LIB = "../cell_lib.sp"
VDD = 3.3
LOAD_CAP = "10f"

# Instance path inside the DUT -> transistors to vary.
# Each instance gets its own nominal values captured before the loop,
# so instances with different sizing are still handled correctly.
XOR_DEVICES = [f"m{i}" for i in range(10)]
MUX_DEVICES = ["mo0", "mo1"] + [f"m{i}" for i in range(10)]

INSTANCES = {
    "xdut.xxor1": XOR_DEVICES,
    "xdut.xxor2": XOR_DEVICES,
    "xdut.xmux1": MUX_DEVICES,
}

PARAMS = ["w", "l"]     # transistor parameters to vary
ABS_VARIATION = "18n"    # agauss absolute variation
SIGMA = 3               # variation is a SIGMA-sigma bound

# Transient settings: step, stop, start-saving
TRAN = ("10p", "150n", "40n")

# Delay measurements: name -> (trigger edge on cin, target node, target edge)
# Order here is the column order in the output file.
MEASUREMENTS = {
    "tplh_cout": ("rise", "cout", "rise"),
    "tphl_cout": ("fall", "cout", "fall"),
    "tplh_out":  ("fall", "out",  "rise"),
    "tphl_out":  ("rise", "out",  "fall"),
}

DATA_FILE = "full_adder_mc.txt"

# ---------------------------------------------------------------------------


def nominal_var(inst: str, dev: str, param: str) -> str:
    """Name of the vector holding a device's nominal value, e.g. nom_xxor1_m0_w."""
    short_inst = inst.split(".")[-1]
    return f"nom_{short_inst}_{dev}_{param}"


def device_ref(inst: str, dev: str, param: str) -> str:
    """ngspice device-parameter reference, e.g. @m.xdut.xxor1.m0[w]."""
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
    add("xdut a b cin out cout full_adder")
    add(f"Cload out vss {LOAD_CAP}")
    add(f"Cload1 cout vss {LOAD_CAP}")
    add("")
    add("* Input voltage sources")
    add("* A = 1, B = 0, cin toggles 0 <-> 1")
    add("* So SUM goes low when CIN goes high, and high when CIN goes low")
    add(f"Va a 0 dc {VDD}")
    add("Vb b 0 dc 0")
    add(f"Vcin cin 0 PULSE(0v {VDD}v 50n 1n 1n 49n 100n)")
    add("")

    # --- Control block: setup -------------------------------------------
    add(".control")
    add(f"let mc_runs = {mc_runs}")
    add("let current_run = 0")
    add("set curplot = new")
    add("set tran_meas = $curplot")
    for name in MEASUREMENTS:
        add(f"let {name}_delays = vector(mc_runs)")
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
    for name, (trig_edge, node, targ_edge) in MEASUREMENTS.items():
        add(f"  meas tran {name} TRIG v(cin) val={half:g} {trig_edge}=1 "
            f"targ v({node}) val={half:g} {targ_edge}=1")
    add("")
    add("  set simplot = $curplot")
    add("  setplot $tran_meas")
    add("")
    for name in MEASUREMENTS:
        add(f"  let {name}_delays[current_run] = {{$simplot}}.{name}")
    add("")
    add("  destroy $simplot")
    add("  let current_run = current_run + 1")
    add("end")
    add("")

    # --- Output ----------------------------------------------------------
    vectors = " ".join(f"{name}_delays" for name in MEASUREMENTS)
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
    parser.add_argument("-o", "--output", default="full_adder_mc.sp",
                        help="output netlist filename (default: full_adder_mc.sp)")
    args = parser.parse_args()

    netlist = build_netlist(args.runs)
    with open(args.output, "w") as f:
        f.write(netlist)
    print(f"Wrote {args.output} ({args.runs} runs, "
          f"{sum(len(d) for d in INSTANCES.values())} devices varied)")


if __name__ == "__main__":
    main()
