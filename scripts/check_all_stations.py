import numpy as np
import matplotlib.pyplot as plt
import os
import json
from NuRadioReco.detector.detector import Detector
from NuRadioReco.detector.RNO_G import rnog_detector
import datetime as dt
from scipy.signal import savgol_filter

db_det=rnog_detector.Detector(
    detector_file=None
    )
db_det.update(dt.datetime(2025,5,2))


stations=[24,23,22,21,14,13,12,11]

channels=[0,1,2,3]
beams=[0,1,2,3,4,5,6,7,8,9,10,11]
version="didaq_v0"
make_plots=True
print_for_quartus=True
save_beams=True
print_for_python=True
c=2.99792458e8
n=1.75
sampling_rate=1e9
int_factor=1
int_rate=sampling_rate*int_factor
num_antennas=4
file='data/RNO_season_2024.json'
det=Detector(file,source="json")

det.update(dt.datetime.now())
#det=db_det
f=np.linspace(.06,.236,10000)
phase_delays={}
print("relative group delays")
for station in stations:

    #if station==14:
    #    db_det.update(dt.datetime(2025,5,5))
    #else:
    #    db_det.update(dt.datetime(2023,8,3))

    plt.figure()
    plt.title(f"station {station}")

    f = np.linspace(.06,.236,10000)
    dts = []
    try:
        rel = db_det.get_signal_chain_response(station,0,trigger=True)(f)
    except:
        print(f"{station} not in db det for group delays")
        phase_delays[station] = dict(zip(channels,np.zeros(4)))
        continue

    for i in range(0,4):

        fmin=.15
        fmax=.2

        fs = np.linspace(.9*fmin, 1.1*fmax, 1000)
        response = db_det.get_signal_chain_response(station, i, trigger=True)(fs)
  
        phase_angle = np.angle(response)
        unwrapped = np.unwrap(phase_angle)
        group_delays = -np.gradient(unwrapped) / (2 * np.pi * np.gradient(fs))
        avg_delay = np.mean( group_delays[np.logical_and(fs>fmin, fs<fmax)] )
        dts.append(avg_delay)


        fig,ax=plt.subplots(3,1,sharex=True,figsize=(6,8))
        ax[0].plot(fs,phase_angle,label="angle")
        ax[0].set_ylabel("phase angle [rad]")
        ax[1].plot(fs,unwrapped,label="unwrapped angle")
        #ax[1].plot(f,smooth,label="smoothed angle")
        ax[1].set_ylabel("phase angle [rad]")
        ax[1].legend()
        ax[2].plot(fs,group_delays,label="group delay")
        #ax[2].plot(fs,smoothed_del,label="smoothed group delay")
        ax[2].set_xlabel("freq [GHz]")
        ax[2].set_ylabel("group delay [ns]")
        ax[2].legend()
        fig.suptitle(f"Station {station} Channels 0-{i}")
        plt.close()
        #plt.show()

    plt.ylabel("Relative Group Delay [ns]")
    plt.xlabel("Freq. [MHz]")
    plt.ylim([-5,5])
    plt.text(75,-4,f"Rel. to CH0 @ 200MHz {np.round(dts,decimals=3)} ns",fontsize=10)
    plt.legend()
    plt.close()
    #plt.savefig(f"plots/group_delay_station_{station}.png")
    plt.close()
    #plt.show()

    print(station, dts)
    dts=np.array(dts)

    phase_delays[station]=dict(zip(channels,dts))

print(phase_delays)
f=open(f"data/{version}_rel_group_delays.json","w")
json.dump(phase_delays,f,indent=4)

all_delays=np.zeros((len(stations),len(channels)))
all_depths=np.zeros((len(stations),len(channels)))
num_beams=12

for i in range(len(stations)):

    for j in range(len(channels)):
        
        if version=="v0p16":
            all_delays[i,j]=det.get_channel(stations[-i-1],channels[j])['cab_time_delay']
            all_depths[i,j]=det.get_channel(stations[-i-1],channels[j])['ant_position_z'] 

        if version=="v0p17":
            all_delays[i,j]=det.get_channel(stations[i],channels[j])['cab_time_delay']
            all_depths[i,j]=det.get_channel(stations[i],channels[j])['ant_position_z']  

        if version=="v0p18" or version=="didaq_v0":
            #if stations[i]==14:
            #    db_det.update(dt.datetime(2024,2,2))
            #else:
            #    db_det.update(dt.datetime(2023,8,3))

            try:
                #database first
                all_delays[i,j]=db_det.get_cable_delay(stations[i],channels[j],trigger=True) + phase_delays[stations[i]][j]
                all_depths[i,j]=db_det.get_relative_position(stations[i],channels[j])[2]

            except:
                print("db failed")
                try:
                    #in case there's a calibrated file
                    all_delays[i,j]=db_det.get_channel(stations[i],channels[j])['cab_time_delay'] + phase_delays[stations[i]][j] 
                    all_depths[i,j]=db_det.get_channel(stations[i],channels[j])['ant_position_z']

                except:
                    #fallback 2024 json
                    all_delays[i,j]=det.get_channel(stations[i],channels[j])['cab_time_delay']
                    all_depths[i,j]=det.get_channel(stations[i],channels[j])['ant_position_z'] 

all_lookbacks=np.zeros((len(stations),4,num_beams))

q_file = open(f"data/{version}_quartus_delays.txt","w")

print(f"delays for {version}")
print("stations",stations[::1])
print(all_delays)
print(all_depths)
for i_stat,station in enumerate(stations[::1]):
    cable_delays=all_delays[i_stat]
    ant_depths=all_depths[i_stat]

    def get_delay(ant_top=0,ant_num=0,angle=0):
        #return (ant_depths[ant_top]-ant_depths[ant_num])*np.sin(angle*np.pi/180)*n/c+(cable_delays[ant_num]-cable_delays[ant_top])/1e9
        return (ant_depths[ant_top]-ant_depths[ant_num])*np.sin(angle*np.pi/180)*n/c-(cable_delays[ant_num])/1e9


    angs=np.linspace(-80,80,160*8)
    delays=np.zeros((4,len(angs)))
    lookback=np.zeros((4,len(angs)))

    delays[0]=get_delay(3,0,angs)
    delays[1]=get_delay(3,1,angs)
    delays[2]=get_delay(3,2,angs)
    delays[3]=get_delay(3,3,angs)

    for i in range(4):
        lookback[i]=-(delays[i]-np.max(delays.T,axis=1))

    beam_locs=np.linspace(np.sin(60*np.pi/180),np.sin(-60*np.pi/180),num_beams)
    beam_locs=np.arcsin(beam_locs)*180/np.pi

    beam_lookback=np.zeros((4,num_beams))

    beam_lookback[0]=get_delay(3,0,beam_locs)
    beam_lookback[1]=get_delay(3,1,beam_locs)
    beam_lookback[2]=get_delay(3,2,beam_locs)
    beam_lookback[3]=get_delay(3,3,beam_locs)
    #print(beam_lookback)
    temp = beam_lookback.T
    for i in range(12):
        temp[i] = (temp[i] - np.min(temp[i]))

    #print(temp)
    beam_lookback = np.round(temp.T*int_rate)


    #print(beam_lookback[0])
    #print(beam_lookback[1])
    #print(beam_lookback[2])
    #print(beam_lookback[3])

    #beam_lookback[0] = -(beam_lookback[0].T-np.max(beam_lookback[0].T)).T
    #beam_lookback[1] = -(beam_lookback[1].T-np.max(beam_lookback[1].T)).T
    #beam_lookback[2] = -(beam_lookback[2].T-np.max(beam_lookback[2].T)).T
    #beam_lookback[3] = -(beam_lookback[3].T-np.max(beam_lookback[3].T)).T


    #beam_lookback[0]=np.rint(np.interp(beam_locs,angs,lookback[0]*int_rate))
    #beam_lookback[1]=np.rint(np.interp(beam_locs,angs,lookback[1]*int_rate))
    #beam_lookback[2]=np.rint(np.interp(beam_locs,angs,lookback[2]*int_rate))
    #beam_lookback[3]=np.rint(np.interp(beam_locs,angs,lookback[3]*int_rate))

    if make_plots:
        if not os.path.exists('plots'): os.mkdir('plots')
        plt.figure()
        plt.plot(angs,delays[0],label='ch03')
        plt.plot(angs,delays[1],label='ch13')
        plt.plot(angs,delays[2],label='ch23')
        plt.plot(angs,delays[3],label='ch33')

        plt.xlabel('angles (deg)')
        plt.ylabel('delays (s)')
        plt.legend()
        plt.savefig(f'plots/{version}/{station}_arrival_times.png')
        plt.close()

        plt.figure()
        plt.plot(angs,lookback[0],label='ch03')
        plt.plot(angs,lookback[1],label='ch13')
        plt.plot(angs,lookback[2],label='ch23')
        plt.plot(angs,lookback[3],label='ch33')

        plt.xlabel('angles (deg)')
        plt.ylabel('lookback (s)')
        plt.legend()
        plt.savefig(f'plots/{version}/{station}_lookback_times.png')
        plt.close()

        plt.figure()
        plt.plot(angs,lookback[0]*int_rate,label='ch0')
        plt.plot(angs,lookback[1]*int_rate,label='ch1')
        plt.plot(angs,lookback[2]*int_rate,label='ch2')
        plt.plot(angs,lookback[3]*int_rate,label='ch3') #*int_rare
        plt.hlines([0,1,2,3,4,5],-80,80,linestyle="dashed")
        plt.xlabel('angles (deg)')
        plt.ylabel('lookback (samples)')
        plt.legend()
        #plt.show()
        plt.savefig(f'plots/{version}/{station}_lookback_interpolated_samples.png')
        plt.close()

        plt.figure()
        plt.scatter(beam_locs,beam_lookback[0],label='ch0')
        plt.scatter(beam_locs,beam_lookback[1],label='ch1')
        plt.scatter(beam_locs,beam_lookback[2],label='ch2')
        plt.scatter(beam_locs,beam_lookback[3],label='ch3')

        plt.xlabel('angles (deg)')
        plt.ylabel('lookback (int samples)')
        plt.legend()
        plt.savefig(f'plots/{version}/{station}_beam_lookback_samples.png')
        plt.close()

    if print_for_quartus:
        #print('print out for quartus for station %s'%station)
        #print(station)
        if station==stations[0]:
            print(f'{station} ((',end='')
        else:
            print(f'{station} (',end='')

        for i in range(num_beams):
            print('(%i,%i,%i,%i)'%(beam_lookback[3][i],beam_lookback[2][i],beam_lookback[1][i],beam_lookback[0][i]),end='')
            if i==num_beams-1:
                break
            #if i==6: print()
            print(',',end='')
        if station==stations[-1]:
            print('));',end='\n')
        else:
            print('),',end='\n')

        if save_beams:
            if station==stations[0]:
                print(f'((',end='',file=q_file)
            else:
                print(f'(',end='',file=q_file)
            for i in range(num_beams):
                print('(%i,%i,%i,%i)'%(beam_lookback[3][i],beam_lookback[2][i],beam_lookback[1][i],beam_lookback[0][i]),end='',file=q_file)
                if i==num_beams-1:
                    break
                #if i==6: print()
                print(',',end='',file=q_file)
            if station==stations[-1]:
                print('));',end='',file=q_file)
            else:
                print('),',end='',file=q_file)

            print(f'--station {station}',end='\n',file=q_file)
            


    all_lookbacks[i_stat]=beam_lookback
form_delays={}
if print_for_python:
    dels = {}
    for i in range(len(stations)):
        #print(stations[i],all_lookbacks[i].T)
        dels[stations[i]] = all_lookbacks[i].T

        sub_form={}
        for j in beams:
            sub_form[f"bm_{j}"]=dict(zip([f"ch_{x}" for x in channels],all_lookbacks[i].T[-j-1]))
        #print(sub_form)
        form_delays[f"st_{stations[i]}"] = sub_form

    #print(dels)
    #np.save("delays_for_sims.npy",dels,allow_pickle=True)
#np.save("json.npy",all_lookbacks)
#print(form_delays)

if save_beams:
    f=open(f"data/{version}_lookbacks.json","w")
    json.dump(form_delays,f,indent=4)


for i in range(num_beams):
    break
    plt.figure()
    plt.scatter(np.linspace(0,.8,len(all_lookbacks[:,0,i])),all_lookbacks[:,0,i]-round(np.mean(all_lookbacks[:,0,i])))
    plt.scatter(1+np.linspace(0,.8,len(all_lookbacks[:,0,i])),all_lookbacks[:,1,i]-round(np.mean(all_lookbacks[:,1,i])))
    plt.scatter(2+np.linspace(0,.8,len(all_lookbacks[:,0,i])),all_lookbacks[:,2,i]-round(np.mean(all_lookbacks[:,2,i])))
    plt.scatter(3+np.linspace(0,.8,len(all_lookbacks[:,0,i])),all_lookbacks[:,3,i]-round(np.mean(all_lookbacks[:,3,i])))
    plt.xlabel('channel')
    plt.ylabel('beam %i sample delay from mean delay'%i)
    plt.xticks([0,1,2,3])
    plt.savefig('plots/station_rel_delays_beam%i.png'%i)
    plt.close()

fig,ax=plt.subplots(num_beams,1,figsize=(8,10),sharex=True)
fig.subplots_adjust(hspace=0)
for i in range(num_beams):

    ax[i].scatter(np.linspace(0,.8,len(all_lookbacks[:,0,i])),all_lookbacks[:,0,i]-np.min(all_lookbacks[:,0,i]))
    ax[i].scatter(1+np.linspace(0,.8,len(all_lookbacks[:,0,i])),all_lookbacks[:,1,i]-np.min(all_lookbacks[:,1,i]))
    ax[i].scatter(2+np.linspace(0,.8,len(all_lookbacks[:,0,i])),all_lookbacks[:,2,i]-np.min(all_lookbacks[:,2,i]))
    ax[i].scatter(3+np.linspace(0,.8,len(all_lookbacks[:,0,i])),all_lookbacks[:,3,i]-np.min(all_lookbacks[:,3,i]))
    ax[i].set_ylabel('Beam %i'%i,fontsize=10)
    ax[i].set_xticks([0,1,2,3,4])
    ax[i].set_yticks([0,1,2,3,4])
    ax[i].set_ylim(bottom=0,top=4)
    ax[i].tick_params(axis='y', which='major', labelsize=8)


fig.suptitle(f"Relative beam delays between {stations}")
ax[num_beams-1].set_xlabel('channel')
fig.tight_layout()
plt.savefig(f'plots/{version}/all_beams.png')
#plt.show()
plt.close()


for i in range(num_beams):
    plt.figure()
    plt.scatter(0*np.ones(len(all_lookbacks[:,0,i])),all_lookbacks[:,0,i])
    plt.scatter(1*np.ones(len(all_lookbacks[:,1,i])),all_lookbacks[:,1,i])
    plt.scatter(2*np.ones(len(all_lookbacks[:,2,i])),all_lookbacks[:,2,i])
    plt.scatter(3*np.ones(len(all_lookbacks[:,3,i])),all_lookbacks[:,3,i])
    plt.xlabel('channel')
    plt.ylabel('beam %i sample delay'%i)
    plt.savefig(f'plots/{version}/station_delays_beam{i}.png')
    plt.close()

