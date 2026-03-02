import numpy as np
import matplotlib.pyplot as plt
from functools import partial
data=np.genfromtxt("data/event_top_tb.txt", delimiter=" ", skip_header=1, unpack=True)
names="clk_counter wr_enable trigs trig_deadtime wr_pointer wr_busy wr_done event_ready rd_pointer rd_lock rd_done rd_enable rd_valid data_o"
names=names.split(" ")
#print(data[0])

#print(np.char.mod('%d', data[0]))
int_base_2 = partial(int, base=2)
clk=np.array(list(map(int_base_2,np.char.mod('%d', data[0]))))
trigs=np.array(list(map(int_base_2,np.char.mod('%d', data[2]))))
wr_pointer=np.array(list(map(int_base_2,np.char.mod('%d', data[4]))))
wr_busy=np.array(list(map(int_base_2,np.char.mod('%d', data[5]))))
wr_done=np.array(list(map(int_base_2,np.char.mod('%d', data[6]))))
rd_pointer=np.array(list(map(int_base_2,np.char.mod('%d', data[8]))))



fig, ax = plt.subplots(13, 1, figsize=(10,6), sharex=True)
ax[0].plot(clk,data[1], label="wr enable")
ax[1].plot(clk,trigs, label="trig")
ax[2].plot(clk,data[3], label="trig deadtime")

ax[3].plot(clk, wr_pointer&0x1, label="write pointer evt 0")
ax[4].plot(clk, (wr_pointer&0x2)>>1, label="write pointer evt 1")

ax[5].plot(clk, wr_busy&0x1, label="write busy evt 0")
ax[6].plot(clk, (wr_busy&0x2)>>1, label="write busy evt 1")

ax[7].plot(clk, wr_done&0x1, label="write done evt 0")
ax[8].plot(clk, (wr_done&0x2)>>1, label="write done evt 1")

ax[9].plot(clk, data[7], label="event ready")

ax[10].plot(clk, (rd_pointer&0x1), label="read pointer evt 0")
ax[11].plot(clk, (rd_pointer&0x2)>>1, label="read pointer evt 1")

ax[12].plot(clk, data[11], label="read enable")



for i in range(13):
    ax[i].legend(loc="center right")
fig.supxlabel("Clk")



plt.show()