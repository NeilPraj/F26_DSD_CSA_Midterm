import matplotlib.pyplot as plt
import numpy as np

data = np.loadtxt("../mux_mc/mux_mc_delays.txt", skiprows=1)

print(data)

select_lh = data[:,1]
select_hl = data[:,2]
input_lh = data[:,3]
input_hl = data[:,4]

fix, axs = plt.subplots(nrows=2, ncols=2, figsize=(10,6))



                        

