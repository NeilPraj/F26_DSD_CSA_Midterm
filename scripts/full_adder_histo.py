import matplotlib.pyplot as plt
import numpy as np

data = np.loadtxt("../full_adder_mc/full_adder_mc.txt", skiprows=1)

#Toss scale column since its a duplicate of the first data column

data = data * 1e12

cout_lh = data[:,1]
cout_hl = data[:,2]
out_lh = data[:,3]
out_hl = data[:,4]

mean_cout_lh = np.mean(cout_lh)
mean_cout_hl = np.mean(cout_hl)
mean_out_lh = np.mean(out_lh)
mean_out_hl = np.mean(out_hl)

avg_cout = (mean_cout_hl + mean_cout_lh) / 2;
avg_out = (mean_out_hl + mean_out_lh) / 2; 

print(f"Average cout: {avg_cout}, Average out: {avg_out}")

fig, axs = plt.subplots(nrows=2, ncols=2, figsize=(10,4))

axs[0,0].hist(cout_hl, bins='auto', linewidth=0.5, edgecolor='white')
axs[0,0].set_title("Cout High -> Low Histogram")
axs[0,0].set_xlabel("Delay (ps)")
axs[0,0].axvline(mean_cout_hl, color="red", linestyle="dashed", linewidth="2", label=f"Mean: {mean_cout_hl:.2f}")

axs[0,1].hist(cout_lh, bins='auto', linewidth=0.5, edgecolor='white')
axs[0,1].set_title("Cout Low -> High Histogram")
axs[0,1].set_xlabel("Delay (ps)")
axs[0,1].axvline(mean_cout_lh, color="red", linestyle="dashed", linewidth="2", label=f"Mean: {mean_cout_lh:.2f}")

axs[1,0].hist(out_hl, bins='auto', linewidth=0.5, edgecolor='white')
axs[1,0].set_title("Out High -> Low Histogram")
axs[1,0].set_xlabel("Delay (ps)")
axs[1,0].axvline(mean_out_hl, color="red", linestyle="dashed", linewidth="2", label=f"Mean: {mean_out_hl:.2f}")

axs[1,1].hist(out_lh, bins='auto', linewidth=0.5, edgecolor='white')
axs[1,1].set_title("Out Low -> High Histogram")
axs[1,1].set_xlabel("Delay (ps)")
axs[1,1].axvline(mean_out_lh, color="red", linestyle="dashed", linewidth="2", label=f"Mean: {mean_out_lh:.2f}")

plt.tight_layout()
plt.show()


