import { useRef, useState } from 'react'
import { useStore } from '../hooks/useStore'
import { today } from '../lib/dates'
import { defaultData } from '../lib/defaults'
import { getState, parseData, replaceState, setState } from '../lib/store'
import type { Settings } from '../lib/types'

function Field({ label, value, onChange }: { label: string; value: number; onChange: (n: number) => void }) {
  const [text, setText] = useState(String(value))
  return (
    <label>{label}
      <input inputMode="numeric" value={text}
        onChange={(e) => { setText(e.target.value); const n = parseFloat(e.target.value); if (Number.isFinite(n) && n >= 0) onChange(n) }}
        onBlur={() => setText(String(value))} />
    </label>
  )
}

export function SettingsView() {
  const { settings } = useStore()
  const fileRef = useRef<HTMLInputElement>(null)
  const [msg, setMsg] = useState('')
  const set = (patch: Partial<Settings>) => setState((s) => ({ ...s, settings: { ...s.settings, ...patch } }))

  const exportData = async () => {
    const json = JSON.stringify(getState(), null, 2)
    const file = new File([json], `lift-and-log-${today()}.json`, { type: 'application/json' })
    // On iPhone the share sheet lets you save straight to Files / iCloud Drive.
    if (navigator.canShare?.({ files: [file] })) {
      try { await navigator.share({ files: [file], title: 'Lift & Log backup' }); return } catch { /* cancelled */ return }
    }
    const a = document.createElement('a')
    a.href = URL.createObjectURL(file)
    a.download = file.name
    a.click()
    URL.revokeObjectURL(a.href)
  }

  const importData = async (f: File) => {
    try {
      const next = parseData(await f.text())
      if (!confirm('Replace all current data with this backup?')) return
      replaceState(next)
      setMsg('Backup restored.')
    } catch (e) {
      setMsg(`Couldn't import: ${(e as Error).message}`)
    }
  }

  return (
    <div className="stack">
      <header className="topbar"><h1>Settings</h1></header>

      <section className="card stack">
        <h2>Goals</h2>
        <div className="grid2">
          <Field label="Daily calories (kcal)" value={settings.calorieGoal} onChange={(n) => set({ calorieGoal: n })} />
          <Field label="Daily protein (g)" value={settings.proteinGoal} onChange={(n) => set({ proteinGoal: n })} />
        </div>
      </section>

      <section className="card stack">
        <h2>Training</h2>
        <div>
          <label>Weight unit</label>
          <div className="seg" role="group" aria-label="Weight unit" style={{ marginTop: 4 }}>
            {(['kg', 'lb'] as const).map((u) => (
              <button key={u} aria-pressed={settings.unit === u} onClick={() => set({ unit: u })}>{u}</button>
            ))}
          </div>
          <p className="muted small" style={{ marginTop: 6 }}>Changes the label only — logged numbers aren't converted.</p>
        </div>
        <Field label="Rest timer (seconds, 0 = off)" value={settings.restSeconds} onChange={(n) => set({ restSeconds: Math.round(n) })} />
      </section>

      <section className="card stack">
        <h2>Your data</h2>
        <p className="muted small">Everything is stored only on this device. Export a backup now and then so you never lose your history.</p>
        <div className="grid2">
          <button className="btn" onClick={exportData}>Export backup</button>
          <button className="btn" onClick={() => fileRef.current?.click()}>Import backup</button>
        </div>
        <input ref={fileRef} type="file" accept="application/json,.json" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) importData(f); e.target.value = '' }} />
        {msg && <p className="small">{msg}</p>}
        <button className="btn danger" onClick={() => { if (confirm('Erase ALL food, workouts and history? This cannot be undone.')) replaceState(defaultData()) }}>
          Erase all data
        </button>
      </section>

      <section className="card stack small muted">
        <h2 style={{ color: 'var(--text)' }}>Install on iPhone</h2>
        <p>Open this page in Safari, tap the Share button, then <b>Add to Home Screen</b>. It then opens full-screen and works offline.</p>
      </section>
    </div>
  )
}
