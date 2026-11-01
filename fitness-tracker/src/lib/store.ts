import { defaultData } from './defaults'
import type { AppData } from './types'

export const STORAGE_KEY = 'lift-and-log:v1'

type Listener = () => void
const listeners = new Set<Listener>()

function load(): AppData {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return parseData(raw)
  } catch {
    /* fall through to defaults */
  }
  return defaultData()
}

/** Validates and fills gaps in imported / stored JSON. Throws on garbage. */
export function parseData(raw: string): AppData {
  const obj = JSON.parse(raw)
  if (!obj || typeof obj !== 'object' || obj.version !== 1) throw new Error('Not a Lift & Log backup')
  const base = defaultData()
  return {
    version: 1,
    settings: { ...base.settings, ...obj.settings },
    foods: Array.isArray(obj.foods) ? obj.foods : [],
    savedFoods: Array.isArray(obj.savedFoods) ? obj.savedFoods : [],
    templates: Array.isArray(obj.templates) ? obj.templates : base.templates,
    sessions: Array.isArray(obj.sessions) ? obj.sessions : [],
    activeSession: obj.activeSession ?? null,
    bodyWeights: Array.isArray(obj.bodyWeights) ? obj.bodyWeights : [],
  }
}

let state: AppData = typeof localStorage === 'undefined' ? defaultData() : load()

export function getState(): AppData {
  return state
}

export function setState(update: (s: AppData) => AppData): void {
  state = update(state)
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
  } catch {
    /* storage full or unavailable — keep in memory */
  }
  listeners.forEach((l) => l())
}

export function replaceState(next: AppData): void {
  setState(() => next)
}

export function subscribe(l: Listener): () => void {
  listeners.add(l)
  return () => listeners.delete(l)
}

/** Ask the browser not to evict our data (helps on iOS). */
export function requestPersistence(): void {
  navigator.storage?.persist?.().catch(() => {})
}
