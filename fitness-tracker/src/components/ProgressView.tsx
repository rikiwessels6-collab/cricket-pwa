import { useMemo, useState } from 'react'
import { useStore } from '../hooks/useStore'
import { addDays, formatShort, fromDateKey, today } from '../lib/dates'
import { averageKcal, totalsFor } from '../lib/nutrition'
import { bestE1RM, exerciseKey, historyFor, workingWeight } from '../lib/progression'
import { setState } from '../lib/store'
import type { Session } from '../lib/types'
import { BarChart, LineChart } from './Charts'

function dateOfLog(sessions: Session[], name: string) {
  const key = exerciseKey(name)
  return sessions
    .filter((s) => s.finishedAt)
    .sort((a, b) => a.startedAt - b.startedAt)
    .flatMap((s) => s.exercises.filter((e) => exerciseKey(e.name) === key).map(() => s.date))
}

export function ProgressView() {
  const data = useStore()
  const { sessions, settings, foods, bodyWeights } = data
  const unit = settings.unit

  const exerciseNames = useMemo(() => {
    const m = new Map<string, string>()
    sessions.filter((s) => s.finishedAt).forEach((s) => s.exercises.forEach((e) => m.set(exerciseKey(e.name), e.name)))
    return [...m.values()].sort()
  }, [sessions])

  const [picked, setPicked] = useState<string>('')
  const exercise = exerciseNames.includes(picked) ? picked : exerciseNames[0]

  const history = exercise ? historyFor(exercise, sessions).filter((h) => workingWeight(h) !== null) : []
  const dates = exercise ? dateOfLog(sessions, exercise) : []
  const weightPts = history.map((h, i) => ({ label: formatShort(dates[i]), value: workingWeight(h)! }))
  const e1rmPts = history.map((h, i) => ({ label: formatShort(dates[i]), value: Math.round(bestE1RM(h)) }))
  const firstW = weightPts[0]?.value
  const lastW = weightPts.at(-1)?.value
  const bestSet = history
    .flatMap((h) => h.setLogs.filter((s) => s.done))
    .reduce<{ weight: number; reps: number } | null>((b, s) => (!b || s.weight > b.weight || (s.weight === b.weight && s.reps > b.reps) ? s : b), null)

  const days = Array.from({ length: 14 }, (_, i) => addDays(today(), i - 13))
  const kcalPts = days.map((d) => ({ label: String(fromDateKey(d).getDate()), value: Math.round(totalsFor(foods, d).kcal) }))
  const avg7 = averageKcal(foods, days.slice(-7))

  const [bw, setBw] = useState('')
  const bwSorted = bodyWeights.slice().sort((a, b) => a.date.localeCompare(b.date))
  const logBw = () => {
    const n = parseFloat(bw)
    if (!Number.isFinite(n) || n <= 0) return
    const d = today()
    setState((s) => ({ ...s, bodyWeights: [...s.bodyWeights.filter((x) => x.date !== d), { date: d, weight: n }] }))
    setBw('')
  }

  const workoutsThisWeek = sessions.filter((s) => s.finishedAt && s.date > addDays(today(), -7)).length

  return (
    <div className="stack">
      <header className="topbar"><h1>Progress</h1></header>

      <section className="card grid3">
        <div className="stat"><b>{workoutsThisWeek}</b><span>workouts, 7 days</span></div>
        <div className="stat"><b>{avg7 ?? '–'}</b><span>avg kcal, 7 days</span></div>
        <div className="stat"><b>{bwSorted.at(-1)?.weight ?? '–'}</b><span>body weight</span></div>
      </section>

      <section className="card stack">
        <h2>Strength</h2>
        {exerciseNames.length === 0 ? (
          <p className="empty">Finish a workout to see your lifts progress here.</p>
        ) : (
          <>
            <select value={exercise} onChange={(e) => setPicked(e.target.value)} aria-label="Exercise">
              {exerciseNames.map((n) => <option key={n}>{n}</option>)}
            </select>
            <div className="grid3">
              <div className="stat"><b>{lastW} {unit}</b><span>working weight</span></div>
              <div className="stat">
                <b style={{ color: lastW! > firstW! ? 'var(--ok)' : undefined }}>{lastW! - firstW! >= 0 ? '+' : ''}{Math.round((lastW! - firstW!) * 100) / 100}</b>
                <span>since first</span>
              </div>
              <div className="stat"><b>{bestSet ? `${bestSet.weight}×${bestSet.reps}` : '–'}</b><span>heaviest set</span></div>
            </div>
            <LineChart
              label={`${exercise} progress`}
              series={[
                { name: 'Working weight', color: 'var(--accent)', points: weightPts },
                { name: 'Est. 1RM', color: 'var(--chart-2)', points: e1rmPts, dashed: true },
              ]}
            />
            <div className="legend">
              <span><i style={{ background: 'var(--accent)' }} />Working weight</span>
              <span><i style={{ background: 'var(--chart-2)' }} />Est. 1-rep max</span>
            </div>
          </>
        )}
      </section>

      <section className="card stack">
        <div className="row spread"><h2>Calories</h2><span className="muted small">last 14 days</span></div>
        <BarChart points={kcalPts} goal={settings.calorieGoal} label="Daily calories, last 14 days" />
      </section>

      <section className="card stack">
        <h2>Body weight</h2>
        <div className="row">
          <input className="grow" inputMode="decimal" placeholder={`Today's weight (${unit})`} value={bw} onChange={(e) => setBw(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && logBw()} />
          <button className="btn primary" onClick={logBw}>Log</button>
        </div>
        {bwSorted.length > 1 && (
          <LineChart label="Body weight" series={[{ name: 'Body weight', color: 'var(--accent)', points: bwSorted.slice(-30).map((b) => ({ label: formatShort(b.date), value: b.weight })) }]} />
        )}
      </section>
    </div>
  )
}
