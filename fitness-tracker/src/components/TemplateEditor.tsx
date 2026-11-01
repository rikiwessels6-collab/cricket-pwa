import { useMemo, useState } from 'react'
import { useStore } from '../hooks/useStore'
import { newId } from '../lib/id'
import { setState } from '../lib/store'
import type { ExercisePlan, WorkoutTemplate } from '../lib/types'

function blankPlan(unit: string): ExercisePlan {
  return { id: newId(), name: '', sets: 3, repMin: 8, repMax: 12, increment: unit === 'lb' ? 5 : 2.5, startWeight: 20 }
}

function NumField({ label, value, onChange }: { label: string; value: number; onChange: (n: number) => void }) {
  const [text, setText] = useState(String(value))
  return (
    <label>{label}
      <input
        inputMode="decimal" value={text}
        onChange={(e) => { setText(e.target.value); const n = parseFloat(e.target.value); if (Number.isFinite(n) && n >= 0) onChange(n) }}
        onBlur={() => setText(String(value))}
      />
    </label>
  )
}

export function TemplateEditor({ template, onClose }: { template: WorkoutTemplate | null; onClose: () => void }) {
  const { settings, sessions, templates } = useStore()
  const [name, setName] = useState(template?.name ?? '')
  const [plans, setPlans] = useState<ExercisePlan[]>(template?.exercises ?? [blankPlan(settings.unit)])

  const knownNames = useMemo(() => {
    const set = new Set<string>()
    templates.forEach((t) => t.exercises.forEach((e) => set.add(e.name)))
    sessions.forEach((s) => s.exercises.forEach((e) => set.add(e.name)))
    return [...set].sort()
  }, [templates, sessions])

  const update = (i: number, patch: Partial<ExercisePlan>) => setPlans(plans.map((p, j) => (j === i ? { ...p, ...patch } : p)))
  const move = (i: number, d: number) => {
    const j = i + d
    if (j < 0 || j >= plans.length) return
    const next = plans.slice()
    ;[next[i], next[j]] = [next[j], next[i]]
    setPlans(next)
  }

  const cleaned = plans
    .filter((p) => p.name.trim())
    .map((p) => ({ ...p, name: p.name.trim(), sets: Math.max(1, Math.round(p.sets)), repMin: Math.round(p.repMin), repMax: Math.max(Math.round(p.repMin), Math.round(p.repMax)) }))
  const canSave = name.trim() !== '' && cleaned.length > 0

  const save = () => {
    const t: WorkoutTemplate = { id: template?.id ?? newId(), name: name.trim(), exercises: cleaned }
    setState((s) => ({
      ...s,
      templates: template ? s.templates.map((x) => (x.id === t.id ? t : x)) : [...s.templates, t],
    }))
    onClose()
  }

  const remove = () => {
    if (!template || !confirm(`Delete "${template.name}"? Your workout history is kept.`)) return
    setState((s) => ({ ...s, templates: s.templates.filter((x) => x.id !== template.id) }))
    onClose()
  }

  return (
    <div className="stack">
      <header className="topbar">
        <button className="btn ghost" onClick={onClose} style={{ paddingLeft: 0 }}>‹ Back</button>
        <button className="btn primary" disabled={!canSave} onClick={save}>Save</button>
      </header>
      <label>Workout name
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Push Day" />
      </label>

      <datalist id="exercise-names">{knownNames.map((n) => <option key={n} value={n} />)}</datalist>

      {plans.map((p, i) => (
        <section key={p.id} className="card stack" style={{ gap: 10 }}>
          <div className="row">
            <label className="grow">Exercise {i + 1}
              <input list="exercise-names" value={p.name} onChange={(e) => update(i, { name: e.target.value })} placeholder="e.g. Bench Press" />
            </label>
          </div>
          <div className="grid3">
            <NumField label="Sets" value={p.sets} onChange={(n) => update(i, { sets: n })} />
            <NumField label="Min reps" value={p.repMin} onChange={(n) => update(i, { repMin: n })} />
            <NumField label="Max reps" value={p.repMax} onChange={(n) => update(i, { repMax: n })} />
          </div>
          <div className="grid2">
            <NumField label={`Start weight (${settings.unit})`} value={p.startWeight} onChange={(n) => update(i, { startWeight: n })} />
            <NumField label={`Increase by (${settings.unit})`} value={p.increment} onChange={(n) => update(i, { increment: n })} />
          </div>
          <div className="row spread">
            <div className="row" style={{ gap: 4 }}>
              <button className="icon-btn" aria-label="Move up" onClick={() => move(i, -1)} disabled={i === 0}>↑</button>
              <button className="icon-btn" aria-label="Move down" onClick={() => move(i, 1)} disabled={i === plans.length - 1}>↓</button>
            </div>
            <button className="btn ghost sm danger" onClick={() => setPlans(plans.filter((_, j) => j !== i))}>Remove</button>
          </div>
        </section>
      ))}

      <button className="btn block" onClick={() => setPlans([...plans, blankPlan(settings.unit)])}>+ Add exercise</button>
      <p className="muted small">
        Weights progress automatically: when you hit <b>max reps on every set</b>, the next session adds the increase.
        In between, keep the weight and add reps. Miss <b>min reps</b> twice in a row and it drops ~10% so you can rebuild.
        Start weight is only used the first time you do an exercise — after that, your history decides.
      </p>
      {template && <button className="btn danger block" onClick={remove}>Delete workout</button>}
    </div>
  )
}
