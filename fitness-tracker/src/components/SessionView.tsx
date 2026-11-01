import { useEffect, useRef, useState } from 'react'
import { useStore } from '../hooks/useStore'
import { historyFor } from '../lib/progression'
import { setState } from '../lib/store'
import type { ExerciseLog, Session, SetLog } from '../lib/types'
import { finishSession } from '../lib/workouts'

const LABELS = { start: 'First time', increase: 'Weight up', hold: 'Chase reps', retry: 'Retry', deload: 'Deload' }

function updateActive(fn: (s: Session) => Session) {
  setState((d) => (d.activeSession ? { ...d, activeSession: fn(d.activeSession) } : d))
}

function updateExercise(i: number, fn: (e: ExerciseLog) => ExerciseLog) {
  updateActive((s) => ({ ...s, exercises: s.exercises.map((e, j) => (j === i ? fn(e) : e)) }))
}

function Stepper({ value, step, onChange, label }: { value: number; step: number; onChange: (n: number) => void; label: string }) {
  // Draft text while the field is being typed in; otherwise show the stored value.
  const [draft, setDraft] = useState<string | null>(null)
  const commit = (n: number) => onChange(Math.max(0, Math.round(n * 100) / 100))
  return (
    <div className="stepper">
      <button aria-label={`Decrease ${label}`} onClick={() => commit(value - step)}>−</button>
      <input
        aria-label={label} inputMode="decimal" className="num" value={draft ?? String(value)}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={() => { const n = parseFloat(draft ?? ''); if (draft !== null && Number.isFinite(n)) commit(n); setDraft(null) }}
        onFocus={(e) => e.target.select()}
      />
      <button aria-label={`Increase ${label}`} onClick={() => commit(value + step)}>+</button>
    </div>
  )
}

export function SessionView({ session, onFinished }: { session: Session; onFinished: (id: string) => void }) {
  const { sessions, settings } = useStore()
  const [restEnd, setRestEndState] = useState<number | null>(null)
  const restRef = useRef<number | null>(null)
  const [now, setNow] = useState(() => Date.now())

  const setRestEnd = (v: number | null) => {
    restRef.current = v
    setRestEndState(v)
  }

  useEffect(() => {
    const t = setInterval(() => {
      const n = Date.now()
      setNow(n)
      if (restRef.current && n >= restRef.current) {
        restRef.current = null
        setRestEndState(null)
        navigator.vibrate?.(300)
      }
    }, 500)
    return () => clearInterval(t)
  }, [])

  const restLeft = restEnd ? Math.ceil((restEnd - now) / 1000) : 0

  const elapsed = Math.floor((now - session.startedAt) / 60000)
  const doneSets = session.exercises.reduce((t, e) => t + e.setLogs.filter((s) => s.done).length, 0)
  const totalSets = session.exercises.reduce((t, e) => t + e.setLogs.length, 0)

  const toggleSet = (ei: number, si: number) => {
    const wasDone = session.exercises[ei].setLogs[si].done
    updateExercise(ei, (e) => ({ ...e, setLogs: e.setLogs.map((s, j) => (j === si ? { ...s, done: !s.done } : s)) }))
    if (!wasDone && settings.restSeconds > 0) setRestEnd(Date.now() + settings.restSeconds * 1000)
  }

  const finish = () => {
    if (doneSets === 0) {
      alert('Tick off at least one set before finishing, or discard the workout.')
      return
    }
    if (doneSets < totalSets && !confirm(`${totalSets - doneSets} set(s) not ticked off. They'll count as missed for progression. Finish anyway?`)) return
    const done = finishSession(session)
    setState((d) => ({ ...d, sessions: [...d.sessions, done], activeSession: null }))
    onFinished(done.id)
  }

  const discard = () => {
    if (confirm('Discard this workout? Nothing will be saved.')) setState((d) => ({ ...d, activeSession: null }))
  }

  return (
    <div className="stack">
      <header className="topbar">
        <div>
          <h1>{session.templateName}</h1>
          <div className="muted small num">{elapsed} min · {doneSets}/{totalSets} sets</div>
        </div>
        <button className="btn primary" onClick={finish}>Finish</button>
      </header>

      {session.exercises.map((ex, ei) => {
        const prev = historyFor(ex.name, sessions).at(-1)
        const step = ex.increment > 0 ? ex.increment : 1
        return (
          <section key={ex.planId + ei} className="card stack" style={{ gap: 10 }}>
            <div className="row spread" style={{ alignItems: 'flex-start' }}>
              <div className="grow">
                <h2>{ex.name}</h2>
                <div className="muted small">
                  Target {ex.sets}×{ex.repMin}–{ex.repMax} @ {ex.targetWeight} {settings.unit}
                </div>
              </div>
              {ex.suggestKind && <span className={`chip ${ex.suggestKind}`}>{LABELS[ex.suggestKind]}</span>}
            </div>
            {ex.suggestReason && ex.suggestKind !== 'start' && <p className="small muted">{ex.suggestReason}.</p>}
            {prev && (
              <p className="small muted num">
                Last time: {prev.setLogs.filter((s) => s.done).map((s) => `${s.weight}×${s.reps}`).join(', ')}
              </p>
            )}

            <div className="set-row head"><span className="center">Set</span><span>{settings.unit}</span><span>Reps</span><span /></div>
            {ex.setLogs.map((s: SetLog, si) => (
              <div key={si} className={`set-row${s.done ? ' done' : ''}`}>
                <span className="idx">{si + 1}</span>
                <Stepper
                  label={`Set ${si + 1} weight`} value={s.weight} step={step}
                  onChange={(w) => updateExercise(ei, (e) => ({
                    ...e,
                    // Changing an unticked set's weight carries forward to later unticked sets.
                    setLogs: e.setLogs.map((x, j) => (j === si || (j > si && !x.done) ? { ...x, weight: w } : x)),
                  }))}
                />
                <Stepper
                  label={`Set ${si + 1} reps`} value={s.reps} step={1}
                  onChange={(r) => updateExercise(ei, (e) => ({ ...e, setLogs: e.setLogs.map((x, j) => (j === si ? { ...x, reps: Math.round(r) } : x)) }))}
                />
                <button className="check" aria-pressed={s.done} aria-label={`Set ${si + 1} done`} onClick={() => toggleSet(ei, si)}>✓</button>
              </div>
            ))}
            <div className="row">
              <button
                className="btn sm"
                onClick={() => updateExercise(ei, (e) => {
                  const last = e.setLogs.at(-1) ?? { weight: e.targetWeight, reps: e.repMin, done: false }
                  return { ...e, setLogs: [...e.setLogs, { ...last, done: false }] }
                })}
              >+ Set</button>
              {ex.setLogs.length > 1 && (
                <button className="btn sm ghost" onClick={() => updateExercise(ei, (e) => ({ ...e, setLogs: e.setLogs.slice(0, -1) }))}>Remove set</button>
              )}
            </div>
          </section>
        )
      })}

      <button className="btn danger block" onClick={discard}>Discard workout</button>

      {restEnd && restLeft > 0 && (
        <div className="rest" role="timer" aria-live="off">
          <span className="num">Rest {Math.floor(restLeft / 60)}:{String(restLeft % 60).padStart(2, '0')}</span>
          <button onClick={() => setRestEnd(restEnd + 30000)}>+30s</button>
          <button onClick={() => setRestEnd(null)}>Skip</button>
        </div>
      )}
    </div>
  )
}
