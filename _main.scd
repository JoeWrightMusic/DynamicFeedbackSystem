/**
This script exemplifies the use of SuperCollider on Bela.
When a project contains a `_main.scd` file, `sclang` is started
and the content of the file is executed.
If you want to interact with SuperCollider running on the board
from within the SuperCollider IDE on your computer, check out
the 12-SuperCollider/remote examples instead.
Those files also include more code examples to interface with
Bela-specific UGens.
 */
s = Server.default;

s.options.numAnalogInChannels = 8;
s.options.numAnalogOutChannels = 8;
s.options.numDigitalChannels = 16;

s.options.blockSize = 16;
s.options.numInputBusChannels = 2;
s.options.numOutputBusChannels = 2;

s.options.postln;

s.waitForBoot({
//______________________________________________________________VARIABLES
	var
	filters,
	sig_chain,
	filt_state,
	freq_count,
	freq_state,
	fVol,
	rate,
	window,
	preMix,
	mixSig,
	in,
	out,
	player,
	which=0,
	output1=0,
	pzo
	;
//______________________________________________________________SET UP FILTERS
	//Number of filters to create
	n=10;
	//create arrays, busses + groups
	filters = Array.fill(n, 0);
	sig_chain = Array.fill(n+1, 0);
	filt_state = Array.fill(n, 0);
	freq_count = Array.fill(132, 0);
	freq_state = Array.fill(132, 0);
	fVol = Bus.control(s, 1);
	rate = Bus.control(s, 1);
	window = Bus.control(s,1);

	(n+1).do({//create n+1 busses
		arg i;
		sig_chain[i]=Bus.audio(s, 1);
	});
	
	mixSig = Bus.audio(s,1);
	preMix = Group.new;
	in = Group.after(preMix);
	n.do({//create n filter groups
		arg i;
		case
		{i==0}{filters[i]=Group.after(in)}
		{i>0}{filters[i]=Group.after(filters[i-1])};
	});
	out=Group.after(filters[n-1]);
	"Set Up Done".postln;
	//______________________________________________________________SYNTHDEFS
	SynthDef(\preMix, {
		var sig; 
		// sig = AnalogIn.ar(6).clip(0.001, 0.999).linlin(0.001, 0.999, -1, 1);
		// sig = XFade2.ar(SoundIn.ar(1), SoundIn.ar(1), sig);
		sig=SoundIn.ar(0);
		Out.ar(mixSig, sig);
	}).add;
	
	SynthDef(\piezo, {
		arg in, out;
		var sig, mult, lp, hp, filt, filtComp;
		sig = In.ar(in);
		mult = AnalogIn.ar(2).linexp(0.001, 0.85, 0.001, 4000);
		filt = AnalogIn.ar(1);
		filtComp = InRange.kr(filt,0.25,1)+InRange.kr(filt,0.9,1);
		filtComp = Select.kr(filtComp, [
				filt.linexp(0,0.25,400,1),
				1,
				filt.linexp(0.85,1,1,25)
			]);
		lp = filt.clip(0.01,0.48).linexp(0.01,0.48, 20, 22000);
		hp = filt.clip(0.52, 0.98).linexp(0.52, 0.98, 5, 15000);
		sig = sig*mult*filtComp;
		sig = HPF.ar(sig, hp);
		sig = LPF.ar(sig, lp);
		//get piezo sound
		Out.ar(out, sig);
	}).add;

	SynthDef(\listen, {//pitch tracking + decrease timer
		arg in, id1, id2, rate;
		var vol, sig, freq, hasFreq, trig, trig2, decreaseMod=0;
		decreaseMod=AnalogIn.kr(0);
		sig = In.ar(in)*decreaseMod;
		#freq, hasFreq = Pitch.kr(
			sig,
			minFreq: 50,
			maxFreq: 22000,
			execFreq: 50,
			median: 5,
			ampThreshold: 0.01,
			peakThreshold: 0.5,
			clar: 1
		);	
		decreaseMod=InRange.kr(decreaseMod, 0, 0.01);
		trig = InRange.kr(hasFreq, 0.4, 1);
		trig = Impulse.kr(10)*trig;
		trig2 = Impulse.kr(0.0001+decreaseMod*10);
		SendTrig.kr(trig, id1, freq);
		SendTrig.kr(trig2, id2, 2);
	}).add;

	SynthDef(\rate, {
		arg id=0003;
		var rt;
		rt = AnalogIn.kr(3).clip(0.01, 0.99);
		Out.kr(rate, rt);
	}).add;
	
	SynthDef(\win, {
		arg id=0004;
		var wn;
		wn = AnalogIn.kr(5).clip(0.01, 0.99);
		Out.kr(window, wn);
	}).add;

	SynthDef(\thru, {//pass signal through group when filter is inactive
		arg in, out, off=1, fade=0.02;
		var sig, env;
		sig = In.ar(in);
		env = EnvGen.kr(Env.asr(fade, 1, fade), off);
		Out.ar(out, sig*env;);
	}).add;

	SynthDef(\filt, {//filter out frequency from signal chain
		arg in, out, off=1, fade=0.02, freq=440, rq;
		var sig, env;
		off = 1-off;
		env = EnvGen.kr(Env.asr(fade, 1, fade), off, doneAction:2);
		sig = In.ar(in);
		rq = AnalogIn.ar(4).clip(0.001,0.999).linexp(0.001, 0.999, 5, 0.1);
		sig = BRF.ar(sig, freq, 1);//make Q a control!!! low values are interesting!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		Out.ar(out, sig*env);
	}).add;

	SynthDef(\out, {//output audio after filters
		arg in, in_vol, out_ch;
		var sig, vol;
		vol = AnalogIn.ar(0).clip(0.001, 0.999).linlin(0.001,0.999,0.001,1.001)-0.001;
		vol = vol.clip(0,1);
		vol = Lag.ar(vol, 0.2);
		sig = In.ar(in);
		sig = sig*vol;
		Out.ar(out_ch, sig);
	}).add;
	"SynthDefs Done".postln;
	//______________________________________________________________TASKS
	//Cues in filter for time seconds
	player = {
		arg which, freq, time, win=0, pause;
		Task{
			win=time*win;//possibly add control!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			freq_state[freq.cpsmidi.round(1)]=1;
			filt_state[which]=1;
			Synth(\filt, [\in, sig_chain[which], \out, sig_chain[which+1], \freq, freq, \fade, win], target: filters[which]);
			filters[which].set(\off, 0);
			(time-(2*win)).clip(0.001,30).wait;
			filters[which].set(\off, 1);
			win.wait;
			filt_state[which]=0;
			freq_state[freq.cpsmidi.round(1)]=0;
		}.play;
	};
	"Player Ready".postln;
	//______________________________________________________________OSCDEFS
	//Manage messages from pitch tracker and cue in filters with player
	OSCdef(\filt_manager, {
		arg msg, time, addr, recvPort, index;
		var choice, freq, ti, rt, wn;
		rt = rate.getSynchronous;
		wn = window.getSynchronous;
		//only cue filter if rate >0.05
		if(rt>0.05,{
			if(msg[2]==1, {
				case
				//if filter not active
				{freq_state[msg[3].cpsmidi.round(1)]==0}
				{
						which = (which+1)%n;
						case
						{filt_state[which]==0}
						{
							freq = msg[3];
							ti = freq.cpsmidi.round(1);
							ti = freq_count[ti];
							rt = (pow(ti,2)*rt.clip(0.02,0.98).linexp(0.02,0.98,0.001,2)).clip(0,30);
							ti = 0.005+rt;
							wn=wn.linlin(0.01, 0.99,0.49,0);
							player.value(which, freq, ti, wn);
							ti = freq.cpsmidi.round(1);
							freq_count[ti]=freq_count[ti]+1;
						}
						{filt_state[which]==1}
						{
							"No More Filters!".postln;
						};
				}
				// if filter active, increase count only
				{freq_state[msg[3].cpsmidi.round(1)]==1}
				{
					freq = msg[3];
					ti = freq.cpsmidi.round(1);
					freq_count[ti]=freq_count[ti]+0.01;
				}
			});
		});
		//decrease filter count
		if(msg[2]==2, {
			for(0, 131, {
				arg i;
				freq_count[i]=(freq_count[i]-1).clip(0, 10000000000000);
			});
			// freq_count.postln;
		});
	},  '\tr', Server.local.addr);
	"OSCdef Done".postln;
	//______________________________________________________________START
	Task{
		3.wait;
		Synth(\rate, [\id, 0003], in);
		Synth(\win, [\id, 0004], in);
		Synth(\preMix, target: preMix);
		pzo=Synth(\piezo, [ \in, mixSig, \in2, 1, \out, sig_chain[0]], in);
		Synth(\listen, [\in, mixSig, \id1, 0001, \id2, 0002], filters[0]);
		n.do({
			arg i;
			Synth(\thru, [\in, sig_chain[i], \out, sig_chain[i+1]], filters[i]);
		});
		Synth(\out, [\in, sig_chain[n], \in_vol, fVol, \out_ch, output1], out);
		"PLAYING".postln;
		3.wait;
		in.set(\gain, 1, \vol, 1, \lp, 20000, \hp, 5);
		fVol.set(1);
	}.play;
});
