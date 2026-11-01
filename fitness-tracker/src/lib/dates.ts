import type { DateKey } from './types'

export function toDateKey(d: Date): DateKey {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

export function today(): DateKey {
  return toDateKey(new Date())
}

export function fromDateKey(key: DateKey): Date {
  const [y, m, d] = key.split('-').map(Number)
  return new Date(y, m - 1, d)
}

export function addDays(key: DateKey, days: number): DateKey {
  const d = fromDateKey(key)
  d.setDate(d.getDate() + days)
  return toDateKey(d)
}

export function formatDay(key: DateKey): string {
  if (key === today()) return 'Today'
  if (key === addDays(today(), -1)) return 'Yesterday'
  return fromDateKey(key).toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' })
}

export function formatShort(key: DateKey): string {
  return fromDateKey(key).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
}
