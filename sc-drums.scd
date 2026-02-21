(
// =====================================================
// BREAKBEAT IDM SLICER — HEADLESS + CLI (v3.4)
// - No GUI
// - Player is a single SystemClock.sched chain with phase state machine
// - Guard token + player token -> reset-safe, old callbacks bail
// =====================================================

// ---------- global guard token must exist before reset uses it
~idmGuardToken = ~idmGuardToken ? 0;

// ---------- hard cleanup (safe to re-evaluate repeatedly)
if(~idm.notNil) { try { ~idmReset.value } { } };

~idmReset = {

	// invalidate any scheduled callbacks immediately
	~idmGuardToken = (~idmGuardToken ? 0) + 1;

	// stop pattern if any
	if(~idm.notNil and: { ~idm[\pat].notNil }) { ~idm[\pat].stop; ~idm[\pat] = nil; };

	// stop loader routines
	if(~idm.notNil and: { ~idm[\loadRoutine].notNil }) {
		if(~idm[\loadRoutine] !== thisThread) { try { ~idm[\loadRoutine].stop } { } };
		~idm[\loadRoutine] = nil;
		~idm[\cancelLoad] = true;
	};

	if(~idm.notNil and: { ~idm[\analysisRoutine].notNil }) {
		if(~idm[\analysisRoutine] !== thisThread) { try { ~idm[\analysisRoutine].stop } { } };
		~idm[\analysisRoutine] = nil;
		~idm[\cancelAnalysis] = true;
	};

	OSCdef(\idm_cellfeat).free;
	MIDIdef.cc(\__learnOnce).free;

	// free buffer
	if(~idm.notNil and: { ~idm[\buf].notNil }) { ~idm[\buf].free; ~idm[\buf] = nil; };

	// invalidate player flags safely
	if(~idm.notNil) {
		~idm[\playerRunning] = false;
		~idm[\playerToken] = (~idm[\playerToken] ? 0) + 1;
	};

	~idm = nil;
	"IDM: reset done.".postln;
};

// ---------- fresh state
~idm = IdentityDictionary.new;

if(s.serverRunning.not) { s.boot; };

s.doWhenBooted({

	// =====================================================
	// ENGINE CONFIG
	// =====================================================
	s.latency = 0.2;
	~idm[\debugNodes] = false;
	~idm[\mode] = \grid; // \grid or \chaos

	~idm[\status] = { |str| ("[IDM] " ++ (str ? "")).postln; };
	~idm[\setStatus] = ~idm[\status];
	~idm[\setBpmStatus] = { |bpm| ("[IDM] BPM: " ++ bpm).postln; };

	// =====================================================
	// STATE / GLOBALS
	// =====================================================
	~idm[\buf] = nil;
	~idm[\sr] = s.sampleRate;
	~idm[\hop] = 512;

	~idm[\minBpm] = 140;
	~idm[\maxBpm] = 175;

	~idm[\bpm] = nil;
	~idm[\clock] = nil;
	~idm[\pat] = nil;

	~idm[\playerToken] = 0;
	~idm[\playerRunning] = false;

	~idm[\forceHits] = false; // set true to guarantee audio
	~idm[\debugTick] = false; // set true to print tick activity

	~idm[\cells] = nil;
	~idm[\onsetOffsets] = nil;

	~idm[\ready] = false;
	~idm[\isLoading] = false;
	~idm[\loadRoutine] = nil;
	~idm[\analysisRoutine] = nil;

	// =====================================================
	// PATH utils
	// =====================================================
	~idm[\normalizePath] = { |p|
		if(p.isNil) { nil } {
			p = p.asString.stripWhiteSpace;
			p = p.replace("\n","").replace("\r","").replace("\"","");
			if(p.beginsWith("file://localhost")) { p = p.replace("file://localhost", ""); };
			if(p.beginsWith("file://")) { p = p.copyRange(7, p.size-1); };
			p = p.replace("%20", " ");
			if(p.size <= 1 or: { p == "/" }) { nil } {
				if(p.beginsWith("/").not) { p = "/" ++ p };
				p
			};
		};
	};

	~idm[\lastPathFile] = Platform.userHomeDir +/+ ".sc_idm_lastpath.txt";
	~idm[\saveLastPath] = { |p|
		var f;
		if(p.isNil) { ^nil };
		f = File(~idm[\lastPathFile], "w");
		if(f.isOpen) { f.write(p.asString); f.close; };
		p
	};
	~idm[\loadLastPath] = {
		var f, txt;
		f = File(~idm[\lastPathFile], "r");
		if(f.isOpen.not) { ^nil };
		txt = f.readAllString;
		f.close;
		txt = txt.notNil.if({ txt.stripWhiteSpace }, { nil });
		txt
	};

	// =====================================================
	// MACROS
	// =====================================================
	~idm[\macros] = IdentityDictionary[
    // pattern density / groove (IDM-ish defaults)
    \density   -> 0.62,
    \fill      -> 0.38,
    \ghost     -> 0.26,
    \tight     -> 0.74,
    \swing     -> 0.14,
    \glitch    -> 0.62,
    \burst     -> 0.38,
    \repeats   -> 0.55,
    \chaos     -> 0.25,

    // sound-shaping
    \ratespread -> 0.22,
    \reverse    -> 0.14,
    \panwidth   -> 0.55,
    \env        -> 0.22,
    \humanize   -> 0.22,

    // reserved
    \kickBias  -> 0.00,
    \snareBias -> 0.00,
    \hatBias   -> 0.00
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

		\kickBias  -> [-1.0, 1.0],
		\snareBias -> [-1.0, 1.0],
		\hatBias   -> [-1.0, 1.0]
	];

	~idm[\getMacro] = { |name| (~idm[\macros][name] ? 0.0) };
	~idm[\setMacro] = { |name, val|
		var lohi;
		lohi = ~idm[\macroSpec][name] ? [0, 1];
		~idm[\macros][name] = val.clip(lohi[0], lohi[1]);
	};

	// =====================================================
	// MIDI mapping (macro -> CC) + learn
	// =====================================================
	MIDIClient.init;
	MIDIIn.connectAll;
	~idm[\ccMaps] = IdentityDictionary.new;

	~idm[\mapCC] = { |macroName, ccNum, chan=0|
		MIDIdef.cc(("cc_"++macroName).asSymbol).free;
		~idm[\ccMaps][macroName] = ccNum;

		MIDIdef.cc(("cc_"++macroName).asSymbol, { |val, num, ch|
			var lohi, mapped;
			if((ch == chan) and: { num == ccNum }) {
				lohi = ~idm[\macroSpec][macroName] ? [0,1];
				mapped = (val/127).linlin(0, 1, lohi[0], lohi[1]);
				~idm[\setMacro].value(macroName, mapped);
			};
		});

		("Mapped CC "++ccNum++" -> "++macroName).postln;
	};

	~idm[\learnCC] = { |macroName, chan=0|
		("Move a CC now to learn mapping for "++macroName).postln;
		MIDIdef.cc(\__learnOnce).free;
		MIDIdef.cc(\__learnOnce, { |val, num, ch|
			if(ch == chan) {
				MIDIdef.cc(\__learnOnce).free;
				~idm[\mapCC].value(macroName, num, chan);
			};
		});
	};

	// =====================================================
	// OSC mapping
	// =====================================================
	~idm[\mapOSC] = { |macroName, addressString|
		OSCdef(("osc_"++macroName).asSymbol).free;

		OSCdef(("osc_"++macroName).asSymbol, { |msg|
			var val, lohi, mapped, inRange;
			val = msg[1].asFloat;
			lohi = ~idm[\macroSpec][macroName] ? [0,1];
			inRange = (val >= lohi[0]) and: { val <= lohi[1] };
			mapped = inRange.if(val, val.linlin(0, 1, lohi[0], lohi[1]));
			~idm[\setMacro].value(macroName, mapped);
		}, addressString.asSymbol);

		("Mapped OSC "++addressString++" -> "++macroName).postln;
	};

	// =====================================================
	// SYNTHS
	// =====================================================
	SynthDef(\idm_slicePlayer, {
		|out=0, buf=0, gridStart=0, gridEnd=44100, onsetOffset=0,
		 amp=0.9, rate=1, pan=0, atk=0.002, rel=0.01|

		var frames, gs, ge, ge2, off, sF, eF;
		var isNeg, step, ph, idx, sig;
		var durFrames, durSec, env;

		frames = BufFrames.kr(buf).max(4);

		gs = gridStart.clip(0, frames-2);
		ge = gridEnd.clip(0, frames-1);
		ge2 = ge.max(gs + 2).clip(0, frames-1);

		off = onsetOffset.clip(0, (ge2 - gs).max(0));
		sF = (gs + off).clip(0, ge2-1);
		eF = ge2;

		isNeg = (rate < 0);
		step = BufRateScale.kr(buf) * rate.abs.max(0.001);

		ph = Phasor.ar(0, step, sF, eF, sF);
		idx = Select.ar(K2A.ar(isNeg), [ph, (sF + eF) - ph]);

		sig = BufRd.ar(1, buf, idx, 0, 4);

		durFrames = (eF - sF).abs.max(2);
		durSec = (durFrames / SampleRate.ir) / rate.abs.max(0.001);

		env = EnvGen.ar(
			Env.linen(atk, (durSec - atk - rel).max(0.001), rel),
			doneAction: 2
		);

		Out.ar(out, Pan2.ar(sig * env * amp, pan));
	}).add;

	s.sync;

	// =====================================================
	// ANALYSIS + GRID
	// =====================================================
	~idm[\onsetStrength] = { |sig, hop=512|
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
		};

		nHops.do { |i|
			var a, b, d;
			a = e[i] ? 0.0;
			b = (i == 0).if(0.0, (e[i-1] ? 0.0));
			d = a - b;
			od[i] = d.max(0.0);
		};

		mx = (od.maxItem ? 0.0).max(1e-9);
		od.collect { |v| v / mx };
	};

	~idm[\estimateBpm] = { |od, hop=512, sr=44100, minBpm=140, maxBpm=175|
		var lagMin, lagMax, bestLag, bestVal;
		lagMin = ((60*sr)/(hop*maxBpm)).round(1).asInteger.max(1);
		lagMax = ((60*sr)/(hop*minBpm)).round(1).asInteger.max(lagMin+1);

		bestLag = lagMin; bestVal = -1.0;
		(lagMin..lagMax).do { |lag|
			var sum, n;
			sum = 0.0;
			n = (od.size - lag).asInteger.max(0);
			n.do { |i| sum = sum + (od[i] * od[i+lag]); };
			if(sum > bestVal) { bestVal = sum; bestLag = lag; };
		};

		(60 * sr) / (hop * bestLag);
	};

	~idm[\pickOnsetPeaks] = { |od, hop=512, thresh=0.15|
		var peaks;
		peaks = List.new;
		(1..(od.size-2)).do { |i|
			var v;
			v = od[i];
			if(v > thresh and: { v > od[i-1] and: { v >= od[i+1] } }) {
				peaks.add([ (i * hop).asInteger, v ]);
			};
		};
		peaks.asArray;
	};

	~idm[\buildGridCells16] = { |numFrames, bpm, sr|
		var total, spb, sp16, nCells;
		total = numFrames.asInteger.max(1);
		spb = (sr * 60 / bpm);
		sp16 = spb / 4;
		nCells = (total / sp16).ceil.asInteger.max(1);

		Array.fill(nCells, { |i|
			var gs, ge;
			gs = (i * sp16).asInteger;
			ge = (((i+1) * sp16).min(total)).asInteger;
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

			while({ idx < peaks.size and: { peaks[idx][0].asInteger < gs } }) { idx = idx + 1 };

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
		};

		offs;
	};

	// =====================================================
	// LOADER
	// =====================================================
	~idm[\load] = { |path|
		if(~idm[\isLoading] == true) { "IDM: load ignored (already loading).".warn; ^nil };
		~idm[\isLoading] = true;

		if(~idm[\loadRoutine].notNil and: { ~idm[\loadRoutine] !== thisThread }) { try { ~idm[\loadRoutine].stop } { } };
		~idm[\loadRoutine] = nil;

		~idm[\loadRoutine] = Routine({
			var sf, frames, chans, fileSR, data, mono, od, bpm, peaks;
			var finish = { ~idm[\isLoading] = false; };

			path = ~idm[\normalizePath].value(path);
			if(path.isNil) { "No file selected.".warn; finish.value; nil.alwaysYield };
			if(File.exists(path).not) { ("File not found: "++path).warn; finish.value; nil.alwaysYield };

			~idm[\saveLastPath].value(path);
			~idm[\setStatus].value("Loading…");
			("Loading: " ++ path).postln;

			~idm[\ready] = false;
			if(~idm[\pat].notNil) { ~idm[\pat].stop; ~idm[\pat] = nil; };
			if(~idm[\buf].notNil) { ~idm[\buf].free; ~idm[\buf] = nil; };

			~idm[\cells] = nil;
			~idm[\onsetOffsets] = nil;

			~idm[\buf] = Buffer.readChannel(s, path, channels:[0]);
			s.sync;

			sf = SoundFile.new;
			sf.openRead(path);
			frames = sf.numFrames.asInteger.max(0);
			chans = sf.numChannels.asInteger.max(1);
			fileSR = sf.sampleRate.asFloat.max(1.0);

			if(frames <= 0) { sf.close; ("Could not read frames: "++path).warn; finish.value; nil.alwaysYield };

			data = FloatArray.newClear(frames * chans);
			sf.readData(data);
			sf.close;

			mono = FloatArray.newClear(frames);
			frames.do { |i|
				var sum = 0.0;
				chans.do { |c| sum = sum + data[(i*chans)+c]; };
				mono[i] = sum / chans;
			};

			od = ~idm[\onsetStrength].value(mono, ~idm[\hop]);
			bpm = ~idm[\estimateBpm].value(od, ~idm[\hop], fileSR, ~idm[\minBpm], ~idm[\maxBpm]).round(0.1);
			~idm[\bpm] = bpm;

			if(~idm[\clock].notNil) { try { ~idm[\clock].stop } { } };
			~idm[\clock] = TempoClock.new(bpm/60).permanent_(true);
			~idm[\clock].play;

			("Estimated BPM (constrained): " ++ bpm).postln;
			~idm[\setBpmStatus].value(bpm);

			peaks = ~idm[\pickOnsetPeaks].value(od, ~idm[\hop], 0.15);
			~idm[\cells] = ~idm[\buildGridCells16].value(~idm[\buf].numFrames, bpm, fileSR);
			~idm[\onsetOffsets] = ~idm[\strongestOnsetOffsetPerCell].value(~idm[\cells], peaks);

			("Grid cells (16ths): " ++ ~idm[\cells].size).postln;
			("Onset peaks: " ++ peaks.size).postln;


			// fallback class pools (until server hit-analysis is re-enabled)
~idm[\kicks]  = (0..(~idm[\cells].size-1)).asArray;
~idm[\snares] = ~idm[\kicks];
~idm[\hats]   = ~idm[\kicks];

			~idm[\ready] = true;

			finish.value;
			~idm[\setStatus].value("Loaded ✓ (playable)");
		}).play(SystemClock);
	};

	// =====================================================
	// PREVIEW
	// =====================================================
	~idm[\preview] = { |i=0|
		var cells, offs, buf;
		buf = ~idm[\buf];
		cells = ~idm[\cells];
		offs = ~idm[\onsetOffsets];

		if(buf.isNil or: { cells.isNil } or: { offs.isNil }) { "Load a break first.".warn; ^nil };
		i = i.clip(0, cells.size-1);

		Synth(\idm_slicePlayer, [
			\buf, buf,
			\gridStart, cells[i][0],
			\gridEnd,   cells[i][1],
			\onsetOffset, offs[i],
			\amp, 0.9, \rate, 1,
			\atk, 0.002, \rel, 0.15
		]);
	};

	// =====================================================
	// GROOVE HELPERS
	// =====================================================
	~idm[\baseDur16] = 0.25; // beats
	~idm[\swingDelayMaxSec] = 0.022;

	~idm[\gridTimingOffset] = { |step|
		var tight, swing, maxJit, jit, swingOff, off;
		tight = ~idm[\getMacro].value(\tight);
		swing = ~idm[\getMacro].value(\swing);
		maxJit = (1 - tight).linlin(0, 1, 0.001, 0.018);
		jit = rrand(maxJit.neg, maxJit);
		swingOff = (((step % 2) == 1).if(swing * ~idm[\swingDelayMaxSec], 0.0));
		off = jit + swingOff;
		off.clip(0.0, 0.04);
	};

	~idm[\chaosTimingOffset] = { |step|
		var tight, chaos, maxJit, jit, extra;
		tight = ~idm[\getMacro].value(\tight);
		chaos = ~idm[\getMacro].value(\chaos);
		maxJit = (1 - tight).linlin(0, 1, 0.004, 0.045);
		jit = rrand(0.0, maxJit);
		extra = rrand(0.0, chaos.linlin(0,1, 0.0, 0.08));
		(jit + extra).clip(0.0, 0.12);
	};

	// ---- rhythmic intent (classic kick/snare/hat skeleton)
~idm[\stepBaseClass] = { |step|
    var m;
    m = step.asInteger % 16;
    if([0, 8].includes(m)) { ^\kick };
    if([4, 12].includes(m)) { ^\snare };
    if([2, 6, 10, 14].includes(m)) { ^\hat };
    ^([\hat, \hat, \snare].choose);
};

// ---- choose an index by class (until you restore analysis, it will still work)
~idm[\chooseFromClass] = { |classSym|
    var cells, arr;
    cells = ~idm[\cells] ? [];
    arr = classSym.switch(
        \kick,  ~idm[\kicks],
        \snare, ~idm[\snares],
        \hat,   ~idm[\hats],
        { ~idm[\snares] }
    );

    if(arr.isNil or: { arr.size == 0 }) { ^rrand(0, (cells.size-1).max(0)) };
    arr.choose;
};

	~idm[\pickIdxGridVar] = { |step|
    var n, g, f, idx, jump;
    n = (~idm[\cells].size ? 1).max(1);

    g = ~idm[\getMacro].value(\glitch);
    f = ~idm[\getMacro].value(\fill);

    // base walk
    idx = (step % n).asInteger;

    // random jump
    if(1.0.rand < (g * 0.45 + f * 0.20)) { idx = rrand(0, n-1) };

    // musical hop
    if(1.0.rand < (g * 0.35)) {
        jump = [1,2,4,8,16].wchoose([0.35,0.25,0.20,0.15,0.05].normalizeSum).asInteger;
        idx = (idx + (jump * [1,-1].choose)).wrap(0, n-1);
    };

    idx
};

	~idm[\hitGate] = { |step|
		var d, f, g, on;
		d = ~idm[\getMacro].value(\density);
		f = ~idm[\getMacro].value(\fill);
		g = ~idm[\getMacro].value(\ghost);

		on = (1.0.rand <= d);
		if(on.not and: { 1.0.rand < (f * 0.35) }) { on = true };
		if(on.not and: { ((step % 2)==1) and: { 1.0.rand < g } }) { on = true };
		on;
	};

	~idm[\pickIdxGrid] = { |step|
		var n;
		n = (~idm[\cells].size ? 1).max(1);
		(step % n).asInteger
	};

	~idm[\pickIdxChaos] = { |step|
		var n, g, b, r, idx;
		n = (~idm[\cells].size ? 1).max(1);

		g = ~idm[\getMacro].value(\glitch);
		b = ~idm[\getMacro].value(\burst);
		r = ~idm[\getMacro].value(\repeats);

		if(1.0.rand < (0.35 + g*0.35)) {
			idx = rrand(0, n-1);
		} {
			var stride = [1,2,4,8].wchoose([0.55, 0.25 + r*0.25, 0.15 + g*0.15, 0.05 + b*0.25].normalizeSum).asInteger;
			idx = (step * stride) % n;
		};

		idx.asInteger
	};

	~idm[\rateForStep] = {
		var spread, revProb, g, base, det, rev;
		spread = ~idm[\getMacro].value(\ratespread);
		revProb = ~idm[\getMacro].value(\reverse);
		g = ~idm[\getMacro].value(\glitch);

		base = 1.0;
		det = rrand(-1.0, 1.0) * spread.linlin(0,1, 0.0, 0.6);
		if(1.0.rand < (g * 0.15)) { det = det + [ -0.5, 0.5, 1.0 ].choose };

		rev = (1.0.rand < revProb).if(-1, 1);
		(base + det).max(0.08) * rev
	};

	~idm[\panForStep] = {
		var w;
		w = ~idm[\getMacro].value(\panwidth).linlin(0, 1, 0.0, 0.95);
		rrand(w.neg, w);
	};

	~idm[\envForStep] = {
		var soft, atk, rel;
		soft = ~idm[\getMacro].value(\env);
		atk = soft.linlin(0,1, 0.001, 0.02);
		rel = soft.linlin(0,1, 0.03, 0.22);
		[atk, rel]
	};

	~idm[\ampForStep] = { |isGhost=false|
		var hum, a, spread;
		hum = ~idm[\getMacro].value(\humanize);
		a = isGhost.if(0.22, 0.85);
		spread = hum.linlin(0,1, 0.0, 0.35);
		(a * rrand(1.0 - spread, 1.0 + spread)).clip(0.0, 1.2)
	};

	~idm[\durForStep] = { |mode|
		var base, c, g, b, r, mult;
		base = ~idm[\baseDur16];
		if(mode == \grid) { ^base };

		c = ~idm[\getMacro].value(\chaos);
		g = ~idm[\getMacro].value(\glitch);
		b = ~idm[\getMacro].value(\burst);
		r = ~idm[\getMacro].value(\repeats);

		mult = rrand(0.35, 1.65).linlin(0.35, 1.65, (1 - c*0.65).max(0.2), 1.6 + c*0.9);
		if(1.0.rand < (b * 0.35 + g*0.15)) { mult = mult * rrand(0.18, 0.55) };
		if(1.0.rand < (r * 0.25)) { mult = mult * rrand(0.25, 0.75) };

		(base * mult).clip(0.06, 0.85)
	};

~idm[\stutCountForStep] = { |step|
	var mode, g, b, r, c;
	mode = ~idm[\mode];
	g = ~idm[\getMacro].value(\glitch);
	b = ~idm[\getMacro].value(\burst);
	r = ~idm[\getMacro].value(\repeats);
	c = ~idm[\getMacro].value(\chaos);

	// GRID: make 2/4 happen once glitch+repeats are up (this is the “instant IDM” feel)
	if(mode == \grid) {
		^[1,2,4,8].wchoose([
			(1 - (g*0.85 + r*0.60 + b*0.25)).clip(0.02, 1.0),
			(g*0.55 + r*0.55).clip(0.0, 1.0),
			(g*0.30 + r*0.25 + b*0.40).clip(0.0, 1.0),
			(g*0.15 + b*0.55).clip(0.0, 1.0)
		].normalizeSum).asInteger;
	};

	// CHAOS: allow 16s, scaled by chaos
	^[1,2,4,8,16].wchoose([
		(1 - (c*0.75 + g*0.35 + r*0.30)).clip(0.02, 1.0),
		(c*0.30 + r*0.25).clip(0.0, 1.0),
		(c*0.25 + g*0.25).clip(0.0, 1.0),
		(c*0.25 + b*0.35).clip(0.0, 1.0),
		(c*0.20 + b*0.45 + g*0.10).clip(0.0, 1.0)
	].normalizeSum).asInteger;
};


// =====================================================
// PLAY / STOP  (TempoClock / Pbind — v3.1 feel restored)
// =====================================================
~idm[\play] = {
    // ---- ALL VARS MUST BE FIRST IN SC ----
    var buf, clock, mode, n;

    buf = ~idm[\buf];
    clock = ~idm[\clock];

    if(buf.isNil) { "No buffer loaded.".warn; ^nil };
    if(clock.isNil) { "No clock.".warn; ^nil };
    if(~idm[\ready].not) { "Not ready yet (still loading).".warn; ^nil };
    if(clock.isRunning.not) { clock.play; };

    if(~idm[\pat].notNil) { ~idm[\pat].stop; ~idm[\pat] = nil; };

    mode = (~idm[\mode] ? \grid);
    n = ((~idm[\cells].size ? 1).asInteger).max(1);

    ~idm[\pat] = Pbind(
        \type, \note,
        \instrument, \idm_slicePlayer,
        \buf, Pfunc { ~idm[\buf].bufnum },

        // stable 16th grid timing on TempoClock
        \dur, Pfunc {
            if(mode == \grid) {
                0.25
            }{
                [0.25, 0.125, 0.0625, 0.375]
                .wchoose([0.45, 0.30, 0.15, 0.10])
                .clip(0.0625, 0.5)
            }
        },

        \step, Pseries(0, 1, inf),

        \idx2, Pfunc { |ev|
            var step;
            step = ev[\step].asInteger;

            if(mode == \grid) {
                (step % n).asInteger
            }{
                ~idm[\pickIdxChaos].value(step).clip(0, n-1).asInteger
            }
        },

        \gridStart,   Pfunc { |ev| ~idm[\cells][ev[\idx2]][0] },
        \gridEnd,     Pfunc { |ev| ~idm[\cells][ev[\idx2]][1] },
        \onsetOffset, Pfunc { |ev| ~idm[\onsetOffsets][ev[\idx2]] },

        \rate, Pfunc { ~idm[\rateForStep].value },

        \pan, Pfunc {
            if(mode == \grid) {
                rrand(-0.35, 0.35)
            }{
                ~idm[\panForStep].value
            }
        },

        \atk, Pfunc { ~idm[\envForStep].value[0] },
        \rel, Pfunc { ~idm[\envForStep].value[1] },

        \amp, Pfunc { |ev|
            var hitOn, isGhost, a;
            hitOn = (~idm[\forceHits] == true).if(true, { ~idm[\hitGate].value(ev[\step].asInteger) });
            isGhost = ((ev[\step].asInteger % 2) == 1) and: { 1.0.rand < (~idm[\getMacro].value(\ghost) * 0.35) };
            a = hitOn.if({ ~idm[\ampForStep].value(isGhost) }, { 0.0 });
            a.clip(0.0, 1.2)
        }

    ).play(clock, quant: 0.0);

    ("[IDM] Playing (Pbind). mode=" ++ mode).postln;
    nil
};

~idm[\stop] = {
    if(~idm.notNil and: { ~idm[\pat].notNil }) { ~idm[\pat].stop; ~idm[\pat] = nil; };
    if(~idm.notNil) {
        ~idm[\playerRunning] = false;
        ~idm[\playerToken] = (~idm[\playerToken] ? 0) + 1;
    };
    ~idm[\setStatus].value("Stopped.");
    "[IDM] Stopped.".postln;
};


	~idm[\renderBars] = { |bars=8, outPath|
	var clock, tempo, durSec;

	if(~idm.isNil) { "IDM not initialized.".warn; ^nil };
	if(~idm[\buf].isNil) { "No buffer loaded (load a break first).".warn; ^nil };

	clock = ~idm[\clock];
	if(clock.isNil) { "No clock (load a break first).".warn; ^nil };
	if(clock.isRunning.not) { clock.play; };

	tempo = clock.tempo.max(0.001);          // beats/sec
	durSec = (bars * 4 / tempo).max(0.1);    // bars * 4 beats/bar

	if(outPath.isNil) {
		outPath = (Platform.userHomeDir +/+ ("SC_IDM_Render_" ++ Date.localtime.stamp ++ ".wav"));
	};

	Routine({
		("[IDM] Recording " ++ bars ++ " bars (" ++ durSec.round(0.01) ++ "s) -> " ++ outPath).postln;

		s.prepareForRecord(outPath);
		s.sync;          // <-- critical: ensures temp__0 (etc) is on server

		s.record;

		SystemClock.sched(durSec, {
			s.stopRecording;
			("[IDM] Saved -> " ++ outPath).postln;
			nil
		});

	}).play(SystemClock);

	outPath
};


	~idm[\renderBarsDownbeat] = { |bars=4, outPath, startOffsetBeats=0.0|
	var clock, startBeat, stopBeat, durBeats;
	var latencySec, latencyBeats;

	if(~idm.isNil) { "IDM not initialized.".warn; ^nil };
	if(~idm[\buf].isNil) { "No buffer loaded (load a break first).".warn; ^nil };

	clock = ~idm[\clock];
	if(clock.isNil) { "No clock (load a break first).".warn; ^nil };
	if(clock.isRunning.not) { clock.play; };

	durBeats = (bars.asFloat * 4.0).max(0.25);

	latencySec = (s.latency ? 0.0).asFloat.max(0.0);
	latencyBeats = latencySec * clock.tempo; // tempo = beats/sec

	// choose a clean barline
	startBeat = clock.nextTimeOnGrid(4);

	// manual nudge + latency compensation so the FIRST HIT lands on beat 1 in the file
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

	// start pattern exactly on barline (TempoClock)
	clock.schedAbs(startBeat, {
		if(~idm[\pat].notNil) { ~idm[\pat].stop; ~idm[\pat] = nil; };
		~idm[\play].value;
		nil
	});

	// start recording LATER by s.latency so file "beat 1" matches first audio
	clock.schedAbs(startBeat + latencyBeats, {
		s.record;
		nil
	});

	// stop recording LATER by the same amount (keeps length exact)
	clock.schedAbs(stopBeat + latencyBeats, {
		s.stopRecording;
		if(~idm[\pat].notNil) { ~idm[\pat].stop; ~idm[\pat] = nil; };
		("[IDM] Saved -> " ++ outPath).postln;
		nil
	});

	outPath
};
	// =====================================================
	// CLI
	// =====================================================
	~idm[\help] = {
	"".postln;
	"================ IDM CLI ================".postln;
	"Transport:".postln;
	"  load <path> | last | loadlast | play | stop | preview <i>".postln;
	"Groove modes:".postln;
	"  mode grid | mode chaos".postln;
	"Macros:".postln;
	"  set <macro> <value>   |   get <macro>".postln;
	"Render:".postln;
	"  render <bars> <outPath>".postln;
	"Force always-audio (bypasses hit gating):".postln;
	"  forcesound 1|0".postln;
	"MIDI/OSC mapping:".postln;
	"  mapcc <macro> <ccNum> [chan] | learncc <macro> [chan] | maposc <macro> </addr>".postln;
	"=========================================".postln;
	"".postln;
};

	~idm[\_restAfterToken] = { |line, firstToken|
		var i;
		i = line.find(firstToken);
		if(i.isNil) { ^"" };
		(line.copyRange(i + firstToken.size, line.size-1)).stripWhiteSpace
	};

	~idm[\cmd] = { |line|
	var sline, parts, cmd;

	if(line.isNil) { ~idm[\help].value; ^nil };
	sline = line.asString.stripWhiteSpace;
	if(sline.size == 0) { ~idm[\help].value; ^nil };

	parts = sline.split($ );
	cmd = parts[0].toLower;

	switch(cmd,
		"help", { ~idm[\help].value; },

		"load", {
			var path;
			path = ~idm[\_restAfterToken].value(sline, parts[0]);
			path = ~idm[\normalizePath].value(path);
			if(path.isNil) { "Bad path.".warn } { ~idm[\load].value(path) };
		},

		"last", {
			var p;
			p = ~idm[\loadLastPath].value;
			if(p.isNil) { "No last path saved yet.".warn } {
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

		"mode", {
			var m;
			if(parts.size < 2) { "Usage: mode grid|chaos".warn; ^nil };
			m = parts[1].toLower;
			if(m == "grid") { ~idm[\mode] = \grid; "[IDM] mode = grid".postln; ^nil };
			if(m == "chaos") { ~idm[\mode] = \chaos; "[IDM] mode = chaos".postln; ^nil };
			"Unknown mode. Use: mode grid | mode chaos".warn;
		},

		"set", {
			var name, val;
			if(parts.size < 3) { "Usage: set <macro> <value>".warn; ^nil };
			name = parts[1].asSymbol;
			val  = parts[2].asFloat;

			if(~idm[\macroSpec].isNil or: { ~idm[\macroSpec].includesKey(name).not }) {
				("Unknown macro: " ++ name).warn; ^nil
			};

			~idm[\setMacro].value(name, val);
			("Set " ++ name ++ " -> " ++ ~idm[\getMacro].value(name)).postln;
		},

		"get", {
			var name;
			if(parts.size < 2) { "Usage: get <macro>".warn; ^nil };
			name = parts[1].asSymbol;

			if(~idm[\macroSpec].isNil or: { ~idm[\macroSpec].includesKey(name).not }) {
				("Unknown macro: " ++ name).warn; ^nil
			};

			(name.asString ++ " = " ++ ~idm[\getMacro].value(name)).postln;
		},

		"render", {
			var bars, out;
			if(parts.size < 3) { "Usage: render <bars> <outPath>".warn; ^nil };

			if(~idm[\renderBars].isNil) { "~idm[\\renderBars] is not defined.".warn; ^nil };

			bars = parts[1].asInteger.max(1);
			out = ~idm[\_restAfterToken].value(sline, parts[0] ++ " " ++ parts[1]);
			out = out.stripWhiteSpace;
			out = ~idm[\normalizePath].value(out);

			if(out.isNil) { "Bad outPath.".warn; ^nil };
			~idm[\renderBars].value(bars, out);
		},

		"forcesound", {
			var v;
			v = (parts.size > 1).if({ parts[1].asInteger }, { 1 });
			~idm[\forceHits] = (v != 0);
			("[IDM] forceHits = " ++ ~idm[\forceHits]).postln;
		},

		"mapcc", {
			var name, cc, ch;
			if(parts.size < 3) { "Usage: mapcc <macro> <ccNum> [chan]".warn; ^nil };
			name = parts[1].asSymbol;
			cc = parts[2].asInteger;
			ch = (parts.size > 3).if({ parts[3].asInteger }, { 0 });
			if(~idm[\mapCC].isNil) { "~idm[\\mapCC] not defined.".warn; ^nil };
			~idm[\mapCC].value(name, cc, ch);
		},

		"learncc", {
			var name, ch;
			if(parts.size < 2) { "Usage: learncc <macro> [chan]".warn; ^nil };
			name = parts[1].asSymbol;
			ch = (parts.size > 2).if({ parts[2].asInteger }, { 0 });
			if(~idm[\learnCC].isNil) { "~idm[\\learnCC] not defined.".warn; ^nil };
			~idm[\learnCC].value(name, ch);
		},

		"maposc", {
			var name, addr;
			if(parts.size < 3) { "Usage: maposc <macro> </address>".warn; ^nil };
			name = parts[1].asSymbol;
			addr = parts[2].asString;
			if(~idm[\mapOSC].isNil) { "~idm[\\mapOSC] not defined.".warn; ^nil };
			~idm[\mapOSC].value(name, addr);
		},

		{
			("Unknown command: " ++ cmd).warn;
			~idm[\help].value;
		}
	);
	nil
};

	// init prompt
	~idm[\status].value("Engine loaded (headless).");
	~idm[\help].value;

	{
		var last = ~idm[\loadLastPath].value;
		if(last.notNil and: { last.size > 0 }) {
			("[IDM] Found last path: " ++ last).postln;
			"[IDM] Tip: ~idm[\\cmd].value(\"last\") to reload it.".postln;
		};
	}.value;

});
)



//COMMANDS


  ~idm[\cmd].value("load /Users/name/path/to/your/file")
  ~idm[\cmd].value("play")
  ~idm[\cmd].value("stop")
  ~idm[\cmd].value("preview 0")
  ~idm[\cmd].value("render 8 /Users/name/desktop/{filename}");
  ~idm[\cmd].value("forceSound 1")   (1/0)
  ~idm[\cmd].value("last")   (load last used path)
  ~idm[\cmd].value("loadlast") (alias)

  ~idm[\renderBarsDownbeat].value(4, "/Users/name/desktop/{filename}", 0);


//PARAMS (enter values between 0-1)

~idm[\setMacro].value(\burst, 0.10);
~idm[\setMacro].value(\glitch, 0.10);
~idm[\setMacro].value(\ghost, 0.50);
~idm[\setMacro].value(\repeats, 0.50);
~idm[\setMacro].value(\density, 0.50);
~idm[\setMacro].value(\panwidth, 0.30);
~idm[\setMacro].value(\reverse, 0.10);
~idm[\setMacro].value(\ratespread, 0.10);
~idm[\setMacro].value(\tight, 0.23);
~idm[\setMacro].value(\swing, 0.12);
~idm[\setMacro].value(\snareBias, 0.12);
~idm[\setMacro].value(\hatBias, 0.12);
~idm[\setMacro].value(\fill, 0.12);

//CHECK A PARAM VALUE

~idm[\macros][\burst].postln;
~idm[\macros].postln; // prints all


//Mode Setup

~idm[\mode] = \grid;   // 16ths
~idm[\mode] = \chaos;  // more chaotic

//SEE AUDIO OUTPUTS

ServerOptions.devices;

//SET OUTPUT DEVICE (requires server reboot)

s.options.outDevice = "YOUR DEVICE NAME HERE";
s.reboot;
