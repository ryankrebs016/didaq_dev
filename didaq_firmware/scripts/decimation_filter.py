import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import firwin

filt=firwin(31, .25, fs=1, pass_zero=True)
filt=np.rint(filt*256)

print(filt)
filt=filt/256
f=np.fft.fftfreq(31,d=1)
fft=np.fft.fft(filt)

f=f[0:len(f)//2]
fft=fft[0:len(fft)//2]

fig,ax = plt.subplots(2,1)
ax[0].plot(filt)
ax[1].plot(f,20*np.log10(np.abs(fft)))
#ax[1].set_yscale("log")
plt.show()