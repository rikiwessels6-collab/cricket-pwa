import { useState } from 'react'
import { useStore } from '../hooks/useStore'
import { formatDay } from '../lib/dates'
import { historyFor, suggestNext, volume, type Suggestion } from '../lib/progression'
import { setState } from '../lib/store'
import type { Session, WorkoutTemplate } from '../lib/types'
import { buildSession } from '../lib/workouts'
import { SessionView } from './SessionView'
import { TemplateEditor } from './TemplateEditor'

export function TrainView() {
  const data = useStore()
  const [editing, setEditing] = useState<WorkoutTemplate | 'new' | null>(null)
  const [summaryId, setSummaryId] = useState<string | null>(null)
  const unit = data.settings.unit

  if (data.activeSession) {
    return <SessionView session={data.activeSession} onFinished={(id) => setSummaryId(id)} />
  }
  if (editing) {
    return <TemplateEditor template={editing === 'new' ? null : editing} onClose={() => setEditing(null)} />
  }

  const finished = data.sessions.filter((s) => s.finishedAt).sort((a, b) => b.startedAt - a.startedAt)
  const summary = summaryId ? finished.find((s) => s.id === summaryId) : undefined

  const start = (t: WorkoutTemplate) => {
    setSummaryId(null)
    setState((s) => ({ ...s, activeSession: buildSession(t, s.sessions) }))
  }

  return (
    <div className="stack">
      <header className="topbar">
        <h1>Train</h1>
        <button className="btn sm" onClick={() => setEditing('new')}>+ Workout</button>
      </header>

      {summary && <SessionSummary session={summary} onClose={() => setSummaryId(null)} />}

      {data.templates.length === 0 && <p className="empty">No workouts yet. Create one to get started.</p>}

      {data.templates.map((t) => {
        const last = finished.find((s) => s.templateId === t.id)
        return (
          <section key={t.id} className="card stack" style={{ gap: 10 }}>
            <div className="row spread">
              <div>
                <h2>{t.name}</h2>
                <div className="muted small">{last ? `Last done ${formatDay(last.date).toLowerCase()}` : 'Not done yet'}</div>
              </div>
              <button className="btn ghost sm" onClick={() => setEditing(t)}>Edit</button>
            </div>
            <ul className="list" style={{ margin: '0 -14px' }}>
              {t.exercises.map((p) => {
                const s = suggestNext(p, historyFor(p.name, data.sessions))
                return (
                  <li key={p.id} style={{ padding: '6px 14px' }}>
                    <span className="grow">{p.name}</span>
                    <span className="muted small num">{p.sets}×{p.repMin}–{p.repMax}</span>
                    <b className="num">{s.weight} {unit}</b>
                    <KindDot kind={s.kind} />
                  </li>
                )
              })}
            </ul>
            <button className="btn primary block" onClick={() => start(t)} disabled={t.exercises.length === 0}>Start workout</button>
          </section>
        )
      })}

      {finished.length > 0 && (
        <section className="card flush">
          <h2 style={{ padding: '12px 14px 4px' }}>History</h2>
          <ul className="list">
            {finished.slice(0, 15).map((s) => (
              <HistoryItem key={s.id} session={s} unit={unit} />
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}

function KindDot({ kind }: { kind: Suggestion['kind'] }) {
  const sym = { increase: '▲', deload: '▼', retry: '↻', hold: '•', start: '•' }[kind]
  return <span className={`chip ${kind}`} style={{ padding: '0 6px', minWidth: 22, justifyContent: 'center' }} aria-label={kind}>{sym}</span>
}

function HistoryItem({ session, unit }: { session: Session; unit: string }) {
  const [open, setOpen] = useState(false)
  const mins = session.finishedAt ? Math.round((session.finishedAt - session.startedAt) / 60000) : 0
  const vol = session.exercises.reduce((t, e) => t + volume(e), 0)
  return (
    <li style={{ display: 'block' }}>
      <button onClick={() => setOpen(!open)} style={{ all: 'unset', cursor: 'pointer', display: 'flex', width: '100%', alignItems: 'center', gap: 10 }}>
        <span className="grow"><b>{session.templateName}</b> <span className="muted small">· {formatDay(session.date)}</span></span>
        <span className="muted small num">{mins} min · {Math.round(vol).toLocaleString()} {unit}</span>
      </button>
      {open && (
        <div className="stack small" style={{ gap: 4, marginTop: 8 }}>
          {session.exercises.map((e) => (
            <div key={e.planId} className="row spread">
              <span>{e.name}</span>
              <span className="num muted">
                {e.setLogs.filter((x) => x.done).map((x) => `${x.weight}×${x.reps}`).join(', ') || 'skipped'}
              </span>
            </div>
          ))}
          <button
            className="btn ghost sm danger" style={{ alignSelf: 'flex-start', paddingLeft: 0 }}
            onClick={() => {
              if (confirm('Delete this workout from history? Future weight suggestions will be recalculated.')) {
                setState((s) => ({ ...s, sessions: s.sessions.filter((x) => x.id !== session.id) }))
              }
            }}
          >Delete workout</button>
        </div>
      )}
    </li>
  )
}

function SessionSummary({ session, onClose }: { session: Session; onClose: () => void }) {
  const data = useStore()
  const template = data.templates.find((t) => t.id === session.templateId)
  return (
    <section className="card stack" style={{ borderColor: 'var(--ok)' }}>
      <div className="row spread">
        <h2>Workout saved 💪</h2>
        <button className="btn ghost sm" onClick={onClose}>Done</button>
      </div>
      <p className="muted small">Next time:</p>
      {session.exercises.map((e) => {
        const plan = template?.exercises.find((p) => p.id === e.planId)
        if (!plan) return null
        const s = suggestNext(plan, historyFor(plan.name, data.sessions))
        return (
          <div key={e.planId} className="row spread">
            <span className="grow">{e.name}</span>
            <b className="num">{s.weight} {data.settings.unit}</b>
            <span className={`chip ${s.kind}`}>{s.kind === 'increase' ? `+${plan.increment}` : s.kind}</span>
          </div>
        )
      })}
    </section>
  )
}
