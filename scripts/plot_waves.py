import numpy as np
import matplotlib.pyplot as plt
import json

beam_colors=[plt.cm.tab20(i) for i in range(12)]

def get_peak_average_power(trace,window=24):
    pows=trace*trace
    peak=0
    for i in range(len(trace)-window):
        avg_pow=np.sum(pows[i:i+window])
        if avg_pow>peak:
            peak=avg_pow
    return peak/32

input_data=np.loadtxt("data/plot_input_waveforms.txt")

f=open("data/output_upsampled.txt")
up_data=np.zeros((4,1024*4))
for i in range(256):
    line=f.readline()
    vals=(line.split(" "))[0:64]

    for j in range(64):
        val=(int(vals[j],2)-128)
        ch=int(np.trunc(j/16))
        sam=16*i+(15-j % 16)
        up_data[ch][sam]=val

f=open("data/output_beamformed.txt")
beam_data=np.zeros((12,1024*4))
for i in range(256):
    line=f.readline()
    vals=(line.split(" "))[0:12*16]

    for j in range(12*16):
        val=(int(vals[j],2)-128)
        bm=int(np.trunc(j/16))
        sam=16*i+(15-j % 16)
        beam_data[bm][sam]=val

f=open("data/output_power.txt")
power_data=np.zeros((12,1024))
for i in range(256):
    line=f.readline()

    if "X" in line:
        for j in range(12*4):
            bm=int(np.trunc(j/4))
            sam=4*i+(3-j % 4)
            power_data[bm][sam]=0

    else:
        vals=(line.split(" "))
        for j in range(12*4):
            val=(int(vals[j],2))
            bm=int(np.trunc(j/4))
            sam=4*i+(3-j % 4)
            power_data[bm][sam]=val

trigs=np.loadtxt("data/output_trigger.txt")

f=.472
beams=list(np.arange(0,12,1))
t_base=np.arange(0,1024,1)/f
t_up=np.arange(0,1024,.25)/f
t_beamformed=np.arange(0,1024,.25)/f
t_power=np.arange(0,1024,1)/f
t_trig=np.arange(0,1024,4)/f

ts_base=np.arange(0,1024,1)
ts_up=np.arange(0,1024,.25)

fig,ax=plt.subplots(3,1,sharex=True,figsize=(10,8))
for i in range(4):
    ax[0].plot(t_base,input_data[i],label="ch %i input"%i)
    ax[0].plot(t_up,up_data[i],label="ch %i upsampled"%i)
print(list(up_data[3]))
ax[0].legend(loc="upper right",fontsize=7)
ax[0].set_ylabel("Channel Traces [adc]")
np.save("data/processed_upsampled.npy",up_data)
for i in range(12):
    ax[1].plot(t_beamformed,beam_data[i],label="beam %i"%i,color=beam_colors[i])
    #print(get_peak_average_power(beam_data[i]))
ax[1].legend(loc="upper right",fontsize=7)
ax[1].set_ylabel("Phased Traces [adc]")
np.save("data/processed_beam_traces.npy",beam_data)

for i in range(12):
    ax[2].plot(t_power,power_data[i],label="beam %i"%i,color=beam_colors[i])

ax[2].vlines(t_trig[np.where(trigs>0)[0]],0,np.max(power_data.flatten()),linestyle="--",color="black",label="trigger") #ax[2].plot(t_trig,trigs*np.max(p),label="triggers")
ax[2].legend(loc="upper right",fontsize=7)
ax[2].set_ylabel("Beam Power [adc$^2$]")
np.save("data/processed_powers.npy",power_data)
np.save("data/processed_triggers.npy",trigs)

ax[2].set_xlabel("time (ns)")
plt.show()
