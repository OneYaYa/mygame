export const clamp = (value, min = 0, max = 100) => Math.min(max, Math.max(min, value));

export const lerp = (from, to, amount) => from + (to - from) * amount;

export function hashString(text) {
  let hash = 2166136261;
  for (let i = 0; i < String(text).length; i += 1) {
    hash ^= String(text).charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

export function nextRandom(state) {
  state.rngState = (Math.imul(state.rngState || 1, 1664525) + 1013904223) >>> 0;
  return state.rngState / 4294967296;
}

export function seededNoise(seed, x, y = 0) {
  let n = (seed ^ Math.imul(x + 374761393, 668265263) ^ Math.imul(y + 1274126177, 2246822519)) >>> 0;
  n = Math.imul(n ^ (n >>> 13), 1274126177) >>> 0;
  return ((n ^ (n >>> 16)) >>> 0) / 4294967295;
}

export function deepClone(value) {
  if (typeof structuredClone === "function") return structuredClone(value);
  return JSON.parse(JSON.stringify(value));
}

export function formatTime(totalMinutes) {
  const normalized = ((Math.floor(totalMinutes) % 1440) + 1440) % 1440;
  const hour = Math.floor(normalized / 60);
  const minute = normalized % 60;
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

export function formatStamp(day, minute) {
  return `第 ${day} 日 · ${formatTime(minute)}`;
}

export function getByPath(object, path) {
  return String(path).split(".").reduce((cursor, key) => cursor?.[key], object);
}

export function setByPath(object, path, value) {
  const keys = String(path).split(".");
  const finalKey = keys.pop();
  const parent = keys.reduce((cursor, key) => {
    if (!cursor[key] || typeof cursor[key] !== "object") cursor[key] = {};
    return cursor[key];
  }, object);
  parent[finalKey] = value;
}

export function titleCase(value) {
  return String(value).replace(/(^|[_-])([a-z])/g, (_, space, letter) => `${space ? " " : ""}${letter.toUpperCase()}`);
}

export function pick(items, random = Math.random) {
  if (!items?.length) return undefined;
  return items[Math.floor(random() * items.length) % items.length];
}

export function distance(a, b) {
  return Math.hypot((a.x || 0) - (b.x || 0), (a.y || 0) - (b.y || 0));
}

export function rectanglesOverlap(a, b) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

export function escapeHtml(value) {
  const element = document.createElement("div");
  element.textContent = String(value ?? "");
  return element.innerHTML;
}

export function debounce(fn, delay = 150) {
  let timeout;
  return (...args) => {
    window.clearTimeout(timeout);
    timeout = window.setTimeout(() => fn(...args), delay);
  };
}

export class Emitter {
  constructor() { this.listeners = new Map(); }

  on(event, callback) {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set());
    this.listeners.get(event).add(callback);
    return () => this.listeners.get(event)?.delete(callback);
  }

  emit(event, payload) {
    this.listeners.get(event)?.forEach((callback) => callback(payload));
  }
}
