export class AudioManager {
  constructor() {
    this.context = null;
    this.enabled = true;
    this.ambientTimer = null;
  }

  ensureContext() {
    if (!this.enabled) return null;
    if (!this.context) {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (!AudioContext) return null;
      this.context = new AudioContext();
    }
    if (this.context.state === "suspended") this.context.resume().catch(() => {});
    return this.context;
  }

  tone(frequency, duration = .08, type = "square", volume = .035, delay = 0) {
    const context = this.ensureContext();
    if (!context) return;
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, context.currentTime + delay);
    gain.gain.setValueAtTime(volume, context.currentTime + delay);
    gain.gain.exponentialRampToValueAtTime(.0001, context.currentTime + delay + duration);
    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start(context.currentTime + delay);
    oscillator.stop(context.currentTime + delay + duration);
  }

  play(name) {
    if (!this.enabled) return;
    switch (name) {
      case 'reset':
        [196, 147, 98, 73].forEach((note, index) => this.tone(note, .9, 'sine', .035, index * .16));
        this.noise(1.4, .018, .12, 520);
        break;
      case 'bell':
        this.tone(196, 1.25, 'sine', .045);
        this.tone(392, .8, 'sine', .018, .03);
        this.tone(587, .55, 'sine', .01, .05);
        break;
      case "step": this.tone(116, .035, "square", .012); break;
      case "talk": this.tone(330, .055, "square", .025); this.tone(440, .07, "square", .018, .045); break;
      case "choice": this.tone(262, .09, "triangle", .04); this.tone(392, .14, "triangle", .035, .08); break;
      case "event": [196, 247, 330].forEach((note, index) => this.tone(note, .32, "triangle", .035, index * .1)); break;
      case "travel": [392, 330, 262].forEach((note, index) => this.tone(note, .12, "square", .025, index * .07)); break;
      case "save": this.tone(523, .07, "square", .025); this.tone(659, .12, "square", .025, .06); break;
      case "ending": [220, 277, 330, 440, 554].forEach((note, index) => this.tone(note, .6, "triangle", .03, index * .17)); break;
      default: this.tone(220, .05, "square", .018);
    }
  }

  unlock() {
    const context = this.ensureContext();
    if (context?.state === 'suspended') context.resume().catch(() => {});
  }

  noise(duration = .5, volume = .008, delay = 0, cutoff = 900) {
    const context = this.ensureContext();
    if (!context) return;
    const frameCount = Math.max(1, Math.floor(context.sampleRate * duration));
    const buffer = context.createBuffer(1, frameCount, context.sampleRate);
    const data = buffer.getChannelData(0);
    for (let index = 0; index < frameCount; index += 1) data[index] = Math.random() * 2 - 1;
    const source = context.createBufferSource();
    const filter = context.createBiquadFilter();
    const gain = context.createGain();
    const start = context.currentTime + delay;
    source.buffer = buffer;
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(cutoff, start);
    gain.gain.setValueAtTime(.0001, start);
    gain.gain.linearRampToValueAtTime(volume, start + Math.min(.14, duration * .3));
    gain.gain.exponentialRampToValueAtTime(.0001, start + duration);
    source.connect(filter);
    filter.connect(gain);
    gain.connect(context.destination);
    source.start(start);
    source.stop(start + duration);
  }

  update(scene, state, delta, movement = {}) {
    if (!this.enabled || !scene || !state) return;
    const context = this.context;
    if (!context || context.state !== 'running') return;
    const now = context.currentTime;
    this.nextStepAt ||= 0;
    this.nextAmbientAt ||= 0;
    this.nextMusicAt ||= 0;
    if (movement.moving && now >= this.nextStepAt) {
      this.tone(movement.running ? 126 : 108, .028, 'triangle', .008);
      this.noise(.035, .004, 0, 460);
      this.nextStepAt = now + (movement.running ? .17 : .29);
    }
    if (now >= this.nextAmbientAt) {
      this.scheduleAmbience(scene.id, state);
      this.nextAmbientAt = now + 2.7 + (state.loopElapsed % 7) * .08;
    }
    if (now >= this.nextMusicAt && !state.cinematic) {
      this.scheduleMusic(scene.id, state);
      this.nextMusicAt = now + 4.8;
    }
  }

  scheduleAmbience(sceneId, state) {
    const indoor = /room|interior|archive|studio|control|darkroom|basement/.test(sceneId);
    if (/harbor|cave|lakeside/.test(sceneId)) {
      this.noise(2.2, .007, 0, 620);
      this.tone(98, 1.8, 'sine', .004, .2);
    } else if (/chapel/.test(sceneId)) {
      this.noise(1.8, .004, 0, 780);
      if (Math.floor(state.loopElapsed / 60) % 6 === 0) this.tone(392, 1.4, 'sine', .012, .35);
    } else if (/inn/.test(sceneId)) {
      this.noise(1.35, .005, 0, 1200);
      this.tone(147, .16, 'triangle', .004, .6);
    } else if (/darkroom/.test(sceneId)) {
      this.tone(55, 2.1, 'sine', .005);
      this.noise(1.7, .003, .1, 360);
    } else if (/archive/.test(sceneId)) {
      this.noise(.55, .004, .4, 1050);
    } else {
      this.noise(2.1, indoor ? .003 : .005, 0, indoor ? 700 : 980);
      if (!indoor) this.tone(784, .08, 'sine', .003, .65);
    }
  }

  scheduleMusic(sceneId, state) {
    const palettes = {
      harbor: [196, 247, 294, 370],
      chapel: [220, 330, 392, 494],
      inn: [196, 262, 330, 392],
      archive: [175, 220, 262, 330],
      darkroom: [147, 185, 220, 277],
      town: [220, 277, 330, 440],
    };
    const key = Object.keys(palettes).find((name) => sceneId.includes(name)) || 'town';
    const notes = palettes[key];
    const offset = (Math.floor(state.loopElapsed / 120) + state.loopCount) % notes.length;
    [0, 2, 1].forEach((step, index) => this.tone(notes[(offset + step) % notes.length], .62, 'triangle', .007, index * .34));
  }

  setEnabled(enabled) {
    this.enabled = Boolean(enabled);
    if (!this.enabled && this.context?.state === "running") this.context.suspend().catch(() => {});
    return this.enabled;
  }
}
