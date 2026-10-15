#!/usr/bin/env python3
import matplotlib.pyplot as plt
import numpy as np

data = np.loadtxt("./agauss_output.txt", skiprows=1)

gauss_vals = data[:,1]

fig, ax = plt.subplots()

ax.hist(gauss_vals, bins=50, linewidth=0.5, edgecolor='white')
plt.show()
