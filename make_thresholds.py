import numpy as np

thresholds=np.ones(24,dtype=int)*20

f=open("data/input_channel_thresholds.txt","w")
for i in range(24):
    f.write(f"{thresholds[-i]:08b} ")
f.close()

thresholds=np.ones(12,dtype=int)*64
#thresholds=np.array([200,200,200,200,1,1,1,1,1,1,1,1])

f=open("data/input_pa_thresholds.txt","w")
for i in range(12):
    f.write(f"{thresholds[-i]:08b} ")
f.close()
