import matplotlib.pyplot as plt
import numpy as np

data = np.loadtxt("../mux_mc/mux_mc_delays.txt", skiprows=1)

print(data)

select_lh = data[:,1]
select_hl = data[:,2]
input_lh = data[:,3]
input_hl = data[:,4]

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
    ax.legend()

plt.tight_layout()
plt.show()
    
