(
// =====================================================
// BREAKBEAT IDM SLICER - GUI + WAVEFORM + PARAMS + AUDIO (v4.2 QUANT)
// =====================================================

~idmGuardToken = ~idmGuardToken ? 0;
~idm = ~idm ? IdentityDictionary.new;

~idmReset = {
	var w;
	~idmGuardToken = (~idmGuardToken ? 0) + 1;

	if(~idm.notNil and: { ~idm[\pat].notNil }) {
		try { ~idm[\pat].stop } { };
		~idm[\pat] = nil;
	};

	if(~idm.notNil and: { ~idm[\clock].notNil }) {
		try { ~idm[\clock].stop } { };
		~idm[\clock] = nil;
	};

	if(~idm.notNil and: { ~idm[\loadRoutine].notNil }) {
		if(~idm[\loadRoutine] !== thisThread) { try { ~idm[\loadRoutine].stop } { } };
		~idm[\loadRoutine] = nil;
	};

	if(~idm.notNil and: { ~idm[\guiUpdateTask].notNil }) {
		try { ~idm[\guiUpdateTask].stop } { };
		~idm[\guiUpdateTask] = nil;
	};

	if(~idm.notNil and: { ~idm[\waveFile].notNil }) {
		try { ~idm[\waveFile].close } { };
		~idm[\waveFile] = nil;
	};

	if(~idm.notNil and: { ~idm[\win].notNil }) {
		w = ~idm[\win];
		try { w.close } { };
		~idm[\win] = nil;
	};

	OSCdef(\idm_cellfeat).free;
	MIDIdef.cc(\__learnOnce).free;

	if(~idm.notNil and: { ~idm[\ccMaps].notNil }) {
		~idm[\ccMaps].keysValuesDo { |k, v|
			MIDIdef.cc(("cc_" ++ k).asSymbol).free;
		};
	};

	if(~idm.notNil and: { ~idm[\oscMaps].notNil }) {
		~idm[\oscMaps].keysValuesDo { |k, v|
			OSCdef(("osc_" ++ k).asSymbol).free;
		};
	};

	if(~idm.notNil and: { ~idm[\buf].notNil }) {
		try { ~idm[\buf].free } { };
		~idm[\buf] = nil;
	};

	if(~idm.notNil) {
		~idm[\playerRunning] = false;
	};

	"IDM: reset done.".postln;
};

if(~idm.notNil and: { ~idm[\initialized] == true }) {
	try { ~idmReset.value } { };
};

~idm = IdentityDictionary.new;

s.options.numInputBusChannels = 0;
if((ServerOptions.devices ? []).includes("MacBook Air Speakers")) {
	s.options.outDevice = "MacBook Air Speakers";
};
if(s.serverRunning.not) { s.boot; };

s.doWhenBooted({

	~idm[\initialized] = true;

	// =====================================================
	// ENGINE CONFIG
	// =====================================================
	s.latency = 0.2;
	~idm[\mode] = \sync;

	~idm[\appDo] = { |func|
		if(thisThread.clock == AppClock) {
			try { func.value } { |error| error.reportError };
		} {
			AppClock.sched(0, {
				try { func.value } { |error| error.reportError };
				nil
			});
		};
	};

	~idm[\status] = { |str|
		("[IDM] " ++ (str ? "")).postln;
		if(~idm[\statusText].notNil) {
			~idm[\appDo].value({
				~idm[\statusText].string = "Status: " ++ (str ? "");
			});
		};
	};

	~idm[\setStatus] = ~idm[\status];

	~idm[\setBpmStatus] = { |bpm|
		("[IDM] BPM: " ++ bpm).postln;
		if(~idm[\bpmText].notNil) {
			~idm[\appDo].value({
				~idm[\bpmText].string = "BPM: " ++ bpm.asString;
			});
		};
	};

	// =====================================================
	// STATE
	// =====================================================
	~idm[\buf] = nil;
	~idm[\sr] = s.sampleRate;
	~idm[\fileSR] = s.sampleRate;
	~idm[\hop] = 512;

	~idm[\minBpm] = 140;
	~idm[\maxBpm] = 175;

	~idm[\bpm] = nil;
	~idm[\clock] = nil;
	~idm[\pat] = nil;

	~idm[\playerRunning] = false;

	~idm[\forceHits] = false;

	~idm[\cells] = nil;
	~idm[\onsetOffsets] = nil;
	~idm[\onsetPeaks] = nil;
	~idm[\sourceMono] = nil;
	~idm[\sourceFrames] = nil;

	~idm[\ready] = false;
	~idm[\serverBufReady] = false;
	~idm[\readyForCommands] = false;
	~idm[\isLoading] = false;
	~idm[\loadRoutine] = nil;

	~idm[\currentSlice] = 0;
	~idm[\currentStep] = 0;
	~idm[\loadedPath] = nil;
	~idm[\waveFile] = nil;
	~idm[\overlayDirty] = true;
	~idm[\overlayRefreshPending] = false;
	~idm[\overlayCache] = nil;
	~idm[\lastFreeIdx] = nil;
	~idm[\selectedSlice] = 0;
	~idm[\selectedFrame] = 0;
	~idm[\selectedEvent] = 0;

	~idm[\seed] = 12345;
	~idm[\frozen] = false;
	~idm[\frozenPattern] = nil;
	~idm[\patternBars] = 4;
	~idm[\patternVersion] = 0;
	~idm[\timelineDirty] = true;

	~idm[\bpmOverride] = nil;
	~idm[\onsetSensitivity] = 0.15;
	~idm[\minSliceBeats] = 0.25;
	~idm[\disabledSlices] = IdentityDictionary.new;
	~idm[\sliceEditVersion] = 0;

	~idm[\macroLocks] = IdentityDictionary.new;
	~idm[\macroAB] = nil;
	~idm[\sessionPath] = Platform.userHomeDir +/+ "Desktop/idm_session.scdarchive";

	// ---------------- QUANTIZATION STATE
	~idm[\quant] = IdentityDictionary[
		\enabled   -> true,
		\mode      -> \nearest,   // \nearest | \forward | \backward
		\gridDiv   -> 16,         // 8 | 16 | 32
		\keepOrder -> true,
		\swing     -> 0.0         // 0..0.95
	];

	~idm[\quantGridTimes] = nil;   // absolute beat times of grid points
	~idm[\quantSeqIdxs] = nil;     // one slice index or nil per quant step
	~idm[\quantSeqDurs] = nil;     // duration in beats per quant step
	~idm[\quantSeqBeats] = nil;    // grid start beat for each quant step
	~idm[\quantSummary] = "";

	// =====================================================
	// PATH UTILS
	// =====================================================
	~idm[\normalizePath] = { |p|
		if(p.isNil) { nil } {
			p = p.asString.stripWhiteSpace;
			p = p.replace("\n", "").replace("\r", "").replace("\"", "");
			if(p.beginsWith("file://localhost")) { p = p.replace("file://localhost", ""); };
			if(p.beginsWith("file://")) { p = p.copyRange(7, p.size - 1); };
			p = p.replace("%20", " ");
			if(p.size <= 1 or: { p == "/" }) {
				nil
			} {
				if(p.beginsWith("/").not) { p = "/" ++ p };
				p
			};
		};
	};

	~idm[\lastPathFile] = Platform.userHomeDir +/+ ".sc_idm_lastpath.txt";

	~idm[\saveLastPath] = { |p|
		var f;
		if(p.isNil) {
			nil
		} {
			f = File(~idm[\lastPathFile], "w");
			if(f.isOpen) {
				f.write(p.asString);
				f.close;
			};
			p
		};
	};

	~idm[\loadLastPath] = {
		var f, txt;
		f = File(~idm[\lastPathFile], "r");
		if(f.isOpen.not) {
			nil
		} {
			txt = f.readAllString;
			f.close;
			txt = txt.notNil.if({ txt.stripWhiteSpace }, { nil });
			txt
		}
	};

	~idm[\chooseFile] = {
		var startPath;
		startPath = ~idm[\loadedPath] ? (Platform.userHomeDir +/+ "Desktop");

		Dialog.openPanel(
			{ |path|
				if(path.notNil) {
					path = ~idm[\normalizePath].value(path);
					~idm[\appDo].value({
						if(~idm[\pathField].notNil) {
							~idm[\pathField].string = path;
						};
					});
					~idm[\load].value(path);
				};
			},
			startPath
		);
	};

	~idm[\modeFromInput] = { |mode|
		var m;
		m = (mode ? \sync).asSymbol;
		if((m == \free) or: { m == \chaos }) {
			\free
		} {
			\sync
		}
	};

	~idm[\modeIndex] = { |mode|
		(~idm[\modeFromInput].value(mode) == \sync).if(0, 1)
	};

	~idm[\modeFromIndex] = { |index|
		(index == 0).if(\sync, \free)
	};

	~idm[\analysisYield] = {
		nil
	};

	// =====================================================
	// MACROS
	// =====================================================
	~idm[\macros] = IdentityDictionary[
		\density   -> 0.62,
		\fill      -> 0.38,
		\ghost     -> 0.26,
		\tight     -> 0.74,
		\swing     -> 0.14,
		\glitch    -> 0.62,
		\burst     -> 0.38,
		\repeats   -> 0.55,
		\chaos     -> 0.25,

		\ratespread -> 0.22,
		\reverse    -> 0.14,
		\panwidth   -> 0.55,
		\env        -> 0.22,
		\humanize   -> 0.22,

		\filter     -> 0.0,
		\res        -> 0.0,
		\drive      -> 0.0,
		\crush      -> 0.0,
		\comb       -> 0.0,
		\delay      -> 0.0
	];

	~idm[\macroSpec] = IdentityDictionary[
		\density   -> [0.0, 1.0],
		\fill      -> [0.0, 1.0],
		\ghost     -> [0.0, 1.0],
		\tight     -> [0.0, 1.0],
		\swing     -> [0.0, 1.0],
		\glitch    -> [0.0, 1.0],
		\burst     -> [0.0, 1.0],
		\repeats   -> [0.0, 1.0],
		\chaos     -> [0.0, 1.0],

		\ratespread -> [0.0, 1.0],
		\reverse    -> [0.0, 1.0],
		\panwidth   -> [0.0, 1.0],
		\env        -> [0.0, 1.0],
		\humanize   -> [0.0, 1.0],

		\filter     -> [0.0, 1.0],
		\res        -> [0.0, 1.0],
		\drive      -> [0.0, 1.0],
		\crush      -> [0.0, 1.0],
		\comb       -> [0.0, 1.0],
		\delay      -> [0.0, 1.0]
	];

	~idm[\macroOrder] = [
		\burst,
		\glitch,
		\ghost,
		\repeats,
		\density,
		\panwidth,
		\reverse,
		\ratespread,
		\tight,
		\swing,
		\fill,
		\chaos,
		\env,
		\humanize,
		\filter,
		\res,
		\drive,
		\crush,
		\comb,
		\delay
	];

	~idm[\presetNames] = [
		"Tight Sync Chop",
		"Subtle Jungle",
		"IDM Scatter",
		"Breakcore Burst",
		"Sparse Glitch",
		"Reverse Shuffle",
		"Micro Edit"
	];

	~idm[\macroPresets] = Dictionary[
		"Tight Sync Chop" -> IdentityDictionary[
			\density -> 0.86, \fill -> 0.18, \ghost -> 0.10, \tight -> 0.92,
			\swing -> 0.04, \glitch -> 0.18, \burst -> 0.10, \repeats -> 0.20,
			\chaos -> 0.05, \ratespread -> 0.08, \reverse -> 0.03, \panwidth -> 0.22,
			\env -> 0.10, \humanize -> 0.08, \filter -> 0.03, \res -> 0.05,
			\drive -> 0.12, \crush -> 0.00, \comb -> 0.00, \delay -> 0.00
		],
		"Subtle Jungle" -> IdentityDictionary[
			\density -> 0.78, \fill -> 0.36, \ghost -> 0.24, \tight -> 0.78,
			\swing -> 0.16, \glitch -> 0.34, \burst -> 0.18, \repeats -> 0.36,
			\chaos -> 0.14, \ratespread -> 0.16, \reverse -> 0.08, \panwidth -> 0.42,
			\env -> 0.16, \humanize -> 0.18, \filter -> 0.08, \res -> 0.10,
			\drive -> 0.16, \crush -> 0.03, \comb -> 0.03, \delay -> 0.08
		],
		"IDM Scatter" -> IdentityDictionary[
			\density -> 0.64, \fill -> 0.54, \ghost -> 0.34, \tight -> 0.48,
			\swing -> 0.22, \glitch -> 0.74, \burst -> 0.46, \repeats -> 0.62,
			\chaos -> 0.58, \ratespread -> 0.42, \reverse -> 0.28, \panwidth -> 0.68,
			\env -> 0.34, \humanize -> 0.30, \filter -> 0.26, \res -> 0.24,
			\drive -> 0.28, \crush -> 0.22, \comb -> 0.20, \delay -> 0.24
		],
		"Breakcore Burst" -> IdentityDictionary[
			\density -> 0.92, \fill -> 0.70, \ghost -> 0.22, \tight -> 0.36,
			\swing -> 0.10, \glitch -> 0.86, \burst -> 0.88, \repeats -> 0.78,
			\chaos -> 0.66, \ratespread -> 0.52, \reverse -> 0.22, \panwidth -> 0.58,
			\env -> 0.12, \humanize -> 0.24, \filter -> 0.20, \res -> 0.18,
			\drive -> 0.36, \crush -> 0.30, \comb -> 0.18, \delay -> 0.18
		],
		"Sparse Glitch" -> IdentityDictionary[
			\density -> 0.36, \fill -> 0.20, \ghost -> 0.18, \tight -> 0.62,
			\swing -> 0.18, \glitch -> 0.64, \burst -> 0.20, \repeats -> 0.48,
			\chaos -> 0.42, \ratespread -> 0.28, \reverse -> 0.20, \panwidth -> 0.72,
			\env -> 0.44, \humanize -> 0.34, \filter -> 0.38, \res -> 0.22,
			\drive -> 0.14, \crush -> 0.18, \comb -> 0.24, \delay -> 0.36
		],
		"Reverse Shuffle" -> IdentityDictionary[
			\density -> 0.72, \fill -> 0.42, \ghost -> 0.30, \tight -> 0.64,
			\swing -> 0.36, \glitch -> 0.48, \burst -> 0.28, \repeats -> 0.46,
			\chaos -> 0.28, \ratespread -> 0.30, \reverse -> 0.62, \panwidth -> 0.52,
			\env -> 0.26, \humanize -> 0.24, \filter -> 0.18, \res -> 0.18,
			\drive -> 0.20, \crush -> 0.08, \comb -> 0.12, \delay -> 0.20
		],
		"Micro Edit" -> IdentityDictionary[
			\density -> 0.70, \fill -> 0.46, \ghost -> 0.20, \tight -> 0.82,
			\swing -> 0.06, \glitch -> 0.68, \burst -> 0.34, \repeats -> 0.72,
			\chaos -> 0.20, \ratespread -> 0.18, \reverse -> 0.10, \panwidth -> 0.34,
			\env -> 0.08, \humanize -> 0.12, \filter -> 0.10, \res -> 0.12,
			\drive -> 0.18, \crush -> 0.12, \comb -> 0.08, \delay -> 0.08
		]
	];

	~idm[\getMacro] = { |name|
		(~idm[\macros][name] ? 0.0)
	};

	~idm[\isChecked] = { |value|
		(value == true) or: { value == 1 }
	};

	~idm[\setMacro] = { |name, val|
		var lohi, clipped, view;

		if(~idm.isNil) {
			"IDM not initialized yet.".warn;
			nil
		} {
			lohi = ~idm[\macroSpec][name] ? [0, 1];
			clipped = val.clip(lohi[0], lohi[1]);
			~idm[\macros][name] = clipped;

			if(~idm[\macroViews].notNil and: { ~idm[\macroViews][name].notNil }) {
				~idm[\appDo].value({
					view = ~idm[\macroViews][name];
					if(view[\slider].notNil) {
						view[\slider].value = clipped.linlin(lohi[0], lohi[1], 0, 1);
					};
					if(view[\value].notNil) {
						view[\value].value = clipped;
					};
				});
			};

			clipped
		}
	};

	~idm[\setMacroLock] = { |name, locked = true|
		var view, isLocked;
		isLocked = ~idm[\isChecked].value(locked);
		~idm[\macroLocks][name] = isLocked;
		if(~idm[\macroViews].notNil and: { ~idm[\macroViews][name].notNil }) {
			~idm[\appDo].value({
				view = ~idm[\macroViews][name];
				if(view[\lock].notNil) {
					view[\lock].value = isLocked.if(1, 0);
				};
			});
		};
	};

	~idm[\updateMacroViews] = {
		~idm[\macroOrder].do { |name|
			~idm[\setMacro].value(name, ~idm[\getMacro].value(name));
			~idm[\setMacroLock].value(name, ~idm[\macroLocks][name] == true);
		};
	};

	~idm[\macroOrder].do { |name|
		~idm[\macroLocks][name] = false;
	};

	~idm[\copyMacroValues] = {
		var out;
		out = IdentityDictionary.new;
		~idm[\macroOrder].do { |name|
			out[name] = ~idm[\getMacro].value(name);
		};
		out
	};

	~idm[\applyMacroValues] = { |values, respectLocks = false|
		if(values.notNil) {
			values.keysValuesDo { |name, val|
				if((respectLocks.not) or: { (~idm[\macroLocks][name] == true).not }) {
					~idm[\setMacro].value(name, val);
				};
			};
			if(~idm[\invalidatePattern].notNil) {
				~idm[\invalidatePattern].value(false);
			};
		};
	};

	~idm[\applyPreset] = { |presetName|
		var preset;
		preset = ~idm[\macroPresets][presetName.asString];
		if(preset.isNil) {
			("Unknown preset: " ++ presetName).warn;
			nil
		} {
			~idm[\applyMacroValues].value(preset, true);
			("[IDM] Preset applied: " ++ presetName).postln;
			presetName
		}
	};

	~idm[\randomizeParams] = {
		~idm[\macroOrder].do { |name|
			var spec, lo, hi;
			if((~idm[\macroLocks][name] == true).not) {
				spec = ~idm[\macroSpec][name] ? [0, 1];
				lo = spec[0];
				hi = spec[1];
				~idm[\setMacro].value(name, rrand(lo, hi));
			};
		};
		if(~idm[\invalidatePattern].notNil) {
			~idm[\invalidatePattern].value(false);
		};
		"[IDM] Randomized unlocked params.".postln;
	};

	~idm[\captureAB] = {
		~idm[\macroAB] = ~idm[\copyMacroValues].value;
		"[IDM] Captured macro A/B state.".postln;
	};

	~idm[\swapAB] = {
		var cur, old;
		if(~idm[\macroAB].isNil) {
			"No A/B state captured yet.".warn;
		} {
			cur = ~idm[\copyMacroValues].value;
			old = ~idm[\macroAB];
			~idm[\macroAB] = cur;
			~idm[\applyMacroValues].value(old, false);
			"[IDM] Swapped macro A/B state.".postln;
		};
	};

	// =====================================================
	// MIDI / OSC
	// =====================================================
	MIDIClient.init;
	MIDIIn.connectAll;
	~idm[\ccMaps] = IdentityDictionary.new;
	~idm[\oscMaps] = IdentityDictionary.new;

	~idm[\mapCC] = { |macroName, ccNum, chan = 0|
		MIDIdef.cc(("cc_" ++ macroName).asSymbol).free;
		~idm[\ccMaps][macroName] = ccNum;

		MIDIdef.cc(("cc_" ++ macroName).asSymbol, { |val, num, ch|
			var lohi, mapped;
			if((ch == chan) and: { num == ccNum }) {
				lohi = ~idm[\macroSpec][macroName] ? [0, 1];
				mapped = (val / 127).linlin(0, 1, lohi[0], lohi[1]);
				~idm[\setMacro].value(macroName, mapped);
			};
		});

		("Mapped CC " ++ ccNum ++ " -> " ++ macroName).postln;
	};

	~idm[\learnCC] = { |macroName, chan = 0|
		("Move a CC now to learn mapping for " ++ macroName).postln;
		MIDIdef.cc(\__learnOnce).free;
		MIDIdef.cc(\__learnOnce, { |val, num, ch|
			if(ch == chan) {
				MIDIdef.cc(\__learnOnce).free;
				~idm[\mapCC].value(macroName, num, chan);
			};
		});
	};

	~idm[\mapOSC] = { |macroName, addressString|
		OSCdef(("osc_" ++ macroName).asSymbol).free;
		~idm[\oscMaps][macroName] = addressString;

		OSCdef(("osc_" ++ macroName).asSymbol, { |msg|
			var val, lohi, mapped, inRange;
			val = msg[1].asFloat;
			lohi = ~idm[\macroSpec][macroName] ? [0, 1];
			inRange = (val >= lohi[0]) and: { val <= lohi[1] };
			mapped = inRange.if(val, val.linlin(0, 1, lohi[0], lohi[1]));
			~idm[\setMacro].value(macroName, mapped);
		}, addressString.asSymbol);

		("Mapped OSC " ++ addressString ++ " -> " ++ macroName).postln;
	};

	// =====================================================
	// SYNTH
	// =====================================================
	SynthDef(\idm_slicePlayer, {
		|out = 0, buf = 0, gridStart = 0, gridEnd = 44100, onsetOffset = 0,
		amp = 0.9, rate = 1, pan = 0, atk = 0.002, rel = 0.01, maxDur = 0,
		filter = 0, res = 0, drive = 0, crush = 0, comb = 0, delay = 0|

		var frames, gs, ge, ge2, off, sF, eF;
		var isNeg, step, ph, idx, sig;
		var durFrames, naturalDur, playDur, env;
		var ffreq, rq, driveGain, crushed, combSig, delaySig;

		frames = BufFrames.kr(buf).max(4);

		gs = gridStart.clip(0, frames - 2);
		ge = gridEnd.clip(0, frames - 1);
		ge2 = ge.max(gs + 2).clip(0, frames - 1);

		off = onsetOffset.clip(0, (ge2 - gs).max(0));
		sF = (gs + off).clip(0, ge2 - 1);
		eF = ge2;

		isNeg = (rate < 0);
		step = BufRateScale.kr(buf) * rate.abs.max(0.001);

		ph = Phasor.ar(0, step, sF, eF, sF);
		idx = Select.ar(K2A.ar(isNeg), [ph, (sF + eF) - ph]);

		sig = BufRd.ar(1, buf, idx, 0, 4);

		durFrames = (eF - sF).abs.max(2);
		naturalDur = (durFrames / BufSampleRate.kr(buf).max(1)) / rate.abs.max(0.001);
		playDur = Select.kr(maxDur > 0, [
			naturalDur,
			naturalDur.min(maxDur.max(0.001))
		]);

		env = EnvGen.ar(
			Env.linen(atk, (playDur - atk - rel).max(0.001), rel),
			doneAction: 2
		);

		ffreq = filter.clip(0, 1).linexp(0, 1, 18000, 650);
		rq = res.clip(0, 1).linlin(0, 1, 0.95, 0.16);
		sig = RLPF.ar(sig, ffreq, rq);

		driveGain = drive.clip(0, 1).linlin(0, 1, 1, 7);
		sig = (sig * driveGain).tanh / driveGain.max(0.001);

		crushed = Latch.ar(sig, Impulse.ar(crush.clip(0, 1).linexp(0, 1, SampleRate.ir, 3200)));
		sig = XFade2.ar(sig, crushed, (crush.clip(0, 1) * 2) - 1);

		combSig = CombC.ar(
			sig,
			0.06,
			comb.clip(0, 1).linlin(0, 1, 0.004, 0.038),
			comb.clip(0, 1).linlin(0, 1, 0.04, 0.38)
		);
		sig = sig + (combSig * comb.clip(0, 1) * 0.42);

		delaySig = DelayC.ar(
			sig,
			0.25,
			delay.clip(0, 1).linlin(0, 1, 0.025, 0.18)
		);
		sig = sig + (delaySig * delay.clip(0, 1) * 0.36);

		Out.ar(out, Pan2.ar(sig * env * amp, pan));
	}).add;

	// =====================================================
	// ANALYSIS
	// =====================================================
	~idm[\onsetStrength] = { |sig, hop = 512|
		var nHops, e, od, mx;
		nHops = ((sig.size / hop).floor).asInteger.max(1);
		e = FloatArray.newClear(nHops);
		od = FloatArray.newClear(nHops);

		nHops.do { |i|
			var start, end, sum, count, j, v;
			start = (i * hop).asInteger;
			end = ((start + hop - 1).min(sig.size - 1)).asInteger;
			sum = 0.0;
			count = (end - start + 1).max(1);

			j = start;
			while({ j <= end }, {
				v = sig[j];
				sum = sum + (v * v);
				j = j + 1;
			});

			e[i] = (sum / count).sqrt;
			if((i > 0) and: { (i % 512) == 0 }) {
				~idm[\analysisYield].value;
			};
		};

		nHops.do { |i|
			var a, b, d;
			a = e[i] ? 0.0;
			b = (i == 0).if(0.0, (e[i - 1] ? 0.0));
			d = a - b;
			od[i] = d.max(0.0);
			if((i > 0) and: { (i % 1024) == 0 }) {
				~idm[\analysisYield].value;
			};
		};

		mx = (od.maxItem ? 0.0).max(1e-9);
		od.collect { |v| v / mx };
	};

	~idm[\estimateBpm] = { |od, hop = 512, sr = 44100, minBpm = 140, maxBpm = 175|
		var lagMin, lagMax, bestLag, bestVal;
		lagMin = ((60 * sr) / (hop * maxBpm)).round(1).asInteger.max(1);
		lagMax = ((60 * sr) / (hop * minBpm)).round(1).asInteger.max(lagMin + 1);

		bestLag = lagMin;
		bestVal = -1.0;

		(lagMin .. lagMax).do { |lag|
			var sum, n;
			sum = 0.0;
			n = (od.size - lag).asInteger.max(0);
			n.do { |i| sum = sum + (od[i] * od[i + lag]); };
			if(sum > bestVal) {
				bestVal = sum;
				bestLag = lag;
			};
		};

		(60 * sr) / (hop * bestLag);
	};

	~idm[\pickOnsetPeaks] = { |od, hop = 512, thresh = 0.15|
		var peaks;
		peaks = List.new;
		if(od.size >= 3) {
			(1 .. (od.size - 2)).do { |i|
				var v;
				v = od[i];
				if(v > thresh and: { v > od[i - 1] and: { v >= od[i + 1] } }) {
					peaks.add([(i * hop).asInteger, v]);
				};
				if((i > 0) and: { (i % 1024) == 0 }) {
					~idm[\analysisYield].value;
				};
			};
		};
		peaks.asArray;
	};

	~idm[\buildGridCells16] = { |numFrames, bpm, sr, minSliceBeats = 0.25|
		var total, spb, spCell, nCells;
		total = numFrames.asInteger.max(1);
		spb = (sr * 60 / bpm);
		spCell = spb * minSliceBeats.asFloat.clip(0.0625, 1.0);
		nCells = (total / spCell).ceil.asInteger.max(1);

		Array.fill(nCells, { |i|
			var gs, ge;
			gs = (i * spCell).asInteger;
			ge = (((i + 1) * spCell).min(total)).asInteger;
			if(ge <= gs) { ge = (gs + 2).min(total); };
			[gs, ge]
		});
	};

	~idm[\strongestOnsetOffsetPerCell] = { |cells, peaks|
		var idx, offs;
		idx = 0;
		offs = Array.fill(cells.size, 0);

		cells.size.do { |i|
			var gs, ge, bestFrame, bestStr, j, p;
			gs = cells[i][0].asInteger;
			ge = cells[i][1].asInteger;

			bestFrame = gs;
			bestStr = -1.0;

			while({ idx < peaks.size and: { peaks[idx][0].asInteger < gs } }) {
				idx = idx + 1
			};

			j = idx;
			while({ j < peaks.size and: { peaks[j][0].asInteger < ge } }) {
				p = peaks[j];
				if(p[1].asFloat > bestStr) {
					bestStr = p[1].asFloat;
					bestFrame = p[0].asInteger;
				};
				j = j + 1;
			};

			offs[i] = (bestFrame - gs).max(0).asInteger;
			if((i > 0) and: { (i % 256) == 0 }) {
				~idm[\analysisYield].value;
			};
		};

		offs;
	};

	// =====================================================
	// QUANTIZATION HELPERS
	// =====================================================
	~idm[\quantDivToUnit] = { |div|
		if(div == 8) {
			0.5
		} {
			if(div == 32) { 0.125 } { 0.25 }
		}
	};

	~idm[\quantModeIndex] = { |sym|
		if(sym == \forward) {
			1
		} {
			if(sym == \backward) { 2 } { 0 }
		}
	};

	~idm[\quantModeFromIndex] = { |i|
		if(i == 1) {
			\forward
		} {
			if(i == 2) { \backward } { \nearest }
		}
	};

	~idm[\quantGridIndex] = { |div|
		if(div == 8) {
			0
		} {
			if(div == 32) { 2 } { 1 }
		}
	};

	~idm[\quantGridLabel] = { |div|
		if(div == 8) {
			"1/8"
		} {
			if(div == 32) { "1/32" } { "1/16" }
		}
	};

	~idm[\buildSwingGridTimes] = { |count, unit, swing|
		Array.fill(count, { |i|
			var pair, t;
			pair = (i / 2).floor.asInteger;
			if((i % 2) == 0) {
				t = pair * (2 * unit);
			} {
				t = (pair * (2 * unit)) + unit + (unit * 0.5 * swing);
			};
			t
		});
	};

	~idm[\findQuantSlot] = { |beat, gridTimes, mode|
		var idx, bestIdx, bestDiff, found;

		bestIdx = 0;
		bestDiff = 1e12;

		if(mode == \nearest) {
			(gridTimes.size - 1).do { |i|
				var d;
				d = (gridTimes[i] - beat).abs;
				if(d < bestDiff) {
					bestDiff = d;
					bestIdx = i;
				};
			};
			bestIdx.min(gridTimes.size - 2);
		} {
			if(mode == \forward) {
			idx = gridTimes.size - 2;
			found = false;
			(gridTimes.size - 1).do { |i|
				if(found.not and: { gridTimes[i] >= beat }) {
					idx = i;
					found = true;
				};
			};
				idx.min(gridTimes.size - 2);
			} {
				idx = 0;
				(gridTimes.size - 1).do { |i|
					if(gridTimes[i] <= beat) {
						idx = i;
					};
				};
				idx.min(gridTimes.size - 2);
			};
		}
	};

	~idm[\getSliceFrames] = { |idx|
		var gs, ge, off, sF, eF;
		if(~idm[\cells].isNil or: { ~idm[\onsetOffsets].isNil }) {
			[0, 2]
		} {
			idx = idx.clip(0, ~idm[\cells].size - 1);

			gs = ~idm[\cells][idx][0].asInteger;
			ge = ~idm[\cells][idx][1].asInteger.max(gs + 2);
			off = (~idm[\onsetOffsets][idx] ? 0).asInteger.clip(0, (ge - gs - 1).max(0));

			sF = (gs + off).clip(0, ge - 1);
			eF = ge.max(sF + 2);
			[sF, eF]
		}
	};

	~idm[\sliceEnabled] = { |idx|
		(~idm[\disabledSlices][idx.asInteger] == true).not
	};

	~idm[\enabledSliceIndices] = {
		var cells, out;
		cells = ~idm[\cells];
		out = List.new;
		if(cells.notNil) {
			cells.size.do { |i|
				if(~idm[\sliceEnabled].value(i)) { out.add(i) };
			};
		};
		out.asArray;
	};

	~idm[\nearestEnabledSlice] = { |idx|
		var enabled, best, bestDist;
		enabled = ~idm[\enabledSliceIndices].value;
		if(enabled.size == 0) {
			nil
		} {
			best = enabled[0];
			bestDist = (best - idx.asInteger).abs;
			enabled.do { |candidate|
				var d;
				d = (candidate - idx.asInteger).abs;
				if(d < bestDist) {
					best = candidate;
					bestDist = d;
				};
			};
			best
		}
	};

	~idm[\invalidatePattern] = { |clearFrozen = true|
		~idm[\patternVersion] = (~idm[\patternVersion] ? 0) + 1;
		if(clearFrozen == true) {
			~idm[\frozen] = false;
			~idm[\frozenPattern] = nil;
		};
		~idm[\timelineDirty] = true;
		~idm[\refreshOverlay].value;
	};

	~idm[\patternLengthBeats] = {
		((~idm[\patternBars] ? 4).asFloat.max(1) * 4.0)
	};

	~idm[\makePatternCopy] = { |pattern|
		if(pattern.isNil) {
			nil
		} {
			pattern.collect { |ev|
				var out;
				out = IdentityDictionary.new;
				ev.keysValuesDo { |k, v| out[k] = v };
				out
			}
		}
	};

	~idm[\rebuildQuant] = {
		var bpm, sr, spb, totalBeats, unit, gridDiv, swing, mode, keepOrder;
		var gridTimes, assignments, stepCount;
		var lastAssigned, summary, totalFrames, result, canBuild;

		canBuild = true;
		result = nil;

		if(~idm[\cells].isNil or: { ~idm[\cells].size <= 0 } or: { ~idm[\bpm].isNil }) {
			~idm[\quantGridTimes] = nil;
			~idm[\quantSeqIdxs] = nil;
			~idm[\quantSeqDurs] = nil;
			~idm[\quantSeqBeats] = nil;
			~idm[\overlayCache] = nil;
			canBuild = false;
		};

		if(canBuild) {
			bpm = ~idm[\bpm];
			sr = ~idm[\fileSR] ? ~idm[\sr];
			spb = (sr * 60 / bpm);
			totalFrames = ~idm[\sourceFrames] ? if(~idm[\sourceMono].notNil) { ~idm[\sourceMono].size } { nil };
			if(totalFrames.isNil or: { totalFrames <= 0 }) {
				~idm[\quantGridTimes] = nil;
				~idm[\quantSeqIdxs] = nil;
				~idm[\quantSeqDurs] = nil;
				~idm[\quantSeqBeats] = nil;
				~idm[\overlayCache] = nil;
				canBuild = false;
			};
		};

		if(canBuild) {
			totalBeats = (totalFrames.asFloat / spb).max(1.0);

			gridDiv = (~idm[\quant][\gridDiv] ? 16).asInteger;
			unit = ~idm[\quantDivToUnit].value(gridDiv);
			swing = (~idm[\quant][\swing] ? 0.0).clip(0.0, 0.95);
			mode = ~idm[\quant][\mode] ? \nearest;
			keepOrder = (~idm[\quant][\keepOrder] == true);

			stepCount = (((totalBeats / unit).ceil.asInteger) + 1).max(8);
			gridTimes = Array.fill(stepCount + 1, { |i|
				var pair, t;
				pair = (i / 2).floor.asInteger;
				if((i % 2) == 0) {
					t = pair * (2 * unit);
				} {
					t = (pair * (2 * unit)) + unit + (unit * 0.5 * swing);
				};
				t
			});

			assignments = Array.fill(stepCount, { nil });
			lastAssigned = -1;

			~idm[\cells].size.do { |i|
				var srcBeat, rawSlot, slot;

				srcBeat = ((~idm[\cells][i][0] + (~idm[\onsetOffsets][i] ? 0)).asFloat / spb);
				rawSlot = srcBeat / unit;

				if(mode == \forward) {
					slot = rawSlot.ceil.asInteger;
				} {
					if(mode == \backward) {
						slot = rawSlot.floor.asInteger;
					} {
						slot = rawSlot.round(1).asInteger;
					};
				};

				if(keepOrder) {
					slot = slot.max(lastAssigned + 1);
				};

				slot = slot.clip(0, assignments.size - 1);
				assignments[slot] = i;
				lastAssigned = slot;
			};

			~idm[\quantGridTimes] = gridTimes;
			~idm[\quantSeqIdxs] = assignments;
			~idm[\quantSeqDurs] = Array.fill(assignments.size, { unit.max(0.001) });
			~idm[\quantSeqBeats] = Array.fill(assignments.size, { |i| gridTimes[i] });
			~idm[\overlayCache] = nil;

			summary =
				"Quant: "
				++ ((~idm[\quant][\enabled] == true).if({ "On" }, { "Off" }))
				++ " | Mode: " ++ mode.asString
				++ " | Grid: " ++ ~idm[\quantGridLabel].value(gridDiv)
				++ " | Keep Order: " ++ keepOrder.asString
				++ " | Swing: " ++ swing.round(0.01).asString;

			~idm[\quantSummary] = summary;
			result = summary;
		};

		result
	};

	~idm[\quantPlaybackDur] = { |step|
		var durs;
		durs = ~idm[\quantSeqDurs];
		if(durs.isNil or: { durs.size == 0 }) {
			0.25
		} {
			durs[step % durs.size].asFloat.max(0.001)
		}
	};

	~idm[\quantPlaybackIdx] = { |step|
		var idxs;
		idxs = ~idm[\quantSeqIdxs];
		if(idxs.isNil or: { idxs.size == 0 }) {
			nil
		} {
			idxs[step % idxs.size]
		}
	};

	~idm[\exportQuantTimeline] = { |bars = 4, outPath|
		var mono, sr, bpm, spb, seqIdxs, seqDurs;
		var totalBeats, totalFrames, out, writePos, step, seqSize, sf, copyLen;
		var idx, durBeats, slotFrames, frames, sF, eF, path, canExport, result;

		mono = ~idm[\sourceMono];
		sr = (~idm[\fileSR] ? ~idm[\sr]).asInteger;
		bpm = ~idm[\bpm];
		seqIdxs = ~idm[\quantSeqIdxs];
		seqDurs = ~idm[\quantSeqDurs];
		canExport = true;
		result = nil;

		if(mono.isNil or: { bpm.isNil } or: { seqIdxs.isNil } or: { seqDurs.isNil }) {
			"Need loaded audio + quant sequence before export.".warn;
			canExport = false;
		};

		if(canExport) {
			if(outPath.isNil or: { outPath.asString.stripWhiteSpace.size == 0 }) {
				outPath = Platform.userHomeDir +/+ "Desktop/idm_quant_timeline.wav";
			};

			path = ~idm[\normalizePath].value(outPath);
			if(path.isNil) {
				"Bad export path.".warn;
				canExport = false;
			};
		};

		if(canExport) {
			spb = ((~idm[\fileSR] ? ~idm[\sr]) * 60 / bpm);
			totalBeats = (bars.asFloat * 4.0).max(0.25);
			totalFrames = (totalBeats * spb).ceil.asInteger.max(1);

			out = FloatArray.newClear(totalFrames);
			writePos = 0;
			step = 0;
			seqSize = seqDurs.size.max(1);

			while({ writePos < totalFrames }, {
				idx = seqIdxs[step % seqSize];
				durBeats = seqDurs[step % seqSize].asFloat.max(0.001);
				slotFrames = (durBeats * spb).round.asInteger.max(1);
				slotFrames = slotFrames.min(totalFrames - writePos);

				if(idx.notNil) {
					frames = ~idm[\getSliceFrames].value(idx);
					sF = frames[0].asInteger;
					eF = frames[1].asInteger;
					copyLen = (eF - sF).min(slotFrames).max(0);

					copyLen.do { |j|
						if((sF + j) < mono.size) {
							out[writePos + j] = mono[sF + j];
						};
					};
				};

				writePos = writePos + slotFrames;
				step = step + 1;
			});

			sf = SoundFile.new;
			if(sf.openWrite(path, "WAV", "int16", 1, sr).not) {
				("Could not open export path: " ++ path).warn;
			} {
				sf.writeData(out);
				sf.close;
				("[IDM] Exported quant timeline -> " ++ path).postln;
				result = path;
			};
		};

		result
	};

	// =====================================================
	// WAVE / GUI HELPERS
	// =====================================================
	~idm[\markOverlayDirty] = {
		~idm[\overlayDirty] = true;
	};

	~idm[\rebuildOverlayCache] = { |width|
		var cells, offs, peaks, gridTimes, totalFrames, bpm, sr, spb, xScale;
		var cache, mono, xCount, framesPerPixel;

		cells = ~idm[\cells];
		offs = ~idm[\onsetOffsets];
		peaks = ~idm[\onsetPeaks];
		mono = ~idm[\sourceMono];
		totalFrames = ~idm[\sourceFrames] ? if(mono.notNil) { mono.size } { 0 };

		if(cells.isNil or: { totalFrames <= 0 } or: { width <= 0 }) {
			~idm[\overlayCache] = nil;
			nil
		} {
			xCount = width.asInteger.max(1);
			framesPerPixel = totalFrames.asFloat / xCount;
			xScale = { |frame| frame.asFloat / totalFrames * width };
			cache = IdentityDictionary.new;
			cache[\width] = width;
			cache[\totalFrames] = totalFrames;

			cache[\wavePairs] = if(mono.notNil) {
				Array.fill(xCount, { |x|
					var start, end, j, lo, hi, v;
					start = (x * framesPerPixel).floor.asInteger.clip(0, totalFrames - 1);
					end = (((x + 1) * framesPerPixel).ceil.asInteger - 1).clip(start, totalFrames - 1);
					lo = 0.0;
					hi = 0.0;
					j = start;
					while({ j <= end }, {
						v = mono[j] ? 0.0;
						if(v < lo) { lo = v };
						if(v > hi) { hi = v };
						j = j + 1;
					});
					[lo, hi]
				})
			} {
				nil
			};

			cache[\cellXs] = cells.collect { |cell| xScale.value(cell[0]) };
			cache[\cellEndXs] = cells.collect { |cell| xScale.value(cell[1]) };
			cache[\onsetXs] = if(offs.notNil) {
				cells.collect { |cell, i| xScale.value(cell[0] + (offs[i] ? 0)) }
			} {
				nil
			};
			cache[\peakXs] = if(peaks.notNil) {
				peaks.collect { |p| xScale.value(p[0]) }
			} {
				nil
			};

			if((~idm[\quant][\enabled] == true) and: { ~idm[\quantGridTimes].notNil } and: { ~idm[\bpm].notNil }) {
				bpm = ~idm[\bpm];
				sr = ~idm[\fileSR] ? ~idm[\sr];
				spb = (sr * 60 / bpm);
				gridTimes = ~idm[\quantGridTimes];
				cache[\quantXs] = Array.fill(gridTimes.size.min(128), { |i|
					var frame;
					frame = (gridTimes[i] * spb).asInteger.clip(0, totalFrames - 1);
					xScale.value(frame)
				});
			} {
				cache[\quantXs] = nil;
			};

			~idm[\overlayCache] = cache;
			cache
		}
	};

	~idm[\refreshWaveform] = {
		~idm[\appDo].value({
			var sfv;
			sfv = ~idm[\waveView];

			if(sfv.notNil) {
				if(~idm[\waveFile].notNil) {
					try { ~idm[\waveFile].close } { };
					~idm[\waveFile] = nil;
				};

				~idm[\overlayCache] = nil;
				~idm[\markOverlayDirty].value;
				if(~idm[\sourceMono].notNil) {
					~idm[\rebuildOverlayCache].value(sfv.bounds.width);
				};
				sfv.refresh;
			};
		});
	};

	~idm[\refreshOverlay] = {
		~idm[\markOverlayDirty].value;
		if(~idm[\overlayRefreshPending] != true) {
			~idm[\overlayRefreshPending] = true;
			~idm[\appDo].value({
				~idm[\overlayRefreshPending] = false;
				if(~idm[\sliceText].notNil) {
					~idm[\sliceText].string =
					"Slice: " ++ (~idm[\currentSlice] ? 0).asString
					++ " | Step: " ++ (~idm[\currentStep] ? 0).asString;
				};
				if(~idm[\quantSummaryText].notNil) {
					~idm[\quantSummaryText].string = ~idm[\quantSummary] ? "";
				};
				if(~idm[\overlayView].notNil) {
					~idm[\overlayDirty] = false;
					~idm[\overlayView].refresh;
				};
				if(~idm[\timelineView].notNil) {
					~idm[\timelineDirty] = false;
					~idm[\timelineView].refresh;
				};
			});
		};
	};

	~idm[\setCurrentSlice] = { |idx, step = 0|
		~idm[\currentSlice] = idx.asInteger.max(0);
		~idm[\currentStep] = step.asInteger.max(0);
		~idm[\refreshOverlay].value;
	};

	~idm[\updateGuiAfterLoad] = {
		~idm[\appDo].value({
			if(~idm[\pathField].notNil) {
				~idm[\pathField].string = "";
			};

			if(~idm[\modePop].notNil) {
				~idm[\modePop].value = ~idm[\modeIndex].value(~idm[\mode]);
			};

			if(~idm[\forceSoundToggle].notNil) {
				~idm[\forceSoundToggle].value = (~idm[\forceHits] == true).if(1, 0);
			};

			if(~idm[\cellsText].notNil) {
				~idm[\cellsText].string = "Cells: " ++ ((~idm[\cells] ? []).size.asString);
			};

			if(~idm[\peaksText].notNil) {
				~idm[\peaksText].string = "Peaks: " ++ ((~idm[\onsetPeaks] ? []).size.asString);
			};

			if(~idm[\quantEnableToggle].notNil) {
				~idm[\quantEnableToggle].value = ((~idm[\quant][\enabled] == true).if(1, 0));
			};

			if(~idm[\quantModePop].notNil) {
				~idm[\quantModePop].value = ~idm[\quantModeIndex].value(~idm[\quant][\mode]);
			};

			if(~idm[\quantGridPop].notNil) {
				~idm[\quantGridPop].value = ~idm[\quantGridIndex].value(~idm[\quant][\gridDiv]);
			};

			if(~idm[\quantKeepOrderToggle].notNil) {
				~idm[\quantKeepOrderToggle].value = ((~idm[\quant][\keepOrder] == true).if(1, 0));
			};

			if(~idm[\quantSwingSlider].notNil) {
				~idm[\quantSwingSlider].value = (~idm[\quant][\swing] ? 0.0);
			};

			if(~idm[\quantSwingBox].notNil) {
				~idm[\quantSwingBox].value = (~idm[\quant][\swing] ? 0.0);
			};

			if(~idm[\quantSummaryText].notNil) {
				~idm[\quantSummaryText].string = ~idm[\quantSummary] ? "";
			};

			if(~idm[\seedField].notNil) {
				~idm[\seedField].value = (~idm[\seed] ? 0).asInteger;
			};

			if(~idm[\patternBarsField].notNil) {
				~idm[\patternBarsField].value = (~idm[\patternBars] ? 4).asInteger.max(1);
			};

			if(~idm[\bpmOverrideField].notNil) {
				~idm[\bpmOverrideField].value = (~idm[\bpmOverride] ? 0).asFloat;
			};

			if(~idm[\onsetSensitivitySlider].notNil) {
				~idm[\onsetSensitivitySlider].value = (~idm[\onsetSensitivity] ? 0.15).linlin(0.02, 0.5, 0, 1).clip(0, 1);
			};

			if(~idm[\onsetSensitivityBox].notNil) {
				~idm[\onsetSensitivityBox].value = (~idm[\onsetSensitivity] ? 0.15).asFloat;
			};

			if(~idm[\minSlicePop].notNil) {
				~idm[\minSlicePop].value = [0.0625, 0.125, 0.25, 0.5].indexOfEqual((~idm[\minSliceBeats] ? 0.25).asFloat) ? 2;
			};

			if(~idm[\sessionPathField].notNil) {
				~idm[\sessionPathField].string = ~idm[\sessionPath] ? (Platform.userHomeDir +/+ "Desktop/idm_session.scdarchive");
			};
		});

		~idm[\markOverlayDirty].value;
	};

	~idm[\reanalyzeLoaded] = { |resetDisabled = true, clearPattern = true|
		var mono, frames, fileSR, od, bpm, peaks, sens, minBeats, canAnalyze;
		canAnalyze = true;
		mono = ~idm[\sourceMono];
		frames = ~idm[\sourceFrames] ? if(mono.notNil) { mono.size } { 0 };
		fileSR = (~idm[\fileSR] ? ~idm[\sr]).asFloat.max(1.0);

		if(mono.isNil or: { frames <= 0 }) {
			"No loaded audio to re-analyze.".warn;
			canAnalyze = false;
		};

		if(canAnalyze) {
			sens = (~idm[\onsetSensitivity] ? 0.15).asFloat.clip(0.02, 0.5);
			minBeats = (~idm[\minSliceBeats] ? 0.25).asFloat.clip(0.0625, 1.0);

			od = ~idm[\onsetStrength].value(mono, ~idm[\hop]);
			if(~idm[\bpmOverride].notNil and: { ~idm[\bpmOverride].asFloat > 0 }) {
				bpm = ~idm[\bpmOverride].asFloat.round(0.1);
			} {
				bpm = ~idm[\estimateBpm].value(
					od, ~idm[\hop], fileSR, ~idm[\minBpm], ~idm[\maxBpm]
				).round(0.1);
			};

			~idm[\bpm] = bpm;

			if(~idm[\clock].notNil) {
				try { ~idm[\clock].stop } { };
			};
			~idm[\clock] = TempoClock.new(bpm / 60).permanent_(true);
			~idm[\clock].play;

			("Estimated BPM (constrained): " ++ bpm).postln;
			~idm[\setBpmStatus].value(bpm);

			peaks = ~idm[\pickOnsetPeaks].value(od, ~idm[\hop], sens);
			~idm[\onsetPeaks] = peaks;
			~idm[\cells] = ~idm[\buildGridCells16].value(frames, bpm, fileSR, minBeats);
			~idm[\onsetOffsets] = ~idm[\strongestOnsetOffsetPerCell].value(~idm[\cells], peaks);

			if(resetDisabled == true) {
				~idm[\disabledSlices] = IdentityDictionary.new;
			};

			("Grid cells (" ++ minBeats.asString ++ " beat): " ++ ~idm[\cells].size).postln;
			("Onset peaks: " ++ peaks.size).postln;

			"[IDM] Rebuilding quant map...".postln;
			~idm[\rebuildQuant].value;
			"[IDM] Quant map ready.".postln;

			~idm[\overlayCache] = nil;
			if(clearPattern == true) {
				~idm[\invalidatePattern].value(true);
			};
			~idm[\updateGuiAfterLoad].value;
			~idm[\refreshWaveform].value;
			~idm[\refreshOverlay].value;
			bpm
		} {
			nil
		}
	};

	// =====================================================
	// LOADER
	// =====================================================
	~idm[\load] = { |path|
		if(~idm[\isLoading] == true) {
			"IDM: load ignored (already loading).".warn;
			nil
		} {
			~idm[\isLoading] = true;

			if(~idm[\loadRoutine].notNil and: { ~idm[\loadRoutine] !== thisThread }) {
				try { ~idm[\loadRoutine].stop } { };
			};
			~idm[\loadRoutine] = nil;

			try {
				var sf, frames, chans, fileSR, data, mono, canContinue;
				var finish = {
					~idm[\isLoading] = false;
					~idm[\loadRoutine] = nil;
				};

				canContinue = true;
				path = ~idm[\normalizePath].value(path);
				if(path.isNil) {
					"No file selected.".warn;
					canContinue = false;
				};

				if(canContinue and: { File.exists(path).not }) {
					("File not found: " ++ path).warn;
					canContinue = false;
				};

				if(canContinue) {
					sf = SoundFile.new;
					if(sf.openRead(path).not) {
						("Could not open audio file: " ++ path).warn;
						canContinue = false;
					};
				};

				if(canContinue) {
					frames = sf.numFrames.asInteger.max(0);
					chans = sf.numChannels.asInteger.max(1);
					fileSR = sf.sampleRate.asFloat.max(1.0);

					if(frames <= 0) {
						sf.close;
						("Could not read frames: " ++ path).warn;
						canContinue = false;
					};
				};

				if(canContinue.not) {
					finish.value;
				} {
					~idm[\saveLastPath].value(path);
					~idm[\loadedPath] = path;
					~idm[\setStatus].value("Loading...");
					("Loading: " ++ path).postln;

					~idm[\ready] = false;
					~idm[\serverBufReady] = false;

					if(~idm[\pat].notNil) {
						~idm[\pat].stop;
						~idm[\pat] = nil;
					};

					if(~idm[\buf].notNil) {
						~idm[\buf].free;
						~idm[\buf] = nil;
					};

					~idm[\cells] = nil;
					~idm[\onsetOffsets] = nil;
					~idm[\onsetPeaks] = nil;
					~idm[\sourceMono] = nil;
					~idm[\sourceFrames] = nil;
					~idm[\quantGridTimes] = nil;
					~idm[\quantSeqIdxs] = nil;
					~idm[\quantSeqDurs] = nil;
					~idm[\quantSeqBeats] = nil;
					~idm[\overlayCache] = nil;
					~idm[\frozen] = false;
					~idm[\frozenPattern] = nil;
					~idm[\timelineDirty] = true;
					~idm[\selectedSlice] = 0;
					~idm[\selectedFrame] = 0;
					~idm[\selectedEvent] = 0;
					~idm[\disabledSlices] = IdentityDictionary.new;

					~idm[\buf] = Buffer.readChannel(s, path, channels: [0], action: {
						~idm[\serverBufReady] = true;
					});
					~idm[\fileSR] = fileSR;

					data = FloatArray.newClear(frames * chans);
					sf.readData(data);
					sf.close;

					mono = FloatArray.newClear(frames);
					frames.do { |i|
						var sum = 0.0;
						chans.do { |c| sum = sum + data[(i * chans) + c]; };
						mono[i] = sum / chans;
						if((i > 0) and: { (i % 65536) == 0 }) {
							~idm[\analysisYield].value;
						};
					};
					data = nil;

					~idm[\sourceMono] = mono;
					~idm[\sourceFrames] = frames;
					~idm[\reanalyzeLoaded].value(false, true);

					~idm[\ready] = true;
					~idm[\currentSlice] = 0;
					~idm[\currentStep] = 0;
					~idm[\setStatus].value("Loaded (playable)");

					finish.value;
					~idm[\updateGuiAfterLoad].value;
					~idm[\refreshWaveform].value;
					~idm[\refreshOverlay].value;
				};
			} { |error|
				"IDM: load failed; clearing loading flag.".warn;
				~idm[\isLoading] = false;
				~idm[\loadRoutine] = nil;
				error.reportError;
			};
		}
	};

	// =====================================================
	// PREVIEW
	// =====================================================
	~idm[\preview] = { |i = 0|
		var cells, offs, buf;
		buf = ~idm[\buf];
		cells = ~idm[\cells];
		offs = ~idm[\onsetOffsets];

		if(buf.isNil or: { cells.isNil } or: { offs.isNil }) {
			"Load a break first.".warn;
			nil
		} {
			i = i.clip(0, cells.size - 1);
			~idm[\setCurrentSlice].value(i, i);

			Synth(\idm_slicePlayer, [
				\buf, buf,
				\gridStart, cells[i][0],
				\gridEnd,   cells[i][1],
				\onsetOffset, offs[i],
				\amp, 0.9,
				\rate, 1,
				\atk, 0.002,
				\rel, 0.15
			]);
		}
	};

	// =====================================================
	// GROOVE HELPERS
	// =====================================================
	~idm[\hitGate] = { |step, mode = \sync|
		var d, f, g, b, c, tight, on;
		mode = ~idm[\modeFromInput].value(mode);

		d = ~idm[\getMacro].value(\density);
		f = ~idm[\getMacro].value(\fill);
		g = ~idm[\getMacro].value(\ghost);
		b = ~idm[\getMacro].value(\burst);
		c = ~idm[\getMacro].value(\chaos);
		tight = ~idm[\getMacro].value(\tight);

		if(mode == \sync) {
			d = (d + (tight * 0.08)).clip(0.0, 1.0);
		} {
			d = (d + (c * 0.14) - ((1.0 - tight) * 0.06)).clip(0.0, 1.0);
			f = (f + (c * 0.22) + (b * 0.08)).clip(0.0, 1.0);
		};

		on = (1.0.rand <= d);
		if(on.not and: { 1.0.rand < (f * 0.35) }) { on = true };
		if(on.not and: { ((step % 2) == 1) and: { 1.0.rand < g } }) { on = true };
		if((mode == \free) and: { on.not } and: { 1.0.rand < (b * c * 0.18) }) { on = true };
		on;
	};

	~idm[\freeDurForStep] = { |step|
		var g, b, r, c, tight, swing, dur, lock;
		g = ~idm[\getMacro].value(\glitch);
		b = ~idm[\getMacro].value(\burst);
		r = ~idm[\getMacro].value(\repeats);
		c = ~idm[\getMacro].value(\chaos);
		tight = ~idm[\getMacro].value(\tight);
		swing = ~idm[\getMacro].value(\swing);

		dur = [0.25, 0.125, 0.0625, 0.375, 0.5].wchoose(
			[
				0.56 - (c * 0.22),
				0.24 + (g * 0.10) + (r * 0.08),
				0.08 + (g * 0.20) + (b * 0.16),
				0.08 + (c * 0.12),
				0.04 + ((1.0 - tight) * 0.12)
			].normalizeSum
		);

		lock = tight.linlin(0, 1, 0.0, 0.55);
		dur = (dur * (1.0 - lock)) + (0.25 * lock);

		if((step % 2) == 1) {
			dur = dur * (1.0 + (swing * 0.45));
		} {
			dur = dur * (1.0 - (swing * 0.20));
		};

		dur.clip(0.0625, 0.5)
	};

	~idm[\pickIdxFree] = { |step|
		var enabled, n, g, b, r, c, idx, last;
		enabled = ~idm[\enabledSliceIndices].value;
		n = enabled.size.max(1);

		g = ~idm[\getMacro].value(\glitch);
		b = ~idm[\getMacro].value(\burst);
		r = ~idm[\getMacro].value(\repeats);
		c = ~idm[\getMacro].value(\chaos);
		last = ~idm[\lastFreeIdx];

		if(enabled.size == 0) {
			idx = 0;
		} {
		if(last.notNil and: { (~idm[\sliceEnabled].value(last)) and: { 1.0.rand < (r * (0.18 + (g * 0.22))) } }) {
			idx = last;
		} {
			if(1.0.rand < (0.18 + (g * 0.28) + (c * 0.42))) {
				idx = enabled[rrand(0, n - 1)];
			} {
				var stride = [1, 2, 3, 4, 8].wchoose(
					[
						0.48 + ((1.0 - c) * 0.20),
						0.22 + (r * 0.22),
						0.08 + (c * 0.18),
						0.14 + (g * 0.18),
						0.08 + (b * 0.28)
					].normalizeSum
				).asInteger;
				idx = enabled[(step * stride) % n];
			};
		};
		};

		idx = idx.asInteger.clip(0, (~idm[\cells].size ? 1).max(1) - 1);
		~idm[\lastFreeIdx] = idx;
		idx
	};

	~idm[\pickIdxChaos] = ~idm[\pickIdxFree];

	~idm[\rateForStep] = { |mode = \sync|
		var spread, revProb, g, c, base, det, rev;
		mode = ~idm[\modeFromInput].value(mode);
		c = (mode == \free).if({ ~idm[\getMacro].value(\chaos) }, { 0.0 });
		spread = (~idm[\getMacro].value(\ratespread) + (c * 0.22)).clip(0.0, 1.0);
		revProb = (~idm[\getMacro].value(\reverse) + (c * 0.10)).clip(0.0, 1.0);
		g = ~idm[\getMacro].value(\glitch);

		base = 1.0;
		if((mode == \free) and: { 1.0.rand < (c * 0.16) }) {
			base = [0.5, 0.75, 1.0, 1.5, 2.0].wchoose([0.12, 0.16, 0.44, 0.18, 0.10]);
		};

		det = rrand(-1.0, 1.0) * spread.linlin(0, 1, 0.0, 0.65);
		if(1.0.rand < (g * (0.10 + (c * 0.18)))) { det = det + [-0.5, 0.5, 1.0].choose };

		rev = (1.0.rand < revProb).if(-1, 1);
		(base + det).max(0.08) * rev
	};

	~idm[\panForStep] = {
		var w;
		w = ~idm[\getMacro].value(\panwidth).linlin(0, 1, 0.0, 0.95);
		rrand(w.neg, w);
	};

	~idm[\envForStep] = {
		var soft, tight, atk, rel;
		soft = ~idm[\getMacro].value(\env);
		tight = ~idm[\getMacro].value(\tight);
		atk = soft.linlin(0, 1, 0.001, 0.02);
		rel = soft.linlin(0, 1, 0.03, 0.22);
		rel = rel * tight.linlin(0, 1, 1.25, 0.55);
		[atk, rel]
	};

	~idm[\ampForStep] = { |isGhost = false|
		var hum, a, spread;
		hum = ~idm[\getMacro].value(\humanize);
		a = isGhost.if(0.22, 0.85);
		spread = hum.linlin(0, 1, 0.0, 0.35);
		(a * rrand(1.0 - spread, 1.0 + spread)).clip(0.0, 1.2)
	};

	~idm[\fxForStep] = { |mode = \sync|
		var c, g, hum, f, r, d, crush, comb, delay;
		mode = ~idm[\modeFromInput].value(mode);
		c = (mode == \free).if({ ~idm[\getMacro].value(\chaos) }, { 0.0 });
		g = ~idm[\getMacro].value(\glitch);
		hum = ~idm[\getMacro].value(\humanize);

		f = (~idm[\getMacro].value(\filter) + (c * g * 0.12) + rrand(0.0, hum * 0.08)).clip(0, 1);
		r = (~idm[\getMacro].value(\res) + (c * 0.08)).clip(0, 1);
		d = (~idm[\getMacro].value(\drive) + rrand(0.0, g * 0.04)).clip(0, 1);
		crush = (~idm[\getMacro].value(\crush) + (c * g * 0.08)).clip(0, 1);
		comb = (~idm[\getMacro].value(\comb) + (mode == \free).if({ c * 0.05 }, { 0.0 })).clip(0, 1);
		delay = (~idm[\getMacro].value(\delay) + (mode == \free).if({ c * 0.05 }, { 0.0 })).clip(0, 1);

		(
			filter: f,
			res: r,
			drive: d,
			crush: crush,
			comb: comb,
			delay: delay
		)
	};

	~idm[\makeStepEvent] = { |step, mode, n, quantEnabled, tempo, doGui = true|
		var idx, dur, isRest, hitOn, isGhost, env, rate, pan, amp, maxDur, fx;
		mode = ~idm[\modeFromInput].value(mode);
		step = step.asInteger;
		n = n.asInteger.max(1);
		tempo = tempo.asFloat.max(0.001);
		isRest = false;

		if(mode == \sync) {
			if(quantEnabled) {
				dur = ~idm[\quantPlaybackDur].value(step);
				idx = ~idm[\quantPlaybackIdx].value(step);
			} {
				dur = 0.25;
				idx = (step % n).asInteger;
			};
		} {
			dur = ~idm[\freeDurForStep].value(step);
			idx = ~idm[\pickIdxFree].value(step).clip(0, n - 1).asInteger;
		};

		if(idx.isNil) {
			isRest = true;
			idx = (~idm[\currentSlice] ? 0).asInteger.clip(0, n - 1);
			if(doGui == true) { ~idm[\setCurrentSlice].value(idx, step) };
		} {
			idx = idx.clip(0, n - 1).asInteger;
			if(~idm[\sliceEnabled].value(idx).not) {
				isRest = true;
				idx = (~idm[\nearestEnabledSlice].value(idx) ? idx).asInteger.clip(0, n - 1);
			};
			if(doGui == true) { ~idm[\setCurrentSlice].value(idx, step) };
		};

		hitOn = if(~idm[\forceHits] == true) {
			true
		} {
			~idm[\hitGate].value(step, mode)
		};
		if(hitOn.not) { isRest = true };

		isGhost = ((step % 2) == 1) and: {
			1.0.rand < (~idm[\getMacro].value(\ghost) * 0.35)
		};

		env = ~idm[\envForStep].value;
		rate = if(isRest) { 1.0 } { ~idm[\rateForStep].value(mode) };
		pan = if(mode == \sync) { rrand(-0.35, 0.35) } { ~idm[\panForStep].value };
		amp = if(isRest) { 0.0 } { ~idm[\ampForStep].value(isGhost) };
		maxDur = (dur.asFloat / tempo).max(0.001);
		fx = if(isRest) {
			(filter: 0, res: 0, drive: 0, crush: 0, comb: 0, delay: 0)
		} {
			~idm[\fxForStep].value(mode)
		};

		(
			beat: 0.0,
			dur: dur,
			idx: idx,
			isRest: isRest,
			isGhost: isGhost,
			rate: rate,
			pan: pan,
			atk: env[0],
			rel: env[1],
			amp: amp.clip(0.0, 1.2),
			maxDur: maxDur,
			filter: fx[\filter],
			res: fx[\res],
			drive: fx[\drive],
			crush: fx[\crush],
			comb: fx[\comb],
			delay: fx[\delay],
			locked: false
		)
	};

	~idm[\generatePattern] = { |bars = nil, seed = nil, version = nil|
		var pattern, mode, n, quantEnabled, tempo, totalBeats, beat, step, ev;
		var clock;

		pattern = List.new;
		mode = ~idm[\modeFromInput].value(~idm[\mode]);
		n = ((~idm[\cells].size ? 1).asInteger).max(1);
		clock = ~idm[\clock];
		tempo = (clock.notNil).if({ clock.tempo }, { ((~idm[\bpm] ? 120) / 60) }).asFloat.max(0.001);
		totalBeats = ((bars ? ~idm[\patternBars] ? 4).asFloat.max(1) * 4.0);
		quantEnabled = (mode == \sync) and: { (~idm[\quant][\enabled] == true) } and: {
			~idm[\quantSeqIdxs].notNil and: { ~idm[\quantSeqDurs].notNil }
		};

		thisThread.randSeed = ((seed ? ~idm[\seed] ? 12345).asInteger + (version ? ~idm[\patternVersion] ? 0).asInteger).abs;
		~idm[\lastFreeIdx] = nil;

		beat = 0.0;
		step = 0;
		while({ beat < totalBeats and: { step < 4096 } }, {
			ev = ~idm[\makeStepEvent].value(step, mode, n, quantEnabled, tempo, false);
			ev[\beat] = beat;
			pattern.add(ev);
			beat = beat + ev[\dur].asFloat.max(0.001);
			step = step + 1;
		});

		pattern.asArray
	};

	~idm[\setFrozenPattern] = { |pattern, frozen = true|
		~idm[\frozenPattern] = pattern;
		~idm[\frozen] = (frozen == true);
		~idm[\selectedEvent] = 0;
		~idm[\timelineDirty] = true;
		~idm[\refreshOverlay].value;
		pattern
	};

	~idm[\freeze] = { |forceRegenerate = false|
		var pattern;
		if(~idm[\ready].not or: { ~idm[\cells].isNil }) {
			"Load a break first.".warn;
			nil
		} {
			if(forceRegenerate or: { ~idm[\frozenPattern].isNil }) {
				pattern = ~idm[\generatePattern].value(~idm[\patternBars], ~idm[\seed], ~idm[\patternVersion]);
			} {
				pattern = ~idm[\makePatternCopy].value(~idm[\frozenPattern]);
			};
			~idm[\setFrozenPattern].value(pattern, true);
			("[IDM] Frozen pattern: " ++ pattern.size ++ " events, seed=" ++ ~idm[\seed]).postln;
			pattern
		}
	};

	~idm[\regen] = {
		~idm[\patternVersion] = (~idm[\patternVersion] ? 0) + 1;
		~idm[\freeze].value(true);
	};

	~idm[\unfreeze] = {
		~idm[\frozen] = false;
		~idm[\timelineDirty] = true;
		~idm[\refreshOverlay].value;
		"[IDM] Live random playback enabled.".postln;
	};

	~idm[\mutate] = { |amount = 0.25|
		var base, fresh, out, amt;
		amt = amount.asFloat.clip(0.0, 1.0);
		if(~idm[\frozenPattern].isNil) {
			~idm[\freeze].value(true);
		} {
			~idm[\patternVersion] = (~idm[\patternVersion] ? 0) + 1;
			base = ~idm[\frozenPattern];
			fresh = ~idm[\generatePattern].value(~idm[\patternBars], ~idm[\seed], ~idm[\patternVersion]);
			out = Array.fill(base.size.max(fresh.size), { |i|
				var old, neu, chosen;
				old = base[i % base.size];
				neu = fresh[i % fresh.size];
				chosen = ((old[\locked] == true) or: { 1.0.rand > amt }).if({ old }, { neu });
				~idm[\makePatternCopy].value([chosen])[0]
			});
			~idm[\setFrozenPattern].value(out, true);
			("[IDM] Mutated frozen pattern, amount=" ++ amt.round(0.01)).postln;
		};
	};

	~idm[\frozenEventForStep] = { |step|
		var pattern, ev, idx;
		pattern = ~idm[\frozenPattern];
		if(pattern.isNil or: { pattern.size == 0 }) {
			nil
		} {
			idx = step.asInteger % pattern.size;
			ev = pattern[idx];
			if(ev[\idx].notNil) {
				~idm[\setCurrentSlice].value(ev[\idx], step);
			};
			~idm[\selectedEvent] = idx;
			ev
		}
	};

	~idm[\editSelectedEvent] = { |action|
		var pattern, i, ev, n;
		pattern = ~idm[\frozenPattern];
		if(pattern.isNil or: { pattern.size == 0 }) {
			"Freeze or regenerate a pattern first.".warn;
			nil
		} {
			i = (~idm[\selectedEvent] ? 0).asInteger.clip(0, pattern.size - 1);
			ev = pattern[i];
			n = ((~idm[\cells].size ? 1).asInteger).max(1);
			if(action == \toggleRest) {
				ev[\isRest] = (ev[\isRest] == true).not;
				if(ev[\isRest] == true) { ev[\amp] = 0.0 } { ev[\amp] = ev[\amp].asFloat.max(0.7) };
			};
			if(action == \lockSlice) {
				ev[\locked] = (ev[\locked] == true).not;
			};
			if(action == \replaceSlice) {
				ev[\idx] = (~idm[\selectedSlice] ? ev[\idx] ? 0).asInteger.clip(0, n - 1);
				ev[\isRest] = false;
				ev[\amp] = ev[\amp].asFloat.max(0.7);
			};
			~idm[\timelineDirty] = true;
			~idm[\refreshOverlay].value;
			ev
		}
	};

	// =====================================================
	// PLAY / STOP
	// =====================================================
	~idm[\play] = {
		var buf, clock, mode, n, quantEnabled, canPlay;

		buf = ~idm[\buf];
		clock = ~idm[\clock];
		canPlay = true;

		if(buf.isNil) { "No buffer loaded.".warn; canPlay = false; };
		if(canPlay and: { clock.isNil }) { "No clock.".warn; canPlay = false; };
		if(canPlay and: { ~idm[\ready].not }) { "Not ready yet (still loading).".warn; canPlay = false; };
		if(canPlay and: { ~idm[\serverBufReady].not }) { "Audio buffer is still transferring to the server.".warn; canPlay = false; };

		if(canPlay) {
			if(clock.isRunning.not) { clock.play; };

			if(~idm[\pat].notNil) {
				~idm[\pat].stop;
				~idm[\pat] = nil;
			};

			mode = ~idm[\modeFromInput].value(~idm[\mode]);
			~idm[\mode] = mode;
			n = ((~idm[\cells].size ? 1).asInteger).max(1);
			quantEnabled = (mode == \sync) and: { (~idm[\quant][\enabled] == true) } and: {
				~idm[\quantSeqIdxs].notNil and: { ~idm[\quantSeqDurs].notNil }
			};
			~idm[\lastFreeIdx] = nil;

			~idm[\pat] = Pbind(
				\instrument, \idm_slicePlayer,
				\buf, Pfunc { ~idm[\buf].bufnum },

				\step, Pseries(0, 1, inf),
				\eventData, Pfunc { |ev|
					var frozenEv;
					frozenEv = if(~idm[\frozen] == true) {
						~idm[\frozenEventForStep].value(ev[\step].asInteger)
					} {
						nil
					};
					frozenEv ? ~idm[\makeStepEvent].value(
						ev[\step].asInteger,
						mode,
						n,
						quantEnabled,
						clock.tempo
					)
				},

				\type, Pfunc { |ev|
					(ev[\eventData][\isRest] == true).if({ \rest }, { \note })
				},
				\dur, Pfunc { |ev| ev[\eventData][\dur] },
				\idx2, Pfunc { |ev| ev[\eventData][\idx] },

				\gridStart, Pfunc { |ev|
					var idx;
					idx = ev[\idx2];
					if(idx.isNil) { 0 } { ~idm[\cells][idx][0] }
				},

				\gridEnd, Pfunc { |ev|
					var idx;
					idx = ev[\idx2];
					if(idx.isNil) { 2 } { ~idm[\cells][idx][1] }
				},

				\onsetOffset, Pfunc { |ev|
					var idx;
					idx = ev[\idx2];
					if(idx.isNil) { 0 } { ~idm[\onsetOffsets][idx] }
				},

				\rate, Pfunc { |ev| ev[\eventData][\rate] },
				\pan, Pfunc { |ev| ev[\eventData][\pan] },
				\atk, Pfunc { |ev| ev[\eventData][\atk] },
				\rel, Pfunc { |ev| ev[\eventData][\rel] },
				\amp, Pfunc { |ev| ev[\eventData][\amp] },
				\maxDur, Pfunc { |ev| ev[\eventData][\maxDur] },
				\filter, Pfunc { |ev| ev[\eventData][\filter] ? 0 },
				\res, Pfunc { |ev| ev[\eventData][\res] ? 0 },
				\drive, Pfunc { |ev| ev[\eventData][\drive] ? 0 },
				\crush, Pfunc { |ev| ev[\eventData][\crush] ? 0 },
				\comb, Pfunc { |ev| ev[\eventData][\comb] ? 0 },
				\delay, Pfunc { |ev| ev[\eventData][\delay] ? 0 }
			).play(clock, quant: 0.0);

			~idm[\playerRunning] = true;
			~idm[\setStatus].value("Playing");
			("[IDM] Playing (Pbind). mode=" ++ mode ++ " quant=" ++ quantEnabled.asString).postln;
		};
		nil
	};

	~idm[\stop] = {
		if(~idm.notNil and: { ~idm[\pat].notNil }) {
			~idm[\pat].stop;
			~idm[\pat] = nil;
		};

		if(~idm.notNil) {
			~idm[\playerRunning] = false;
		};

		~idm[\setStatus].value("Stopped.");
		"[IDM] Stopped.".postln;
	};

	// =====================================================
	// RENDER
	// =====================================================
	~idm[\renderBars] = { |bars = 8, outPath|
		var clock, tempo, durSec, canRender, result;

		canRender = true;
		result = nil;
		if(~idm.isNil) { "IDM not initialized.".warn; canRender = false; };
		if(canRender and: { ~idm[\buf].isNil }) { "No buffer loaded (load a break first).".warn; canRender = false; };

		if(canRender) {
			clock = ~idm[\clock];
			if(clock.isNil) { "No clock (load a break first).".warn; canRender = false; };
		};

		if(canRender) {
			if(clock.isRunning.not) { clock.play; };

			tempo = clock.tempo.max(0.001);
			durSec = (bars * 4 / tempo).max(0.1);

			if(outPath.isNil) {
				outPath = (Platform.userHomeDir +/+ ("SC_IDM_Render_" ++ Date.localtime.stamp ++ ".wav"));
			};

			Routine({
				("[IDM] Recording " ++ bars ++ " bars (" ++ durSec.round(0.01) ++ "s) -> " ++ outPath).postln;

				s.prepareForRecord(outPath);
				s.record;

				SystemClock.sched(durSec, {
					s.stopRecording;
					("[IDM] Saved -> " ++ outPath).postln;
					nil
				});
			}).play(SystemClock);

			result = outPath;
		};

		result
	};

	~idm[\renderBarsDownbeat] = { |bars = 4, outPath, startOffsetBeats = 0.0|
		var clock, startBeat, stopBeat, durBeats;
		var latencySec, latencyBeats, canRender, result;

		canRender = true;
		result = nil;
		if(~idm.isNil) { "IDM not initialized.".warn; canRender = false; };
		if(canRender and: { ~idm[\buf].isNil }) { "No buffer loaded (load a break first).".warn; canRender = false; };

		if(canRender) {
			clock = ~idm[\clock];
			if(clock.isNil) { "No clock (load a break first).".warn; canRender = false; };
		};

		if(canRender) {
			if(clock.isRunning.not) { clock.play; };

			durBeats = (bars.asFloat * 4.0).max(0.25);

			latencySec = (s.latency ? 0.0).asFloat.max(0.0);
			latencyBeats = latencySec * clock.tempo;

			startBeat = clock.nextTimeOnGrid(4);
			startBeat = startBeat + startOffsetBeats;
			stopBeat  = startBeat + durBeats;

			if(outPath.isNil) {
				outPath = (Platform.userHomeDir +/+ ("SC_IDM_Loop_" ++ bars.asInteger ++ "bar_" ++ Date.localtime.stamp ++ ".wav"));
			};

			("[IDM] Arm record (latency-comp): startBeat=" ++ startBeat
				++ " stopBeat=" ++ stopBeat
				++ " latencySec=" ++ latencySec.round(0.001)
				++ " -> " ++ outPath
			).postln;

			s.prepareForRecord(outPath);

			clock.schedAbs(startBeat, {
				if(~idm[\pat].notNil) { ~idm[\pat].stop; ~idm[\pat] = nil; };
				~idm[\play].value;
				nil
			});

			clock.schedAbs(startBeat + latencyBeats, {
				s.record;
				nil
			});

			clock.schedAbs(stopBeat + latencyBeats, {
				s.stopRecording;
				if(~idm[\pat].notNil) { ~idm[\pat].stop; ~idm[\pat] = nil; };
				("[IDM] Saved -> " ++ outPath).postln;
				nil
			});

			result = outPath;
		};

		result
	};

	~idm[\renderFrozen] = { |bars = nil, outPath|
		var useBars, mode, stamp;
		useBars = (bars ? ~idm[\patternBars] ? 4).asInteger.max(1);

		if(~idm[\frozenPattern].isNil or: { ~idm[\frozenPattern].size == 0 }) {
			~idm[\freeze].value(true);
		} {
			~idm[\frozen] = true;
		};

		if(outPath.isNil or: { outPath.asString.stripWhiteSpace.size == 0 }) {
			mode = ~idm[\modeFromInput].value(~idm[\mode]).asString;
			stamp = Date.localtime.stamp;
			outPath = Platform.userHomeDir +/+ (
				"Desktop/idm_frozen_" ++ mode
				++ "_bpm" ++ ((~idm[\bpm] ? 0).round(0.1).asString)
				++ "_seed" ++ (~idm[\seed] ? 0).asString
				++ "_" ++ stamp ++ ".wav"
			);
		};

		~idm[\renderBarsDownbeat].value(useBars, outPath, 0.0)
	};

	~idm[\finalizeSliceEdit] = {
		~idm[\sliceEditVersion] = (~idm[\sliceEditVersion] ? 0) + 1;
		~idm[\overlayCache] = nil;
		~idm[\rebuildQuant].value;
		~idm[\invalidatePattern].value(true);
		~idm[\updateGuiAfterLoad].value;
		~idm[\refreshWaveform].value;
		~idm[\refreshOverlay].value;
	};

	~idm[\splitSelectedSlice] = {
		var cells, offs, idx, frame, gs, ge, newCells, newOffs, oldDisabled;
		cells = ~idm[\cells];
		offs = ~idm[\onsetOffsets];
		if(cells.isNil or: { offs.isNil }) {
			"Load a break first.".warn;
		} {
			idx = (~idm[\selectedSlice] ? 0).asInteger.clip(0, cells.size - 1);
			frame = (~idm[\selectedFrame] ? cells[idx][0]).asInteger;
			gs = cells[idx][0].asInteger;
			ge = cells[idx][1].asInteger;
			frame = frame.clip(gs + 32, ge - 32);
			if(frame <= gs or: { frame >= ge }) {
				"Split point is too close to the slice edge.".warn;
			} {
				oldDisabled = ~idm[\disabledSlices];
				newCells = Array.fill(cells.size + 1, { |i|
					if(i < idx) {
						cells[i]
					} {
						if(i == idx) {
							[gs, frame]
						} {
							if(i == (idx + 1)) { [frame, ge] } { cells[i - 1] }
						}
					}
				});
				newOffs = Array.fill(offs.size + 1, { |i|
					if(i < idx) {
						offs[i]
					} {
						if(i == idx) { offs[idx].min((frame - gs - 1).max(0)) } {
							if(i == (idx + 1)) { 0 } { offs[i - 1] }
						}
					}
				});
				~idm[\cells] = newCells;
				~idm[\onsetOffsets] = newOffs;
				~idm[\disabledSlices] = IdentityDictionary.new;
				oldDisabled.keysValuesDo { |k, v|
					if(v == true) {
						if(k <= idx) { ~idm[\disabledSlices][k] = true } { ~idm[\disabledSlices][k + 1] = true };
					};
				};
				~idm[\selectedSlice] = idx;
				~idm[\finalizeSliceEdit].value;
			};
		};
	};

	~idm[\mergeSelectedSliceNext] = {
		var cells, offs, idx, newCells, newOffs, oldDisabled;
		cells = ~idm[\cells];
		offs = ~idm[\onsetOffsets];
		if(cells.isNil or: { offs.isNil } or: { cells.size < 2 }) {
			"Need at least two slices to merge.".warn;
		} {
			idx = (~idm[\selectedSlice] ? 0).asInteger.clip(0, cells.size - 2);
			oldDisabled = ~idm[\disabledSlices];
			newCells = Array.fill(cells.size - 1, { |i|
				if(i < idx) {
					cells[i]
				} {
					if(i == idx) { [cells[idx][0], cells[idx + 1][1]] } { cells[i + 1] }
				}
			});
			newOffs = Array.fill(offs.size - 1, { |i|
				if(i < idx) { offs[i] } { if(i == idx) { offs[idx] } { offs[i + 1] } }
			});
			~idm[\cells] = newCells;
			~idm[\onsetOffsets] = newOffs;
			~idm[\disabledSlices] = IdentityDictionary.new;
			oldDisabled.keysValuesDo { |k, v|
				if(v == true) {
					if(k < idx) {
						~idm[\disabledSlices][k] = true;
					} {
						if((k == idx) or: { k == (idx + 1) }) {
							~idm[\disabledSlices][idx] = true;
						} {
							~idm[\disabledSlices][k - 1] = true;
						};
					};
				};
			};
			~idm[\selectedSlice] = idx.min(newCells.size - 1);
			~idm[\finalizeSliceEdit].value;
		};
	};

	~idm[\nudgeSelectedOnset] = { |frames = 128|
		var cells, offs, idx, gs, ge, maxOff;
		cells = ~idm[\cells];
		offs = ~idm[\onsetOffsets];
		if(cells.isNil or: { offs.isNil }) {
			"Load a break first.".warn;
		} {
			idx = (~idm[\selectedSlice] ? 0).asInteger.clip(0, cells.size - 1);
			gs = cells[idx][0].asInteger;
			ge = cells[idx][1].asInteger;
			maxOff = (ge - gs - 2).max(0);
			offs[idx] = ((offs[idx] ? 0).asInteger + frames.asInteger).clip(0, maxOff);
			~idm[\finalizeSliceEdit].value;
		};
	};

	~idm[\toggleSelectedSliceDisabled] = {
		var idx;
		if(~idm[\cells].isNil) {
			"Load a break first.".warn;
		} {
			idx = (~idm[\selectedSlice] ? 0).asInteger.clip(0, ~idm[\cells].size - 1);
			if(~idm[\disabledSlices][idx] == true) {
				~idm[\disabledSlices].removeAt(idx);
			} {
				~idm[\disabledSlices][idx] = true;
			};
			~idm[\finalizeSliceEdit].value;
		};
	};

	~idm[\saveSession] = { |path = nil|
		var session, outPath;
		outPath = path ? ~idm[\sessionPath] ? (Platform.userHomeDir +/+ "Desktop/idm_session.scdarchive");
		outPath = ~idm[\normalizePath].value(outPath);
		if(outPath.isNil) {
			"Bad session path.".warn;
			nil
		} {
			session = IdentityDictionary[
				\version -> 1,
				\loadedPath -> ~idm[\loadedPath],
				\mode -> ~idm[\mode],
				\bpm -> ~idm[\bpm],
				\bpmOverride -> ~idm[\bpmOverride],
				\onsetSensitivity -> ~idm[\onsetSensitivity],
				\minSliceBeats -> ~idm[\minSliceBeats],
				\quant -> ~idm[\quant],
				\macros -> ~idm[\copyMacroValues].value,
				\macroLocks -> ~idm[\macroLocks],
				\macroAB -> ~idm[\macroAB],
				\seed -> ~idm[\seed],
				\frozen -> ~idm[\frozen],
				\frozenPattern -> ~idm[\frozenPattern],
				\patternBars -> ~idm[\patternBars],
				\patternVersion -> ~idm[\patternVersion],
				\cells -> ~idm[\cells],
				\onsetOffsets -> ~idm[\onsetOffsets],
				\onsetPeaks -> ~idm[\onsetPeaks],
				\disabledSlices -> ~idm[\disabledSlices],
				\selectedSlice -> ~idm[\selectedSlice]
			];
			session.writeArchive(outPath);
			~idm[\sessionPath] = outPath;
			("[IDM] Session saved -> " ++ outPath).postln;
			outPath
		}
	};

	~idm[\loadSession] = { |path = nil|
		var session, inPath, loaded, savedCells, savedOffsets, savedBpm;
		inPath = path ? ~idm[\sessionPath] ? (Platform.userHomeDir +/+ "Desktop/idm_session.scdarchive");
		inPath = ~idm[\normalizePath].value(inPath);
		if(inPath.isNil or: { File.exists(inPath).not }) {
			("Session file not found: " ++ (inPath ? "nil")).warn;
			nil
		} {
			session = Object.readArchive(inPath);
			if(session.isNil) {
				("Could not read session: " ++ inPath).warn;
				nil
			} {
				~idm[\sessionPath] = inPath;
				loaded = false;
				if(session[\loadedPath].notNil and: { File.exists(session[\loadedPath]) }) {
					~idm[\load].value(session[\loadedPath]);
					loaded = true;
				} {
					("Session audio missing: " ++ (session[\loadedPath] ? "nil")).warn;
				};

				~idm[\mode] = ~idm[\modeFromInput].value(session[\mode] ? ~idm[\mode]);
				~idm[\bpmOverride] = session[\bpmOverride];
				~idm[\onsetSensitivity] = session[\onsetSensitivity] ? ~idm[\onsetSensitivity];
				~idm[\minSliceBeats] = session[\minSliceBeats] ? ~idm[\minSliceBeats];
				~idm[\quant] = session[\quant] ? ~idm[\quant];
				~idm[\macroLocks] = session[\macroLocks] ? ~idm[\macroLocks];
				~idm[\macroAB] = session[\macroAB];
				~idm[\seed] = session[\seed] ? ~idm[\seed];
				~idm[\patternBars] = session[\patternBars] ? ~idm[\patternBars];
				~idm[\patternVersion] = session[\patternVersion] ? ~idm[\patternVersion];
				~idm[\disabledSlices] = session[\disabledSlices] ? IdentityDictionary.new;
				~idm[\selectedSlice] = session[\selectedSlice] ? 0;

				~idm[\applyMacroValues].value(session[\macros], false);

				savedCells = session[\cells];
				savedOffsets = session[\onsetOffsets];
				savedBpm = session[\bpm];
				if(loaded and: { savedCells.notNil and: { savedOffsets.notNil } }) {
					~idm[\cells] = savedCells;
					~idm[\onsetOffsets] = savedOffsets;
					~idm[\onsetPeaks] = session[\onsetPeaks];
					~idm[\bpm] = savedBpm ? ~idm[\bpm];
					if(~idm[\clock].notNil) { try { ~idm[\clock].stop } { } };
					~idm[\clock] = TempoClock.new((~idm[\bpm] ? 120) / 60).permanent_(true);
					~idm[\clock].play;
					~idm[\setBpmStatus].value(~idm[\bpm]);
					~idm[\rebuildQuant].value;
				};

				~idm[\frozenPattern] = session[\frozenPattern];
				~idm[\frozen] = (session[\frozen] == true) and: { ~idm[\frozenPattern].notNil };
				~idm[\timelineDirty] = true;
				~idm[\overlayCache] = nil;
				~idm[\updateMacroViews].value;
				~idm[\updateGuiAfterLoad].value;
				~idm[\refreshWaveform].value;
				~idm[\refreshOverlay].value;
				("[IDM] Session loaded -> " ++ inPath).postln;
				session
			}
		}
	};

	// =====================================================
	// GUI
	// =====================================================
	~idm[\openUI] = {
		var win, nav, content;
		var buildWavePage, buildGeneratePage, buildParamsPage, buildAudioPage, clearContent, makeTabButton;
			var audioDevicesView;

			if(~idm[\win].notNil and: { ~idm[\win].isClosed.not }) {
				try { ~idm[\win].close } { };
				~idm[\win] = nil;
			};

		~idm[\macroViews] = IdentityDictionary.new;

		win = Window("IDM Breakbeat Slicer", Rect(80, 60, 1320, 760)).front;
		win.background = Color(0.12, 0.12, 0.12);
		~idm[\win] = win;

		win.onClose_({
			if(~idm.notNil) {
				~idm[\win] = nil;
				if(~idm[\waveFile].notNil) {
					try { ~idm[\waveFile].close } { };
					~idm[\waveFile] = nil;
				};
				if(~idm[\guiUpdateTask].notNil) {
					try { ~idm[\guiUpdateTask].stop } { };
					~idm[\guiUpdateTask] = nil;
				};
			};
		});

		nav = CompositeView(win, Rect(10, 10, 150, 740));
		nav.background = Color(0.10, 0.10, 0.10);

		content = CompositeView(win, Rect(170, 10, 1140, 740));
		content.background = Color(0.16, 0.16, 0.16);

		clearContent = {
			if(content.children.notNil) {
				content.children.copy.do { |child|
					try { child.visible = false } { };
					try { child.remove } { };
				};
			};

			~idm[\waveView] = nil;
			~idm[\overlayView] = nil;
			~idm[\timelineView] = nil;
			~idm[\pathField] = nil;
			~idm[\previewField] = nil;
			~idm[\seedField] = nil;
			~idm[\patternBarsField] = nil;
			~idm[\mutateField] = nil;
			~idm[\bpmOverrideField] = nil;
			~idm[\onsetSensitivitySlider] = nil;
			~idm[\onsetSensitivityBox] = nil;
			~idm[\minSlicePop] = nil;
			~idm[\forceSoundToggle] = nil;
			~idm[\modePop] = nil;
			~idm[\bpmText] = nil;
			~idm[\cellsText] = nil;
			~idm[\peaksText] = nil;
			~idm[\sliceText] = nil;
			~idm[\statusText] = nil;
			~idm[\renderBarsField] = nil;
			~idm[\renderOffsetField] = nil;
			~idm[\renderPathField] = nil;
			~idm[\exportBarsField] = nil;
			~idm[\exportPathField] = nil;
			~idm[\devicePop] = nil;
			~idm[\quantEnableToggle] = nil;
			~idm[\quantModePop] = nil;
			~idm[\quantGridPop] = nil;
			~idm[\quantKeepOrderToggle] = nil;
			~idm[\quantSwingSlider] = nil;
			~idm[\quantSwingBox] = nil;
			~idm[\quantSummaryText] = nil;
			~idm[\sessionPathField] = nil;
			~idm[\presetPop] = nil;
			~idm[\macroViews] = IdentityDictionary.new;
		};

		buildWavePage = {
			clearContent.value;

			StaticText(content, Rect(16, 12, 240, 24))
				.string_("Wave / Transport")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 16).boldVariant);

			~idm[\pathField] = TextField(content, Rect(16, 46, 760, 24))
				.string_("");

			Button(content, Rect(786, 46, 90, 24))
				.states_([["Browse"]])
				.action_({
					~idm[\chooseFile].value;
				});

			Button(content, Rect(886, 46, 70, 24))
				.states_([["Load"]])
				.action_({
					~idm[\load].value(~idm[\pathField].string);
				});

			Button(content, Rect(966, 46, 70, 24))
				.states_([["Last"]])
				.action_({
					var p = ~idm[\loadLastPath].value;
					if(p.notNil) {
						~idm[\pathField].string = p;
						~idm[\load].value(p);
					} {
						"No last path saved yet.".warn;
					};
				});

			Button(content, Rect(16, 84, 70, 24))
				.states_([["Play"]])
				.action_({
					~idm[\play].value;
				});

			Button(content, Rect(96, 84, 70, 24))
				.states_([["Stop"]])
				.action_({
					~idm[\stop].value;
				});

			StaticText(content, Rect(186, 86, 60, 20))
				.string_("Preview")
				.stringColor_(Color.white);

			~idm[\previewField] = NumberBox(content, Rect(242, 84, 60, 22))
				.value_(0)
				.clipLo_(0);

			Button(content, Rect(312, 84, 70, 24))
				.states_([["Preview"]])
				.action_({
					~idm[\preview].value(~idm[\previewField].value.asInteger);
				});

			~idm[\forceSoundToggle] = CheckBox(content, Rect(408, 86, 20, 20))
				.value_((~idm[\forceHits] == true).if(1, 0))
				.action_({ |cb|
					~idm[\forceHits] = ~idm[\isChecked].value(cb.value);
				});

			StaticText(content, Rect(432, 86, 120, 20))
				.string_("Force Sound")
				.stringColor_(Color.white);

			StaticText(content, Rect(570, 86, 50, 20))
				.string_("Mode")
				.stringColor_(Color.white);

			~idm[\modePop] = PopUpMenu(content, Rect(618, 84, 120, 22))
				.items_(["sync", "free"])
				.value_(~idm[\modeIndex].value(~idm[\mode]))
				.action_({ |pm|
					~idm[\mode] = ~idm[\modeFromIndex].value(pm.value);
				});

			~idm[\bpmText] = StaticText(content, Rect(760, 86, 120, 20))
				.string_("BPM: -")
				.stringColor_(Color.white);

			~idm[\cellsText] = StaticText(content, Rect(850, 86, 120, 20))
				.string_("Cells: 0")
				.stringColor_(Color.white);

			~idm[\peaksText] = StaticText(content, Rect(940, 86, 120, 20))
				.string_("Peaks: 0")
				.stringColor_(Color.white);

			~idm[\sliceText] = StaticText(content, Rect(16, 116, 220, 20))
				.string_("Slice: 0 | Step: 0")
				.stringColor_(Color.white);

			~idm[\statusText] = StaticText(content, Rect(250, 116, 820, 20))
				.string_("Status: Ready")
				.stringColor_(Color.white);

			// ---------------- QUANT CONTROLS
			StaticText(content, Rect(16, 146, 220, 20))
				.string_("Slice Quantization")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 14).boldVariant);

			~idm[\quantEnableToggle] = CheckBox(content, Rect(16, 172, 20, 20))
				.value_((~idm[\quant][\enabled] == true).if(1, 0))
				.action_({ |cb|
					~idm[\quant][\enabled] = ~idm[\isChecked].value(cb.value);
					~idm[\rebuildQuant].value;
				});

			StaticText(content, Rect(40, 172, 54, 20))
				.string_("Enable")
				.stringColor_(Color.white);

			StaticText(content, Rect(110, 172, 42, 20))
				.string_("Mode")
				.stringColor_(Color.white);

			~idm[\quantModePop] = PopUpMenu(content, Rect(150, 170, 110, 22))
				.items_(["nearest", "forward", "backward"])
				.value_(~idm[\quantModeIndex].value(~idm[\quant][\mode]))
				.action_({ |pm|
					~idm[\quant][\mode] = ~idm[\quantModeFromIndex].value(pm.value);
					~idm[\rebuildQuant].value;
				});

			StaticText(content, Rect(278, 172, 36, 20))
				.string_("Grid")
				.stringColor_(Color.white);

			~idm[\quantGridPop] = PopUpMenu(content, Rect(312, 170, 80, 22))
				.items_(["1/8", "1/16", "1/32"])
				.value_(~idm[\quantGridIndex].value(~idm[\quant][\gridDiv]))
				.action_({ |pm|
					var div;
					div = [8, 16, 32][pm.value];
					~idm[\quant][\gridDiv] = div;
					~idm[\rebuildQuant].value;
				});

			~idm[\quantKeepOrderToggle] = CheckBox(content, Rect(410, 172, 20, 20))
				.value_((~idm[\quant][\keepOrder] == true).if(1, 0))
				.action_({ |cb|
					~idm[\quant][\keepOrder] = ~idm[\isChecked].value(cb.value);
					~idm[\rebuildQuant].value;
				});

			StaticText(content, Rect(434, 172, 120, 20))
				.string_("Keep Order")
				.stringColor_(Color.white);

			StaticText(content, Rect(570, 172, 42, 20))
				.string_("Swing")
				.stringColor_(Color.white);

			~idm[\quantSwingSlider] = Slider(content, Rect(614, 174, 180, 16))
				.value_(~idm[\quant][\swing] ? 0.0)
				.action_({ |sl|
					var v;
					v = sl.value.clip(0, 0.95);
					~idm[\quant][\swing] = v;
					if(~idm[\quantSwingBox].notNil) {
						~idm[\quantSwingBox].value = v;
					};
					~idm[\rebuildQuant].value;
				});

			~idm[\quantSwingBox] = NumberBox(content, Rect(802, 170, 70, 22))
				.value_(~idm[\quant][\swing] ? 0.0)
				.action_({ |nb|
					var v;
					v = nb.value.clip(0, 0.95);
					~idm[\quant][\swing] = v;
					if(~idm[\quantSwingSlider].notNil) {
						~idm[\quantSwingSlider].value = v;
					};
					~idm[\rebuildQuant].value;
				});

			Button(content, Rect(884, 170, 150, 22))
				.states_([["Rebuild Quant"]])
				.action_({
					~idm[\rebuildQuant].value;
				});

			~idm[\quantSummaryText] = StaticText(content, Rect(16, 198, 1040, 18))
				.string_(~idm[\quantSummary] ? "")
				.stringColor_(Color.gray(0.85));

			StaticText(content, Rect(16, 224, 520, 26))
				.string_("Waveform / Current Slice / Onset / Quant Grid")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 14).boldVariant);

			~idm[\waveView] = UserView(content, Rect(16, 258, 1090, 242));
			~idm[\waveView].background = Color.black;
			~idm[\waveView].clearOnRefresh = true;
			~idm[\overlayView] = ~idm[\waveView];
			~idm[\waveView].drawFunc = {
				var cells, totalFrames, bounds, width, height, cache, curIdx;
				var xs, endXs, onsetXs, peakXs, quantXs, x1, x2, onX;
				var wavePairs, centerY, ampScale;

				cells = ~idm[\cells];
				totalFrames = ~idm[\sourceFrames] ? if(~idm[\sourceMono].notNil) { ~idm[\sourceMono].size } { 0 };

				bounds = ~idm[\waveView].bounds;
				width = bounds.width;
				height = bounds.height;

				Pen.fillColor = Color.black;
				Pen.addRect(Rect(0, 0, width, height));
				Pen.fill;

				if(totalFrames > 0) {
					cache = ~idm[\overlayCache];
					if(cache.isNil or: { cache[\width] != width } or: { cache[\totalFrames] != totalFrames }) {
						cache = ~idm[\rebuildOverlayCache].value(width);
					};

					if(cache.notNil) {
						wavePairs = cache[\wavePairs];
						if(wavePairs.notNil) {
							centerY = height * 0.48;
							ampScale = height * 0.42;
							Pen.width = 1;
							Pen.strokeColor = Color(0.86, 0.86, 0.86, 0.95);
							wavePairs.do { |pair, x|
								var y1, y2;
								y1 = (centerY - ((pair[1] ? 0.0) * ampScale)).clip(0, height);
								y2 = (centerY - ((pair[0] ? 0.0) * ampScale)).clip(0, height);
								Pen.moveTo(Point(x, y1));
								Pen.lineTo(Point(x, y2.max(y1 + 1)));
							};
							Pen.stroke;
						};
					};
				};

				if(cells.notNil and: { totalFrames > 0 }) {
					cache = ~idm[\overlayCache];
					if(cache.notNil) {
						xs = cache[\cellXs];
						endXs = cache[\cellEndXs];
						onsetXs = cache[\onsetXs];
						peakXs = cache[\peakXs];
						quantXs = cache[\quantXs];

						if(quantXs.notNil) {
							Pen.width = 1;
							Pen.strokeColor = Color(0.1, 0.9, 0.6, 0.18);
							quantXs.do { |x|
								Pen.moveTo(Point(x, 0));
								Pen.lineTo(Point(x, height));
							};
							Pen.stroke;
						};

						Pen.width = 1;
						Pen.strokeColor = Color(1, 1, 1, 0.18);

						xs.do { |x|
							Pen.moveTo(Point(x, 0));
							Pen.lineTo(Point(x, height));
						};
						Pen.stroke;

						if(onsetXs.notNil) {
							Pen.strokeColor = Color(0.1, 0.8, 1.0, 0.35);
							onsetXs.do { |x|
								Pen.moveTo(Point(x, 0));
								Pen.lineTo(Point(x, height));
							};
							Pen.stroke;
						};

						if(peakXs.notNil) {
							Pen.strokeColor = Color(1.0, 0.4, 0.2, 0.18);
							peakXs.do { |x|
								Pen.moveTo(Point(x, height * 0.75));
								Pen.lineTo(Point(x, height));
							};
							Pen.stroke;
						};

						curIdx = (~idm[\currentSlice] ? 0).clip(0, cells.size - 1);
						x1 = xs[curIdx];
						x2 = endXs[curIdx];
						onX = if(onsetXs.notNil) { onsetXs[curIdx] } { x1 };

						if(x1.notNil and: { x2.notNil }) {
							Pen.fillColor = Color(1.0, 0.8, 0.1, 0.18);
							Pen.addRect(Rect(x1, 0, (x2 - x1).max(1), height));
							Pen.fill;

							Pen.strokeColor = Color(1.0, 0.85, 0.2, 0.85);
							Pen.width = 2;
							Pen.moveTo(Point(x1, 0)); Pen.lineTo(Point(x1, height));
							Pen.moveTo(Point(x2, 0)); Pen.lineTo(Point(x2, height));
							Pen.stroke;

							Pen.strokeColor = Color(0.0, 1.0, 1.0, 0.9);
							Pen.moveTo(Point(onX, 0));
							Pen.lineTo(Point(onX, height));
							Pen.stroke;
						};
					};
				};
			};

			~idm[\waveView].mouseDownAction = { |view, x, y, modifiers, buttonNumber, clickCount|
				var frames, frac, frame, idx;
				if(~idm[\cells].notNil and: { ~idm[\cells].size > 0 }) {
					frames = ~idm[\sourceFrames] ? if(~idm[\sourceMono].notNil) { ~idm[\sourceMono].size } { 0 };
					if(frames > 0) {
						frac = (x / view.bounds.width).clip(0, 1);
						frame = (frac * frames).asInteger;
						idx = (~idm[\cells].detectIndex { |cell|
							(frame >= cell[0]) and: { frame < cell[1] }
						}) ? 0;
						~idm[\selectedSlice] = idx;
						~idm[\selectedFrame] = frame;
						~idm[\previewField].value = idx;
						~idm[\preview].value(idx);
					};
				};
			};

			StaticText(content, Rect(16, 520, 180, 20))
				.string_("Render / Export")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 14).boldVariant);

			StaticText(content, Rect(16, 548, 40, 20))
				.string_("Bars")
				.stringColor_(Color.white);

			~idm[\renderBarsField] = NumberBox(content, Rect(56, 546, 60, 22))
				.value_(8)
				.clipLo_(1);

			StaticText(content, Rect(132, 548, 80, 20))
				.string_("Offset")
				.stringColor_(Color.white);

			~idm[\renderOffsetField] = NumberBox(content, Rect(188, 546, 60, 22))
				.value_(0);

			~idm[\renderPathField] = TextField(content, Rect(266, 546, 660, 22))
				.string_(Platform.userHomeDir +/+ "Desktop/idm_loop_render.wav");

			Button(content, Rect(940, 546, 166, 22))
				.states_([["Render Downbeat"]])
				.action_({
					~idm[\renderBarsDownbeat].value(
						~idm[\renderBarsField].value.asInteger.max(1),
						~idm[\renderPathField].string,
						~idm[\renderOffsetField].value.asFloat
					);
				});

			StaticText(content, Rect(16, 582, 90, 20))
				.string_("Export Path")
				.stringColor_(Color.white);

			~idm[\exportPathField] = TextField(content, Rect(90, 580, 836, 22))
				.string_(Platform.userHomeDir +/+ "Desktop/idm_quant_timeline.wav");

			Button(content, Rect(940, 580, 166, 22))
				.states_([["Export Quant Timeline"]])
				.action_({
					~idm[\exportQuantTimeline].value(
						~idm[\renderBarsField].value.asInteger.max(1),
						~idm[\exportPathField].string
					);
				});

			~idm[\updateGuiAfterLoad].value;
			~idm[\refreshWaveform].value;
			~idm[\refreshOverlay].value;
		};

		buildGeneratePage = {
			clearContent.value;

			StaticText(content, Rect(16, 12, 320, 24))
				.string_("Generate / Freeze")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 16).boldVariant);

			StaticText(content, Rect(16, 46, 44, 20))
				.string_("Seed")
				.stringColor_(Color.white);

			~idm[\seedField] = NumberBox(content, Rect(58, 44, 82, 22))
				.value_((~idm[\seed] ? 0).asInteger)
				.action_({ |nb|
					~idm[\seed] = nb.value.asInteger;
					~idm[\invalidatePattern].value(false);
				});

			StaticText(content, Rect(156, 46, 36, 20))
				.string_("Bars")
				.stringColor_(Color.white);

			~idm[\patternBarsField] = NumberBox(content, Rect(194, 44, 54, 22))
				.value_((~idm[\patternBars] ? 4).asInteger.max(1))
				.clipLo_(1)
				.action_({ |nb|
					~idm[\patternBars] = nb.value.asInteger.max(1);
					~idm[\invalidatePattern].value(false);
				});

			Button(content, Rect(266, 44, 100, 24))
				.states_([["Regenerate"]])
				.action_({
					~idm[\seed] = ~idm[\seedField].value.asInteger;
					~idm[\patternBars] = ~idm[\patternBarsField].value.asInteger.max(1);
					~idm[\regen].value;
				});

			Button(content, Rect(376, 44, 78, 24))
				.states_([["Freeze"]])
				.action_({
					~idm[\seed] = ~idm[\seedField].value.asInteger;
					~idm[\patternBars] = ~idm[\patternBarsField].value.asInteger.max(1);
					~idm[\freeze].value(false);
				});

			Button(content, Rect(464, 44, 88, 24))
				.states_([["Unfreeze"]])
				.action_({ ~idm[\unfreeze].value; });

			StaticText(content, Rect(570, 46, 50, 20))
				.string_("Mutate")
				.stringColor_(Color.white);

			~idm[\mutateField] = NumberBox(content, Rect(624, 44, 58, 22))
				.value_(0.25)
				.clipLo_(0)
				.clipHi_(1);

			Button(content, Rect(692, 44, 80, 24))
				.states_([["Mutate"]])
				.action_({ ~idm[\mutate].value(~idm[\mutateField].value.asFloat); });

			StaticText(content, Rect(16, 84, 260, 20))
				.string_("Generated Pattern Timeline")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 14).boldVariant);

			~idm[\timelineView] = UserView(content, Rect(16, 112, 1090, 110));
			~idm[\timelineView].background = Color(0.05, 0.05, 0.05);
			~idm[\timelineView].clearOnRefresh = true;
			~idm[\timelineView].drawFunc = {
				var pattern, bounds, width, height, totalBeats, selected;
				pattern = ~idm[\frozenPattern];
				bounds = ~idm[\timelineView].bounds;
				width = bounds.width;
				height = bounds.height;

				Pen.fillColor = Color(0.04, 0.04, 0.04);
				Pen.addRect(Rect(0, 0, width, height));
				Pen.fill;

				totalBeats = ~idm[\patternLengthBeats].value.max(0.001);
				Pen.strokeColor = Color(1, 1, 1, 0.10);
				((~idm[\patternBars] ? 4).asInteger.max(1) + 1).do { |bar|
					var x;
					x = (bar * 4.0 / totalBeats) * width;
					Pen.moveTo(Point(x, 0));
					Pen.lineTo(Point(x, height));
				};
				Pen.stroke;

				if(pattern.notNil) {
					selected = (~idm[\selectedEvent] ? 0).asInteger;
					pattern.do { |ev, i|
						var x, w, y, h, col;
						x = (ev[\beat].asFloat / totalBeats) * width;
						w = (ev[\dur].asFloat.max(0.001) / totalBeats * width).max(2);
						y = 12;
						h = height - 24;
						col = if(ev[\isRest] == true) {
							Color(0.20, 0.20, 0.20, 0.70)
						} {
							if(ev[\rate].asFloat < 0) {
								Color(0.95, 0.35, 0.22, 0.82)
							} {
								if(ev[\isGhost] == true) {
									Color(0.40, 0.70, 1.00, 0.68)
								} {
									Color(0.15, 0.85, 0.55, 0.78)
								}
							}
						};
						Pen.fillColor = col;
						Pen.addRect(Rect(x, y, w, h));
						Pen.fill;
						if(ev[\locked] == true) {
							Pen.strokeColor = Color(1.0, 0.85, 0.2, 0.95);
							Pen.width = 1;
							Pen.addRect(Rect(x + 1, y + 1, (w - 2).max(1), (h - 2).max(1)));
							Pen.stroke;
						};
						if(i == selected) {
							Pen.strokeColor = Color.white;
							Pen.width = 2;
							Pen.addRect(Rect(x, y, w, h));
							Pen.stroke;
						};
					};
				} {
					Pen.stringAtPoint("Press Regenerate after loading a loop.", Point(18, 44), Font("Helvetica", 14), Color.gray(0.8));
				};
			};

			~idm[\timelineView].mouseDownAction = { |view, x, y, modifiers, buttonNumber, clickCount|
				var pattern, totalBeats, beat, found;
				pattern = ~idm[\frozenPattern];
				if(pattern.notNil and: { pattern.size > 0 }) {
					totalBeats = ~idm[\patternLengthBeats].value.max(0.001);
					beat = (x / view.bounds.width).clip(0, 1) * totalBeats;
					found = pattern.detectIndex { |ev|
						(beat >= ev[\beat].asFloat) and: { beat < (ev[\beat].asFloat + ev[\dur].asFloat) }
					};
					if(found.notNil) {
						~idm[\selectedEvent] = found;
						~idm[\selectedSlice] = pattern[found][\idx].asInteger;
						if(pattern[found][\isRest] != true) { ~idm[\preview].value(~idm[\selectedSlice]) };
						~idm[\refreshOverlay].value;
					};
				};
			};

			Button(content, Rect(16, 236, 92, 24))
				.states_([["Rest / Hit"]])
				.action_({ ~idm[\editSelectedEvent].value(\toggleRest) });

			Button(content, Rect(118, 236, 88, 24))
				.states_([["Lock Slice"]])
				.action_({ ~idm[\editSelectedEvent].value(\lockSlice) });

			Button(content, Rect(216, 236, 104, 24))
				.states_([["Replace Slice"]])
				.action_({ ~idm[\editSelectedEvent].value(\replaceSlice) });

			Button(content, Rect(340, 236, 116, 24))
				.states_([["Render Frozen"]])
				.action_({
					~idm[\renderFrozen].value((~idm[\patternBars] ? 4).asInteger.max(1), nil);
				});

			StaticText(content, Rect(16, 288, 260, 20))
				.string_("Slice / BPM Correction")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 14).boldVariant);

			StaticText(content, Rect(16, 318, 100, 20))
				.string_("BPM Override")
				.stringColor_(Color.white);

			~idm[\bpmOverrideField] = NumberBox(content, Rect(118, 316, 64, 22))
				.value_(~idm[\bpmOverride] ? 0)
				.action_({ |nb|
					var v;
					v = nb.value.asFloat;
					~idm[\bpmOverride] = (v > 0).if(v, nil);
				});

			Button(content, Rect(190, 316, 54, 24))
				.states_([["Half"]])
				.action_({
					~idm[\bpmOverride] = ((~idm[\bpm] ? 120).asFloat / 2).max(1);
					~idm[\reanalyzeLoaded].value(true, true);
				});

			Button(content, Rect(250, 316, 60, 24))
				.states_([["Double"]])
				.action_({
					~idm[\bpmOverride] = ((~idm[\bpm] ? 120).asFloat * 2).max(1);
					~idm[\reanalyzeLoaded].value(true, true);
				});

			StaticText(content, Rect(330, 318, 70, 20))
				.string_("Sensitivity")
				.stringColor_(Color.white);

			~idm[\onsetSensitivitySlider] = Slider(content, Rect(402, 320, 150, 16))
				.value_((~idm[\onsetSensitivity] ? 0.15).linlin(0.02, 0.5, 0, 1).clip(0, 1))
				.action_({ |sl|
					var v;
					v = sl.value.linlin(0, 1, 0.02, 0.5);
					~idm[\onsetSensitivity] = v;
					if(~idm[\onsetSensitivityBox].notNil) { ~idm[\onsetSensitivityBox].value = v };
				});

			~idm[\onsetSensitivityBox] = NumberBox(content, Rect(560, 316, 58, 22))
				.value_(~idm[\onsetSensitivity] ? 0.15)
				.action_({ |nb|
					var v;
					v = nb.value.asFloat.clip(0.02, 0.5);
					~idm[\onsetSensitivity] = v;
					if(~idm[\onsetSensitivitySlider].notNil) { ~idm[\onsetSensitivitySlider].value = v.linlin(0.02, 0.5, 0, 1) };
				});

			StaticText(content, Rect(638, 318, 70, 20))
				.string_("Min Slice")
				.stringColor_(Color.white);

			~idm[\minSlicePop] = PopUpMenu(content, Rect(708, 316, 88, 22))
				.items_(["1/64", "1/32", "1/16", "1/8"])
				.value_([0.0625, 0.125, 0.25, 0.5].indexOfEqual((~idm[\minSliceBeats] ? 0.25).asFloat) ? 2)
				.action_({ |pm|
					~idm[\minSliceBeats] = [0.0625, 0.125, 0.25, 0.5][pm.value];
				});

			Button(content, Rect(808, 316, 96, 24))
				.states_([["Re-analyze"]])
				.action_({
					var v;
					v = ~idm[\bpmOverrideField].value.asFloat;
					~idm[\bpmOverride] = (v > 0).if(v, nil);
					~idm[\reanalyzeLoaded].value(true, true);
				});

			Button(content, Rect(16, 354, 84, 24))
				.states_([["Split Here"]])
				.action_({ ~idm[\splitSelectedSlice].value });

			Button(content, Rect(110, 354, 88, 24))
				.states_([["Merge Next"]])
				.action_({ ~idm[\mergeSelectedSliceNext].value });

			Button(content, Rect(208, 354, 80, 24))
				.states_([["Onset -"]])
				.action_({ ~idm[\nudgeSelectedOnset].value((~idm[\hop] / -4).asInteger) });

			Button(content, Rect(298, 354, 80, 24))
				.states_([["Onset +"]])
				.action_({ ~idm[\nudgeSelectedOnset].value((~idm[\hop] / 4).asInteger) });

			Button(content, Rect(388, 354, 110, 24))
				.states_([["Disable Slice"]])
				.action_({ ~idm[\toggleSelectedSliceDisabled].value });

			StaticText(content, Rect(16, 420, 220, 20))
				.string_("Session Save / Recall")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 14).boldVariant);

			~idm[\sessionPathField] = TextField(content, Rect(16, 452, 760, 22))
				.string_(~idm[\sessionPath] ? (Platform.userHomeDir +/+ "Desktop/idm_session.scdarchive"));

			Button(content, Rect(790, 452, 120, 22))
				.states_([["Save Session"]])
				.action_({ ~idm[\saveSession].value(~idm[\sessionPathField].string); });

			Button(content, Rect(920, 452, 120, 22))
				.states_([["Load Session"]])
				.action_({ ~idm[\loadSession].value(~idm[\sessionPathField].string); });

			~idm[\updateGuiAfterLoad].value;
			~idm[\refreshOverlay].value;
		};

		buildParamsPage = {
			var patternCol1, patternCol2, fxCol1, fxCol2, drawMacroColumn;
			var rowH, patternTopY, fxTopY, leftX, rightX;
			var sliderW, valueW, zeroW, lockW, labelW, rangeW;

			clearContent.value;

			StaticText(content, Rect(16, 12, 240, 24))
				.string_("Realtime Params")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 16).boldVariant);

			StaticText(content, Rect(16, 40, 700, 18))
				.string_("These update ~idm[\\setMacro] live while the pattern is running.")
				.stringColor_(Color.gray(0.85));

			StaticText(content, Rect(16, 70, 46, 20))
				.string_("Preset")
				.stringColor_(Color.white);

			~idm[\presetPop] = PopUpMenu(content, Rect(68, 68, 176, 22))
				.items_(~idm[\presetNames])
				.value_(0);

			Button(content, Rect(254, 68, 94, 24))
				.states_([["Apply Preset"]])
				.action_({
					~idm[\applyPreset].value(~idm[\presetNames][~idm[\presetPop].value]);
				});

			Button(content, Rect(360, 68, 118, 24))
				.states_([["Randomize"]])
				.action_({
					~idm[\randomizeParams].value;
				});

			Button(content, Rect(490, 68, 106, 24))
				.states_([["Capture A/B"]])
				.action_({
					~idm[\captureAB].value;
				});

			Button(content, Rect(606, 68, 86, 24))
				.states_([["Swap A/B"]])
				.action_({
					~idm[\swapAB].value;
				});

			StaticText(content, Rect(710, 70, 360, 20))
				.string_("Locks protect params from presets and randomize.")
				.stringColor_(Color.gray(0.78));

			patternCol1 = [
				\burst, \glitch, \ghost, \repeats, \density, \panwidth, \reverse
			];
			patternCol2 = [
				\ratespread, \tight, \swing, \fill, \chaos, \env, \humanize
			];
			fxCol1 = [\filter, \res, \drive];
			fxCol2 = [\crush, \comb, \delay];

			rowH = 46;
			patternTopY = 132;
			fxTopY = 524;

			leftX = 20;
			rightX = 570;

			labelW = 110;
			rangeW = 90;
			sliderW = 230;
			valueW = 64;
			zeroW = 34;
			lockW = 20;

			~idm[\macroViews] = IdentityDictionary.new;

			drawMacroColumn = { |colNames, baseX, startY|
				colNames.do { |name, i|
					var y, spec, lo, hi, label, rangeTxt, slider, valBox, zeroBtn, lockBtn;

					spec = ~idm[\macroSpec][name] ? [0, 1];
					lo = spec[0];
					hi = spec[1];
					y = startY + (i * rowH);

					label = StaticText(content, Rect(baseX, y, labelW, 18))
						.string_(name.asString)
						.stringColor_(Color.white);

					rangeTxt = StaticText(content, Rect(baseX + 118, y, rangeW, 18))
						.string_(lo.asString ++ "..." ++ hi.asString)
						.stringColor_(Color.gray(0.7));

					slider = Slider(content, Rect(baseX, y + 24, sliderW, 18))
						.value_(~idm[\getMacro].value(name).linlin(lo, hi, 0, 1))
						.action_({ |sl|
							var mapped;
							mapped = sl.value.linlin(0, 1, lo, hi);
							~idm[\setMacro].value(name, mapped);
						});

					valBox = NumberBox(content, Rect(baseX + sliderW + 12, y + 22, valueW, 20))
						.value_(~idm[\getMacro].value(name))
						.action_({ |nb|
							~idm[\setMacro].value(name, nb.value);
						});

					zeroBtn = Button(content, Rect(baseX + sliderW + 12 + valueW + 8, y + 22, zeroW, 20))
						.states_([["0", Color.white, Color(0.25, 0.25, 0.25)]])
						.action_({
							~idm[\setMacro].value(name, 0);
						});

					lockBtn = CheckBox(content, Rect(baseX + sliderW + 12 + valueW + 8 + zeroW + 8, y + 22, lockW, 20))
						.value_((~idm[\macroLocks][name] == true).if(1, 0))
						.action_({ |cb|
							~idm[\setMacroLock].value(name, cb.value);
						});

					~idm[\macroViews][name] = (
						label: label,
						range: rangeTxt,
						slider: slider,
						value: valBox,
						zero: zeroBtn,
						lock: lockBtn
					);
				};
			};

			StaticText(content, Rect(leftX, 108, 220, 20))
				.string_("Core Rhythm")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 13).boldVariant);

			StaticText(content, Rect(rightX, 108, 220, 20))
				.string_("Motion / Variation")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 13).boldVariant);

			drawMacroColumn.value(patternCol1, leftX, patternTopY);
			drawMacroColumn.value(patternCol2, rightX, patternTopY);

			StaticText(content, Rect(leftX, 474, 220, 20))
				.string_("IDM FX Layer")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 13).boldVariant);

			StaticText(content, Rect(leftX + 120, 476, 780, 18))
				.string_("Per-hit filter, resonance, drive, bitcrush, comb, and delay.")
				.stringColor_(Color.gray(0.78));

			drawMacroColumn.value(fxCol1, leftX, fxTopY);
			drawMacroColumn.value(fxCol2, rightX, fxTopY);

			~idm[\updateMacroViews].value;
			~idm[\appDo].value({ content.refresh; });
		};

		buildAudioPage = {
			var deviceNames, deviceListString, defaultDevice, defaultIndex;

			clearContent.value;

			StaticText(content, Rect(16, 12, 240, 24))
				.string_("Audio")
				.stringColor_(Color.white)
				.font_(Font("Helvetica", 16).boldVariant);

			StaticText(content, Rect(16, 46, 540, 18))
				.string_("Choose an output device, then reboot the server to apply it.")
				.stringColor_(Color.gray(0.85));

			defaultDevice = "MacBook Air Speakers";
			deviceNames = ServerOptions.devices ? [defaultDevice];
			defaultIndex = deviceNames.indexOfEqual(defaultDevice) ? 0;
			deviceListString = { |names|
				(names ? [defaultDevice]).collect { |name, i|
					(i + 1).asString ++ ". " ++ name
				}.join("\n")
			};

			StaticText(content, Rect(16, 88, 140, 20))
				.string_("Output Device")
				.stringColor_(Color.white);

			~idm[\devicePop] = PopUpMenu(content, Rect(16, 114, 420, 24))
				.items_(deviceNames)
				.value_(defaultIndex);

			Button(content, Rect(452, 114, 90, 24))
				.states_([["Refresh"]])
				.action_({
					var names, idx;
					names = ServerOptions.devices ? [defaultDevice];
					idx = names.indexOfEqual(defaultDevice) ? 0;
					~idm[\devicePop].items = names;
					~idm[\devicePop].value = idx;
					if(audioDevicesView.notNil) {
						audioDevicesView.string = deviceListString.value(names);
					};
				});

			Button(content, Rect(556, 114, 170, 24))
				.states_([["Set + Reboot Server"]])
				.action_({
					var sel = ~idm[\devicePop].items[~idm[\devicePop].value];
					if(sel.notNil) {
						s.options.outDevice = sel;
						("[IDM] Setting outDevice -> " ++ sel).postln;
						s.reboot;
					};
				});

			StaticText(content, Rect(16, 164, 800, 20))
				.string_("Current available devices:")
				.stringColor_(Color.white);

			audioDevicesView = TextView(content, Rect(16, 190, 520, 170))
				.string_(deviceListString.value(deviceNames))
				.editable_(false)
				.background_(Color(0.10, 0.10, 0.10))
				.stringColor_(Color.white);
		};

		makeTabButton = { |parent, label, y, func|
			Button(parent, Rect(10, y, 130, 32))
				.states_([
					[label, Color.white, Color(0.22, 0.22, 0.22)]
				])
				.action_({
					func.value;
				});
		};

		StaticText(nav, Rect(10, 10, 120, 24))
			.string_("Sections")
			.stringColor_(Color.white)
			.font_(Font("Helvetica", 15).boldVariant);

		~idm[\showWavePage] = { buildWavePage.value; };
		~idm[\showGeneratePage] = { buildGeneratePage.value; };
		~idm[\showParamsPage] = { buildParamsPage.value; };
		~idm[\showAudioPage] = { buildAudioPage.value; };

		makeTabButton.value(nav, "Wave / Transport", 50, { buildWavePage.value; });
		makeTabButton.value(nav, "Generate", 90, { buildGeneratePage.value; });
		makeTabButton.value(nav, "Params", 130, { buildParamsPage.value; });
		makeTabButton.value(nav, "Audio", 170, { buildAudioPage.value; });

		buildWavePage.value;

		~idm[\setStatus].value("GUI ready.");

		win.front;
		win
	};

	// =====================================================
	// CLI
	// =====================================================
	~idm[\help] = {
		"".postln;
		"================ IDM CLI ================".postln;
		"Transport:".postln;
		"  load <path> | last | loadlast | play | stop | preview <i> | ui".postln;
		"Groove modes:".postln;
		"  mode sync | mode free   (aliases: grid | chaos)".postln;
		"Generation:".postln;
		"  seed <int> | regen | freeze | unfreeze | mutate <0..1>".postln;
		"Macros:".postln;
		"  set <macro> <value> | get <macro> | preset <name> | randomize | lock <macro> 1|0".postln;
		"Render:".postln;
		"  render <bars> <outPath> | renderfrozen <bars> <outPath>".postln;
		"Analysis / session:".postln;
		"  bpm <value|0> | sensitivity <0.02..0.5> | minslice 64|32|16|8 | reanalyze".postln;
		"  savesession <path> | loadsession <path>".postln;
		"Quant:".postln;
		"  quant 1|0 | quantmode nearest|forward|backward | quantgrid 8|16|32".postln;
		"  keeporder 1|0 | quantswing <0..0.95> | exportquant <bars> <outPath>".postln;
		"Force always-audio:".postln;
		"  forcesound 1|0".postln;
		"MIDI/OSC mapping:".postln;
		"  mapcc <macro> <ccNum> [chan] | learncc <macro> [chan] | maposc <macro> </addr>".postln;
		"=========================================".postln;
		"".postln;
	};

	~idm[\_restAfterToken] = { |line, firstToken|
		var i;
		i = line.find(firstToken);
		if(i.isNil) {
			""
		} {
			(line.copyRange(i + firstToken.size, line.size - 1)).stripWhiteSpace
		}
	};

	~idm[\cmd] = { |line|
		var sline, parts, cmd;

		if(line.isNil) {
			~idm[\help].value;
		} {
			sline = line.asString.stripWhiteSpace;
			if(sline.size == 0) {
				~idm[\help].value;
			} {
				parts = sline.split($ );
				cmd = parts[0].toLower;

				switch(cmd,
					"help", { ~idm[\help].value; },

					"ui", { ~idm[\openUI].value; },

					"load", {
						var path;
						path = ~idm[\_restAfterToken].value(sline, parts[0]);
						path = ~idm[\normalizePath].value(path);
						if(path.isNil) { "Bad path.".warn } { ~idm[\load].value(path) };
					},

					"last", {
						var p;
						p = ~idm[\loadLastPath].value;
						if(p.isNil) {
							"No last path saved yet.".warn
						} {
							("Loading last: " ++ p).postln;
							~idm[\load].value(p);
						};
					},

					"loadlast", { ~idm[\cmd].value("last"); },
					"play", { ~idm[\play].value; },
					"stop", { ~idm[\stop].value; },

					"preview", {
						var idx;
						idx = (parts.size > 1).if({ parts[1].asInteger }, { 0 });
						~idm[\preview].value(idx);
					},

					"seed", {
						if(parts.size < 2) {
							("seed = " ++ (~idm[\seed] ? 0)).postln;
						} {
							~idm[\seed] = parts[1].asInteger;
							~idm[\invalidatePattern].value(false);
							("[IDM] seed = " ++ ~idm[\seed]).postln;
						};
					},

					"regen", { ~idm[\regen].value; },
					"freeze", { ~idm[\freeze].value(false); },
					"unfreeze", { ~idm[\unfreeze].value; },

					"mutate", {
						var amt;
						amt = (parts.size > 1).if({ parts[1].asFloat }, { 0.25 });
						~idm[\mutate].value(amt);
					},

					"mode", {
						var m;
						if(parts.size < 2) {
							"Usage: mode sync|free (aliases: grid|chaos)".warn;
						} {
							m = parts[1].toLower;
							if((m == "sync") or: { m == "grid" }) {
								~idm[\mode] = \sync;
								if(~idm[\modePop].notNil) { ~idm[\appDo].value({ ~idm[\modePop].value = 0; }) };
								"[IDM] mode = sync".postln;
							} {
								if((m == "free") or: { m == "chaos" }) {
									~idm[\mode] = \free;
									if(~idm[\modePop].notNil) { ~idm[\appDo].value({ ~idm[\modePop].value = 1; }) };
									"[IDM] mode = free".postln;
								} {
									"Unknown mode. Use: mode sync | mode free".warn;
								};
							};
						};
					},

					"set", {
						var name, val;
						if(parts.size < 3) {
							"Usage: set <macro> <value>".warn;
						} {
							name = parts[1].asSymbol;
							val  = parts[2].asFloat;

							if(~idm[\macroSpec].isNil or: { ~idm[\macroSpec].includesKey(name).not }) {
								("Unknown macro: " ++ name).warn;
							} {
								~idm[\setMacro].value(name, val);
								("Set " ++ name ++ " -> " ++ ~idm[\getMacro].value(name)).postln;
							};
						};
					},

					"get", {
						var name;
						if(parts.size < 2) {
							"Usage: get <macro>".warn;
						} {
							name = parts[1].asSymbol;
							if(~idm[\macroSpec].isNil or: { ~idm[\macroSpec].includesKey(name).not }) {
								("Unknown macro: " ++ name).warn;
							} {
								(name.asString ++ " = " ++ ~idm[\getMacro].value(name)).postln;
							};
						};
					},

					"preset", {
						var presetName;
						presetName = ~idm[\_restAfterToken].value(sline, parts[0]);
						if(presetName.size == 0) {
							("Presets: " ++ ~idm[\presetNames].join(", ")).postln;
						} {
							~idm[\applyPreset].value(presetName);
						};
					},

					"randomize", { ~idm[\randomizeParams].value; },
					"captureab", { ~idm[\captureAB].value; },
					"swapab", { ~idm[\swapAB].value; },

					"lock", {
						var name, v;
						if(parts.size < 3) {
							"Usage: lock <macro> 1|0".warn;
						} {
							name = parts[1].asSymbol;
							v = parts[2].asInteger != 0;
							~idm[\setMacroLock].value(name, v);
						};
					},

					"render", {
						var bars, out;
						if(parts.size < 3) {
							"Usage: render <bars> <outPath>".warn;
						} {
							if(~idm[\renderBars].isNil) {
								"~idm[\\renderBars] is not defined.".warn;
							} {
								bars = parts[1].asInteger.max(1);
								out = ~idm[\_restAfterToken].value(sline, parts[0] ++ " " ++ parts[1]);
								out = out.stripWhiteSpace;
								out = ~idm[\normalizePath].value(out);
								if(out.isNil) { "Bad outPath.".warn } { ~idm[\renderBars].value(bars, out) };
							};
						};
					},

					"renderfrozen", {
						var bars, out;
						bars = (parts.size > 1).if({ parts[1].asInteger.max(1) }, { (~idm[\patternBars] ? 4).asInteger.max(1) });
						out = if(parts.size > 2) {
							~idm[\_restAfterToken].value(sline, parts[0] ++ " " ++ parts[1]).stripWhiteSpace
						} {
							nil
						};
						~idm[\renderFrozen].value(bars, out);
					},

					"quant", {
						var v;
						v = (parts.size > 1).if({ parts[1].asInteger }, { 1 });
						~idm[\quant][\enabled] = (v != 0);
						~idm[\rebuildQuant].value;
					},

					"quantmode", {
						var m;
						if(parts.size < 2) {
							"Usage: quantmode nearest|forward|backward".warn;
						} {
							m = parts[1].toLower;
							if(m == "nearest") { ~idm[\quant][\mode] = \nearest; };
							if(m == "forward") { ~idm[\quant][\mode] = \forward; };
							if(m == "backward") { ~idm[\quant][\mode] = \backward; };
							if(["nearest", "forward", "backward"].includes(m).not) {
								"Use nearest, forward, or backward.".warn;
							};
							~idm[\rebuildQuant].value;
						};
					},

					"quantgrid", {
						var g;
						if(parts.size < 2) {
							"Usage: quantgrid 8|16|32".warn;
						} {
							g = parts[1].asInteger;
							if([8, 16, 32].includes(g).not) {
								"Use 8, 16, or 32".warn;
							} {
								~idm[\quant][\gridDiv] = g;
								~idm[\rebuildQuant].value;
							};
						};
					},

					"keeporder", {
						var v;
						v = (parts.size > 1).if({ parts[1].asInteger }, { 1 });
						~idm[\quant][\keepOrder] = (v != 0);
						~idm[\rebuildQuant].value;
					},

					"quantswing", {
						var v;
						if(parts.size < 2) {
							"Usage: quantswing <0..0.95>".warn;
						} {
							v = parts[1].asFloat.clip(0.0, 0.95);
							~idm[\quant][\swing] = v;
							~idm[\rebuildQuant].value;
						};
					},

					"exportquant", {
						var bars, out;
						if(parts.size < 3) {
							"Usage: exportquant <bars> <outPath>".warn;
						} {
							bars = parts[1].asInteger.max(1);
							out = ~idm[\_restAfterToken].value(sline, parts[0] ++ " " ++ parts[1]);
							out = out.stripWhiteSpace;
							out = ~idm[\normalizePath].value(out);
							if(out.isNil) { "Bad outPath.".warn } { ~idm[\exportQuantTimeline].value(bars, out) };
						};
					},

					"bpm", {
						var v;
						if(parts.size < 2) {
							("bpmOverride = " ++ (~idm[\bpmOverride] ? 0)).postln;
						} {
							v = parts[1].asFloat;
							~idm[\bpmOverride] = (v > 0).if(v, nil);
							~idm[\reanalyzeLoaded].value(true, true);
						};
					},

					"sensitivity", {
						if(parts.size < 2) {
							("onsetSensitivity = " ++ (~idm[\onsetSensitivity] ? 0.15)).postln;
						} {
							~idm[\onsetSensitivity] = parts[1].asFloat.clip(0.02, 0.5);
							~idm[\reanalyzeLoaded].value(true, true);
						};
					},

					"minslice", {
						var div;
						if(parts.size < 2) {
							("minSliceBeats = " ++ (~idm[\minSliceBeats] ? 0.25)).postln;
						} {
							div = parts[1].asInteger;
							~idm[\minSliceBeats] = if(div == 64) {
								0.0625
							} {
								if(div == 32) { 0.125 } { if(div == 8) { 0.5 } { 0.25 } }
							};
							~idm[\reanalyzeLoaded].value(true, true);
						};
					},

					"reanalyze", { ~idm[\reanalyzeLoaded].value(true, true); },

					"savesession", {
						var path;
						path = ~idm[\_restAfterToken].value(sline, parts[0]);
						path = (path.size == 0).if({ nil }, { path });
						~idm[\saveSession].value(path);
					},

					"loadsession", {
						var path;
						path = ~idm[\_restAfterToken].value(sline, parts[0]);
						path = (path.size == 0).if({ nil }, { path });
						~idm[\loadSession].value(path);
					},

					"forcesound", {
						var v;
						v = (parts.size > 1).if({ parts[1].asInteger }, { 1 });
						~idm[\forceHits] = (v != 0);
						if(~idm[\forceSoundToggle].notNil) {
							~idm[\appDo].value({
								~idm[\forceSoundToggle].value = (~idm[\forceHits] == true).if(1, 0);
							});
						};
						("[IDM] forceHits = " ++ ~idm[\forceHits]).postln;
					},

					"mapcc", {
						var name, cc, ch;
						if(parts.size < 3) {
							"Usage: mapcc <macro> <ccNum> [chan]".warn;
						} {
							name = parts[1].asSymbol;
							cc = parts[2].asInteger;
							ch = (parts.size > 3).if({ parts[3].asInteger }, { 0 });
							if(~idm[\mapCC].isNil) { "~idm[\\mapCC] not defined.".warn } { ~idm[\mapCC].value(name, cc, ch) };
						};
					},

					"learncc", {
						var name, ch;
						if(parts.size < 2) {
							"Usage: learncc <macro> [chan]".warn;
						} {
							name = parts[1].asSymbol;
							ch = (parts.size > 2).if({ parts[2].asInteger }, { 0 });
							if(~idm[\learnCC].isNil) { "~idm[\\learnCC] not defined.".warn } { ~idm[\learnCC].value(name, ch) };
						};
					},

					"maposc", {
						var name, addr;
						if(parts.size < 3) {
							"Usage: maposc <macro> </address>".warn;
						} {
							name = parts[1].asSymbol;
							addr = parts[2].asString;
							if(~idm[\mapOSC].isNil) { "~idm[\\mapOSC] not defined.".warn } { ~idm[\mapOSC].value(name, addr) };
						};
					},

					{
						("Unknown command: " ++ cmd).warn;
						~idm[\help].value;
					}
				);
			};
		};
		nil
	};

	~idm[\whenReady] = { |func|
		if(~idm.notNil and: { ~idm[\readyForCommands] == true }) {
			func.value;
		} {
			"IDM not ready yet.".warn;
		};
	};

	// =====================================================
	// INIT
	// =====================================================
	~idm[\status].value("Engine loaded.");
	~idm[\help].value;

	{
		var last = ~idm[\loadLastPath].value;
		if(last.notNil and: { last.size > 0 }) {
			("[IDM] Found last path: " ++ last).postln;
			"[IDM] Tip: ~idm[\\cmd].value(\"last\") to reload it.".postln;
		};
	}.value;

	~idm[\readyForCommands] = true;
	"[IDM] Ready for commands.".postln;
	~idm[\openUI].value;
});
)

//////////////////////////////////////////////////////////
// QUICK COMMAND EXAMPLES
// These are intentionally inside a block comment so evaluating the whole file is safe.
/*
~idm[\openUI].value;
~idm[\cmd].value("ui");

~idm[\cmd].value("load /path/to/drum_loop.wav");
~idm[\cmd].value("play");
~idm[\cmd].value("stop");
~idm[\cmd].value("preview 0");
~idm[\cmd].value("forcesound 1");
~idm[\cmd].value("last");
~idm[\cmd].value("loadlast");

~idm[\renderBarsDownbeat].value(8, Platform.userHomeDir +/+ "Desktop/idm_loop_8bar.wav", 0);

// QUANT / SYNC
~idm[\cmd].value("mode sync");
~idm[\cmd].value("quant 1");
~idm[\cmd].value("quantmode nearest");
~idm[\cmd].value("quantgrid 16");
~idm[\cmd].value("keeporder 1");
~idm[\cmd].value("quantswing 0.0");
~idm[\cmd].value("exportquant 8 " ++ (Platform.userHomeDir +/+ "Desktop/idm_quant_timeline.wav"));

// FREE MODE
~idm[\cmd].value("mode free");

// PARAMS
~idm[\setMacro].value(\burst, 0.46);
~idm[\setMacro].value(\glitch, 0.25);
~idm[\setMacro].value(\ghost, 0.34);
~idm[\setMacro].value(\repeats, 0.44);
~idm[\setMacro].value(\density, 0.94);
~idm[\setMacro].value(\panwidth, 0.14);
~idm[\setMacro].value(\reverse, 0.53);
~idm[\setMacro].value(\ratespread, 0.13);
~idm[\setMacro].value(\tight, 0.43);
~idm[\setMacro].value(\swing, 0.12);
~idm[\setMacro].value(\fill, 0.13);
~idm[\setMacro].value(\chaos, 0.13);

// CHECK PARAMS / AUDIO
~idm[\macros][\burst].postln;
~idm[\macros].postln;
ServerOptions.devices;
*/
