import numpy as np

#nuradiomc dah dah dah

ch_data = np.zeros((4,2048), dtype=int) + 128
#ch0_data=np.zeros(1024,dtype=int)+128
#ch1_data=np.zeros(1024,dtype=int)+128
#ch2_data=np.zeros(1024,dtype=int)+128
#ch3_data=np.zeros(1024,dtype=int)+128

ch_data[0,80]=128+32
ch_data[0,81]=128-32

ch_data[1,80]=128+32
ch_data[1,81]=128-32

if False:
    ch0_data=np.loadtxt("data/ch0_test_trace.txt")+128
    ch1_data=np.loadtxt("data/ch1_test_trace.txt")+128
    ch2_data=np.loadtxt("data/ch2_test_trace.txt")+128
    ch3_data=np.loadtxt("data/ch3_test_trace.txt")+128

    ch0_data=np.pad(ch0_data,pad_width=(0,1024-len(ch0_data)),constant_values=128).astype(int)
    ch1_data=np.pad(ch1_data,pad_width=(0,1024-len(ch1_data)),constant_values=128).astype(int)
    ch2_data=np.pad(ch2_data,pad_width=(0,1024-len(ch2_data)),constant_values=128).astype(int)
    ch3_data=np.pad(ch3_data,pad_width=(0,1024-len(ch3_data)),constant_values=128).astype(int)


print(len(ch_data))

ch_cond=ch_data.reshape((4,512,4))
#ch0_cond=ch0_data.reshape((256,4))
#ch1_cond=ch1_data.reshape((256,4))
#ch2_cond=ch2_data.reshape((256,4))
#ch3_cond=ch3_data.reshape((256,4))

ch_vals=np.zeros((4,512),dtype=int)
#ch0_vals=np.zeros(256,dtype=int)
#ch1_vals=np.zeros(256,dtype=int)
#ch2_vals=np.zeros(256,dtype=int)
#ch3_vals=np.zeros(256,dtype=int)

#order gets flipped going into vhdl modules... here is [0, 1, 2, ..., 30, 31] but in fpga land its [31,30,...,2,1,0]
for ch in range(4):
    for i in range(512):
        ch_vals[ch,i]=(ch_cond[ch][i][3])+(ch_cond[ch][i][2]<<8)+(ch_cond[ch][i][1]<<16)+(ch_cond[ch][i][0]<<24)

#for i in range(256):
#    ch0_vals[i]=(ch0_cond[i][3])+(ch0_cond[i][2]<<8)+(ch0_cond[i][1]<<16)+(ch0_cond[i][0]<<24)
#    ch1_vals[i]=(ch1_cond[i][3])+(ch1_cond[i][2]<<8)+(ch1_cond[i][1]<<16)+(ch1_cond[i][0]<<24)
#    ch2_vals[i]=(ch2_cond[i][3])+(ch2_cond[i][2]<<8)+(ch2_cond[i][1]<<16)+(ch2_cond[i][0]<<24)
#    ch3_vals[i]=(ch3_cond[i][3])+(ch3_cond[i][2]<<8)+(ch3_cond[i][1]<<16)+(ch3_cond[i][0]<<24)

#print((ch0_vals[0]&0xff))

f=open("data/input_pa_waveforms.txt",mode="w")
for i in range(512):

    save_string=f""

    for ch in range(4):
        save_string+=f"{ch_vals[ch][i]:032b} "
    if i!=512-1:
        save_string+=f"\n"
    
    f.write(save_string)

    #if i==256-1:
    #    f.write(f"{ch0_vals[i]:032b} {ch1_vals[i]:032b} {ch2_vals[i]:032b} {ch3_vals[i]:032b}")
    #else:
    #    f.write(f"{ch0_vals[i]:032b} {ch1_vals[i]:032b} {ch2_vals[i]:032b} {ch3_vals[i]:032b}\n")
f.close()

#for easier plotting
np.savetxt("data/processed_input_pa_waveforms.txt",(ch_data),fmt="%i")

#np.savetxt("data/processed_input_waveforms.txt",(ch0_data-128,ch1_data-128,ch2_data-128,ch3_data-128))
