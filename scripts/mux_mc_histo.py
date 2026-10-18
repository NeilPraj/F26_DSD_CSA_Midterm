import matplotlib.pyplot as plt
import numpy as np

data = np.loadtxt("../mux_mc_runs/total_mux_mc_delays_merged.txt", skiprows=1)

data = data * 1e12

select_lh = data[:,1]
select_hl = data[:,2]
input_lh = data[:,3]
input_hl = data[:,4]

median_select_lh = np.median(select_lh)
median_select_hl = np.median(select_hl)
median_input_lh = np.median(input_lh)
median_input_hl = np.median(input_hl)

average_select = np.mean((select_hl + select_lh) / 2)
average_input = np.mean((input_lh + input_hl) / 2)



print(
    f"--- Propagation Delay Medians ---\n"
    f"  SELECT (LH / HL): {median_select_lh:.4f} / {median_select_hl:.4f}\n"
    f"  INPUT  (LH / HL): {median_input_lh:.4f} / {median_input_hl:.4f}\n"
    f"---------------------------------"
)
print(f"Average Select time: {average_select:.4f} | Average Data Input time: {average_input:.4f}")



fix, axs = plt.subplots(nrows=2, ncols=2, figsize=(10,6))

datasets = [
    ("Select Low -> High", select_lh),
    ("Select High -> Low", select_hl),
    ("Input Low -> High",  input_lh),
    ("Input High -> Low",  input_hl),
]

                        
for ax, (title, data) in zip(axs.flat, datasets):
    ax.hist(data, bins="auto", linewidth=0.5, edgecolor="white")
    #ax.axvline(mean, color="red", linestyle="--", linewidth=2, label=f"Mean: {mean:.2f}")
    ax.set_title(f"{title} Histogram")
    ax.set_xlabel("Delay (ps)")

plt.tight_layout()
plt.show()
    
