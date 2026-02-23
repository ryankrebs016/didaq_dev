import numpy as np
import matplotlib.pyplot as plt
from functools import partial
data=np.genfromtxt("data/ram_tb.txt",delimiter=" ",skip_header=1,unpack=True)
names=["clk_counter","enable_i","trigger_i","ram_enable","wr_finished_o","rd_done_i"]
print(data[0])

print(np.char.mod('%d', data[0]))
int_base_2 = partial(int, base=2)
clk=np.array(list(map(int_base_2,np.char.mod('%d', data[0]))))
#data["clk_counter"]=data["clk_counter"]
fig, ax = plt.subplots(len(data)-1,1,figsize=(10,6),sharex=True)

for i in range(len(data)-1):
    print(i)
    ax[i].plot(clk,data[i+1])
    ax[i].set_ylabel(names[i+1])
    ax[i].set_ylim(0,1.2)
    ax[i].set_yticks([])
#fig.legend()
ax[0].set_xlim(0,1100)
fig.supxlabel("clk")
fig.tight_layout()
fig.subplots_adjust(hspace=0)
plt.show()