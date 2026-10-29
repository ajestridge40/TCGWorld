extends Node
## Tiny synthesizer: every sound effect and the ambient music-box loop are
## generated at startup, so the prototype ships with zero audio assets.
## Swap in real .ogg files later by putting them in `streams` under the same names.

const RATE := 22050

var streams: Dictionary = {}
var players: Array = []
var music: AudioStreamPlayer
var music_enabled := true
var _music_thread: Thread


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	music = AudioStreamPlayer.new()
	music.volume_db = -14.0
	add_child(music)
	_build_effects()
	if DisplayServer.get_name() != "headless":
		_music_thread = Thread.new()
		_music_thread.start(_build_music)


func _exit_tree() -> void:
	if _music_thread and _music_thread.is_started():
		_music_thread.wait_to_finish()


func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var s: AudioStream = streams.get(name)
	if s == null:
		return
	for p in players:
		if not p.playing:
			p.stream = s
			p.pitch_scale = pitch
			p.volume_db = volume_db
			p.play()
			return


func set_music(on: bool) -> void:
	music_enabled = on
	if on and music.stream and not music.playing:
		music.play()
	elif not on:
		music.stop()


# ---------------------------------------------------------------- synthesis

func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


static func _note_freq(semitones_from_a4: float) -> float:
	return 440.0 * pow(2.0, semitones_from_a4 / 12.0)


## A soft plucked tone: sine + a little octave, exponential decay.
func _tone(buf: PackedFloat32Array, start: int, freq: float, dur: float, vol: float, decay: float = 6.0) -> void:
	var n := int(dur * RATE)
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var t := float(i) / RATE
		var env := exp(-t * decay) * minf(1.0, t * 400.0)
		buf[idx] += vol * env * (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t) + 0.1 * sin(TAU * freq * 3.0 * t))


func _noise(buf: PackedFloat32Array, start: int, dur: float, vol: float, f_from: float, f_to: float) -> void:
	# Noise through a sweeping one-pole low-pass: sounds like paper tearing.
	var n := int(dur * RATE)
	var y := 0.0
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in n:
		var t := float(i) / n
		var cutoff := lerpf(f_from, f_to, t)
		var a := clampf(TAU * cutoff / RATE, 0.0, 1.0)
		y += a * (r.randf_range(-1.0, 1.0) - y)
		var env := sin(PI * t) * (0.7 + 0.3 * r.randf())
		if start + i < buf.size():
			buf[start + i] += y * vol * env * 2.0


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


func _build_effects() -> void:
	var b := _buf(0.06)
	_tone(b, 0, 880.0, 0.06, 0.25, 50.0)
	streams["click"] = _make_wav(b)

	b = _buf(0.25)
	_tone(b, 0, _note_freq(15), 0.1, 0.3, 20.0)
	_tone(b, int(0.07 * RATE), _note_freq(22), 0.18, 0.3, 14.0)
	streams["coin"] = _make_wav(b)

	b = _buf(0.45)
	_noise(b, 0, 0.45, 0.6, 600.0, 5000.0)
	streams["rip"] = _make_wav(b)

	b = _buf(0.12)
	_noise(b, 0, 0.12, 0.35, 2500.0, 900.0)
	streams["flip"] = _make_wav(b)

	b = _buf(0.12)
	_noise(b, 0, 0.1, 0.25, 1200.0, 400.0)
	streams["thump"] = _make_wav(b)

	# Reveal chimes climb with rarity.
	var chords := {
		"reveal_uncommon": [3, 7],
		"reveal_rare": [3, 7, 10, 15],
		"reveal_ultra": [3, 7, 10, 15, 19, 22],
		"reveal_secret": [-2, 3, 7, 10, 15, 19, 22, 27],
	}
	for k in chords:
		var notes: Array = chords[k]
		b = _buf(0.12 * notes.size() + 1.0)
		for i in notes.size():
			_tone(b, int(i * 0.09 * RATE), _note_freq(notes[i]), 1.0, 0.18, 4.0)
		streams[k] = _make_wav(b)

	b = _buf(1.2)
	for i in 4:
		_tone(b, int(i * 0.12 * RATE), _note_freq([3, 7, 10, 15][i]), 0.9, 0.2, 3.0)
	streams["fanfare"] = _make_wav(b)

	b = _buf(0.6)
	_tone(b, 0, _note_freq(10), 0.5, 0.2, 6.0)
	_tone(b, int(0.1 * RATE), _note_freq(15), 0.5, 0.2, 6.0)
	streams["chime"] = _make_wav(b)

	b = _buf(0.5)
	_tone(b, 0, _note_freq(12), 0.4, 0.2, 8.0)
	_tone(b, int(0.08 * RATE), _note_freq(16), 0.4, 0.2, 8.0)
	_tone(b, int(0.16 * RATE), _note_freq(19), 0.4, 0.2, 8.0)
	streams["heart"] = _make_wav(b)

	b = _buf(0.3)
	_tone(b, 0, 110.0, 0.3, 0.5, 12.0)
	_noise(b, 0, 0.15, 0.3, 800.0, 200.0)
	streams["hit"] = _make_wav(b)

	b = _buf(0.2)
	_tone(b, 0, _note_freq(-5), 0.2, 0.3, 15.0)
	streams["play"] = _make_wav(b)

	b = _buf(0.35)
	_tone(b, 0, _note_freq(0), 0.15, 0.25, 10.0)
	_tone(b, int(0.1 * RATE), _note_freq(-4), 0.25, 0.25, 10.0)
	streams["nope"] = _make_wav(b)

	b = _buf(1.6)
	for i in 5:
		_tone(b, int(i * 0.14 * RATE), _note_freq([0, 4, 7, 12, 16][i]), 1.2, 0.2, 2.5)
	streams["win"] = _make_wav(b)

	b = _buf(1.4)
	for i in 4:
		_tone(b, int(i * 0.2 * RATE), _note_freq([7, 3, 0, -5][i]), 1.0, 0.2, 3.0)
	streams["lose"] = _make_wav(b)


## Gentle music-box loop: I-vi-IV-V in F major with a pentatonic melody.
func _build_music() -> void:
	var bpm := 84.0
	var beat := 60.0 / bpm
	var bars := 16
	var total := beat * 4.0 * bars
	var b := _buf(total + 0.01)
	var chords := [[-4, 0, 3], [-7, -4, 0], [-11, -7, -4], [-9, -5, -2]]  # F, Dm, Bb, C (rel. A4)
	var scale := [-4, -2, 0, 3, 5, 8, 10, 12]
	var r := RandomNumberGenerator.new()
	r.seed = 1994
	for bar in bars:
		var ch: Array = chords[bar % 4]
		for i in 4:
			var root: int = ch[i % 3] - 12
			_tone(b, int((bar * 4 + i) * beat * RATE), _note_freq(root), beat * 1.5, 0.08, 2.0)
		var step := 0
		while step < 8:
			if r.randf() < 0.7:
				var note: int = scale[r.randi_range(0, scale.size() - 1)]
				if r.randf() < 0.5:
					note = ch[r.randi_range(0, 2)] + 12
				_tone(b, int((bar * 4 + step * 0.5) * beat * RATE), _note_freq(note), beat * 2.0, 0.07, 3.0)
			step += 1 if r.randf() < 0.6 else 2
	# Soften the loop seam.
	var fade := int(0.05 * RATE)
	for i in fade:
		b[b.size() - 1 - i] *= float(i) / fade
	var wav := _make_wav(b, true)
	call_deferred("_start_music", wav)


func _start_music(wav: AudioStreamWAV) -> void:
	streams["music"] = wav
	music.stream = wav
	if music_enabled:
		music.play()
