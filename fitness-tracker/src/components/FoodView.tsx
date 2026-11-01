import { useMemo, useState } from 'react'
import { useStore } from '../hooks/useStore'
import { addDays, formatDay, today } from '../lib/dates'
import { newId } from '../lib/id'
import { totalsFor } from '../lib/nutrition'
import { setState } from '../lib/store'
import type { FoodEntry, Meal, SavedFood } from '../lib/types'

const MEALS: { id: Meal; label: string }[] = [
  { id: 'breakfast', label: 'Breakfast' },
  { id: 'lunch', label: 'Lunch' },
  { id: 'dinner', label: 'Dinner' },
  { id: 'snack', label: 'Snacks' },
]

function guessMeal(): Meal {
  const h = new Date().getHours()
  if (h < 11) return 'breakfast'
  if (h < 15) return 'lunch'
  if (h < 21) return 'dinner'
  return 'snack'
}

function numOrUndef(v: string): number | undefined {
  const n = parseFloat(v)
  return Number.isFinite(n) && n >= 0 ? n : undefined
}

function Ring({ value, goal }: { value: number; goal: number }) {
  const r = 50
  const c = 2 * Math.PI * r
  const pct = goal > 0 ? Math.min(value / goal, 1) : 0
  const over = value > goal
  return (
    <svg className="ring" viewBox="0 0 120 120" role="img" aria-label={`${value} of ${goal} kcal`}>
      <circle cx="60" cy="60" r={r} fill="none" stroke="var(--surface-2)" strokeWidth="12" />
      <circle
        cx="60" cy="60" r={r} fill="none"
        stroke={over ? 'var(--danger)' : 'var(--accent)'} strokeWidth="12" strokeLinecap="round"
        strokeDasharray={`${c * pct} ${c}`} transform="rotate(-90 60 60)"
      />
      <text x="60" y="58" textAnchor="middle" fontSize="22" fontWeight="700" fill="var(--text)">{Math.round(value)}</text>
      <text x="60" y="78" textAnchor="middle" fontSize="11" fill="var(--text-muted)">kcal eaten</text>
    </svg>
  )
}

export function FoodView() {
  const { foods, savedFoods, settings } = useStore()
  const [date, setDate] = useState(today())
  const [adding, setAdding] = useState(false)
  const totals = totalsFor(foods, date)
  const dayFoods = foods.filter((f) => f.date === date)
  const remaining = settings.calorieGoal - totals.kcal

  return (
    <div className="stack">
      <header className="topbar">
        <button className="icon-btn" aria-label="Previous day" onClick={() => setDate(addDays(date, -1))}>‹</button>
        <h1 className="center">{formatDay(date)}</h1>
        <button className="icon-btn" aria-label="Next day" disabled={date >= today()} onClick={() => setDate(addDays(date, 1))}>›</button>
      </header>

      <section className="card ring-wrap">
        <Ring value={totals.kcal} goal={settings.calorieGoal} />
        <div className="grow stack" style={{ gap: 8 }}>
          <div>
            <div className="num" style={{ fontSize: '1.5rem', fontWeight: 700, color: remaining < 0 ? 'var(--danger)' : undefined }}>
              {Math.abs(Math.round(remaining))}
            </div>
            <div className="muted small">{remaining < 0 ? 'kcal over goal' : 'kcal remaining'} · goal {settings.calorieGoal}</div>
          </div>
          <div>
            <div className="row spread small"><span>Protein</span><span className="num">{Math.round(totals.protein)} / {settings.proteinGoal} g</span></div>
            <div className="bar"><span style={{ width: `${Math.min(100, (totals.protein / Math.max(1, settings.proteinGoal)) * 100)}%` }} /></div>
          </div>
          <div className="row small muted num" style={{ gap: 14 }}>
            <span>Carbs {Math.round(totals.carbs)} g</span>
            <span>Fat {Math.round(totals.fat)} g</span>
          </div>
        </div>
      </section>

      {adding ? (
        <AddFood date={date} savedFoods={savedFoods} onClose={() => setAdding(false)} />
      ) : (
        <button className="btn primary block" onClick={() => setAdding(true)}>+ Add food</button>
      )}

      {MEALS.map((m) => {
        const items = dayFoods.filter((f) => f.meal === m.id)
        if (items.length === 0) return null
        const kcal = items.reduce((t, f) => t + f.kcal, 0)
        return (
          <section key={m.id} className="card flush">
            <div className="row spread" style={{ padding: '10px 14px 4px' }}>
              <h3>{m.label}</h3>
              <span className="muted small num">{Math.round(kcal)} kcal</span>
            </div>
            <ul className="list">
              {items.map((f) => (
                <li key={f.id}>
                  <div className="grow">
                    <div>{f.name}</div>
                    {(f.protein || f.carbs || f.fat) ? (
                      <div className="muted small num">
                        P {f.protein ?? 0} · C {f.carbs ?? 0} · F {f.fat ?? 0}
                      </div>
                    ) : null}
                  </div>
                  <span className="num">{Math.round(f.kcal)}</span>
                  <button
                    className="btn ghost sm danger" aria-label={`Delete ${f.name}`}
                    onClick={() => setState((s) => ({ ...s, foods: s.foods.filter((x) => x.id !== f.id) }))}
                  >✕</button>
                </li>
              ))}
            </ul>
          </section>
        )
      })}
      {dayFoods.length === 0 && !adding && <p className="empty">Nothing logged for {formatDay(date).toLowerCase()} yet.</p>}
    </div>
  )
}

function AddFood({ date, savedFoods, onClose }: { date: string; savedFoods: SavedFood[]; onClose: () => void }) {
  const [meal, setMeal] = useState<Meal>(guessMeal)
  const [name, setName] = useState('')
  const [kcal, setKcal] = useState('')
  const [protein, setProtein] = useState('')
  const [carbs, setCarbs] = useState('')
  const [fat, setFat] = useState('')
  const [servings, setServings] = useState('1')
  const [remember, setRemember] = useState(true)

  const matches = useMemo(() => {
    const q = name.trim().toLowerCase()
    const list = q ? savedFoods.filter((f) => f.name.toLowerCase().includes(q)) : savedFoods
    return list.slice(0, 8)
  }, [name, savedFoods])

  const fill = (f: SavedFood) => {
    setName(f.name)
    setKcal(String(f.kcal))
    setProtein(f.protein != null ? String(f.protein) : '')
    setCarbs(f.carbs != null ? String(f.carbs) : '')
    setFat(f.fat != null ? String(f.fat) : '')
    setRemember(false)
  }

  const k = numOrUndef(kcal)
  const mult = numOrUndef(servings) ?? 1
  const canSave = name.trim() !== '' && k !== undefined && mult > 0

  const save = () => {
    if (!canSave) return
    const scale = (n?: number) => (n === undefined ? undefined : Math.round(n * mult * 10) / 10)
    const per = { name: name.trim(), kcal: k!, protein: numOrUndef(protein), carbs: numOrUndef(carbs), fat: numOrUndef(fat) }
    const entry: FoodEntry = {
      id: newId(), date, meal,
      name: mult === 1 ? per.name : `${per.name} ×${mult}`,
      kcal: Math.round(per.kcal * mult),
      protein: scale(per.protein), carbs: scale(per.carbs), fat: scale(per.fat),
    }
    setState((s) => {
      let saved = s.savedFoods
      if (remember) {
        const existing = saved.find((x) => x.name.toLowerCase() === per.name.toLowerCase())
        saved = existing
          ? saved.map((x) => (x === existing ? { ...existing, ...per } : x))
          : [{ id: newId(), ...per }, ...saved]
      }
      return { ...s, foods: [...s.foods, entry], savedFoods: saved }
    })
    onClose()
  }

  return (
    <section className="card stack">
      <div className="row spread">
        <h2>Add food</h2>
        <button className="btn ghost sm" onClick={onClose}>Cancel</button>
      </div>
      <div className="seg" role="group" aria-label="Meal">
        {MEALS.map((m) => (
          <button key={m.id} aria-pressed={meal === m.id} onClick={() => setMeal(m.id)}>{m.label.replace('Snacks', 'Snack')}</button>
        ))}
      </div>
      <label>Food
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Chicken breast 200g" autoFocus />
      </label>
      {matches.length > 0 && (
        <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
          {matches.map((f) => (
            <button key={f.id} className="btn sm" onClick={() => fill(f)}>{f.name} · {f.kcal}</button>
          ))}
        </div>
      )}
      <div className="grid2">
        <label>Calories (kcal)
          <input inputMode="decimal" value={kcal} onChange={(e) => setKcal(e.target.value)} placeholder="0" />
        </label>
        <label>Servings
          <input inputMode="decimal" value={servings} onChange={(e) => setServings(e.target.value)} />
        </label>
      </div>
      <div className="grid3">
        <label>Protein g<input inputMode="decimal" value={protein} onChange={(e) => setProtein(e.target.value)} /></label>
        <label>Carbs g<input inputMode="decimal" value={carbs} onChange={(e) => setCarbs(e.target.value)} /></label>
        <label>Fat g<input inputMode="decimal" value={fat} onChange={(e) => setFat(e.target.value)} /></label>
      </div>
      <label className="row" style={{ color: 'var(--text)' }}>
        <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} style={{ width: 22, minHeight: 22 }} />
        Save to My Foods for quick adding
      </label>
      <button className="btn primary block" disabled={!canSave} onClick={save}>
        Add{k !== undefined ? ` · ${Math.round(k * mult)} kcal` : ''}
      </button>
    </section>
  )
}
