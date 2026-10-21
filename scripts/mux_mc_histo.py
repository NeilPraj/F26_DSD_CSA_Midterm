import matplotlib.pyplot as plt
import numpy as np
from scipy.stats import norm
import os

K = 3
OUT_DIR = "mux_plots"
os.makedirs(OUT_DIR, exist_ok=True)

data = np.loadtxt("../mux_mc_runs/total_mux_mc_delays_merged.txt", skiprows=1)
data = data[:, 1:] * 1e12                      # drop scale column, convert to ps

# Drop runs where any measurement failed
good = ~np.isnan(data).any(axis=1)
print(f"Runs: {len(data)}, dropped (failed meas): {(~good).sum()}")
data = data[good]

signals = {
    "SELECT LH": data[:, 0], "SELECT HL": data[:, 1],
    "INPUT LH":  data[:, 2], "INPUT HL":  data[:, 3],
}
signals["SELECT tpd"] = (signals["SELECT LH"] + signals["SELECT HL"]) / 2
signals["INPUT tpd"]  = (signals["INPUT LH"]  + signals["INPUT HL"])  / 2

# ---------------------------------------------------------------- stats table
print(f"{'Signal':<12}{'mean':>9}{'median':>9}{'sigma':>8}{'min':>9}{'max':>9}"
      f"{f'mu-{K}s':>9}{f'mu+{K}s':>9}")
for name, x in signals.items():
    mu, s = x.mean(), x.std(ddof=1)
    print(f"{name:<12}{mu:9.2f}{np.median(x):9.2f}{s:8.2f}"
          f"{x.min():9.2f}{x.max():9.2f}{mu - K*s:9.2f}{mu + K*s:9.2f}")


# ---------------------------------------------------------------- plotting
def centered_limits(x):
    """Symmetric x-limits around the mean, wide enough to hold all data
    and the +/-K sigma markers."""
    mu, s = x.mean(), x.std(ddof=1)
    half = max(K*s, mu - x.min(), x.max() - mu) * 1.05
    return mu - half, mu + half


def plot_hist(ax, name, x):
    mu, s = x.mean(), x.std(ddof=1)
    # "auto" picks hundreds of hairline bins for huge N; cap it so bars stay readable
    bins = "auto" if len(x) < 10_000 else 80
    ax.hist(x, bins=bins, density=True, edgecolor="white", linewidth=0.5)
    xs = np.linspace(x.min(), x.max(), 200)
    ax.plot(xs, norm.pdf(xs, mu, s), "k-", lw=1, label="Gaussian fit")
    ax.axvline(mu, color="red", ls="--", lw=1.5, label=f"μ = {mu:.2f} ps")
    ax.axvline(mu - K*s, color="orange", ls=":", lw=1.5, label=f"μ−{K}σ = {mu-K*s:.2f} ps")
    ax.axvline(mu + K*s, color="orange", ls=":", lw=1.5, label=f"μ+{K}σ = {mu+K*s:.2f} ps")
    ax.set_xlim(centered_limits(x))
    ax.set_title(f"{name} (σ = {s:.2f} ps)")
    ax.set_xlabel("Delay (ps)")
    ax.legend(fontsize=8)


def save(fig, fname):
    fig.savefig(f"{OUT_DIR}/{fname}.png", dpi=300, bbox_inches="tight")
    fig.savefig(f"{OUT_DIR}/{fname}.svg", bbox_inches="tight")


def to_fname(name):
    return name.replace(" ", "_").lower()           # "SELECT LH" -> "select_lh"


names = ["SELECT LH", "SELECT HL", "INPUT LH", "INPUT HL"]
names_tpd = ["SELECT tpd", "INPUT tpd"]

# Individual figures, one file each
for name in names + names_tpd:
    fig, ax = plt.subplots(figsize=(6, 4))
    plot_hist(ax, name, signals[name])
    fig.tight_layout()
    save(fig, to_fname(name))
    plt.close(fig)                                  # don't pop up extra windows

# Side-by-side LH | HL pairs, one figure per path.
# Each panel gets its own scale, centered on its own mean.
pairs = {
    "SELECT": ("SELECT LH", "SELECT HL"),
    "INPUT":  ("INPUT LH",  "INPUT HL"),
}
for path_name, (lh, hl) in pairs.items():
    fig, axs = plt.subplots(1, 2, figsize=(12, 4))
    plot_hist(axs[0], lh, signals[lh])
    plot_hist(axs[1], hl, signals[hl])
    axs[0].set_ylabel("Probability density")
    fig.suptitle(f"MUX {path_name} Propagation Delay: LH vs HL (N = {len(data)})")
    fig.tight_layout()
    save(fig, f"{path_name.lower()}_lh_hl_pair")
    plt.close(fig)

# Combined 2x2 grid
fig, axs = plt.subplots(2, 2, figsize=(10, 7))
for ax, name in zip(axs.flat, names):
    plot_hist(ax, name, signals[name])
fig.suptitle(f"MUX Monte Carlo Propagation Delay (N = {len(data)})")
fig.tight_layout()
save(fig, "combined")
plt.show()
