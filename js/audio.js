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

  setEnabled(enabled) {
    this.enabled = Boolean(enabled);
    if (!this.enabled && this.context?.state === "running") this.context.suspend().catch(() => {});
    return this.enabled;
  }
}
