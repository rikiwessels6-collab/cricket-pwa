import { today } from './dates'
import { newId } from './id'
import { historyFor, suggestNext } from './progression'
import type { ExerciseLog, Session, WorkoutTemplate } from './types'

/**
 * Builds a new session from a template, pre-filling each exercise with the
 * progression engine's suggested weight.
 */
export function buildSession(template: WorkoutTemplate, pastSessions: Session[], now = Date.now()): Session {
  const exercises: ExerciseLog[] = template.exercises.map((plan) => {
    const history = historyFor(plan.name, pastSessions)
    const s = suggestNext(plan, history)
    const last = history[history.length - 1]
    // When repeating a weight, start from last time's reps so you can see what to beat.
    const repeating = s.kind === 'hold' || s.kind === 'retry'
    const setLogs = Array.from({ length: plan.sets }, (_, i) => ({
      weight: s.weight,
      reps: repeating && last?.setLogs[i] ? last.setLogs[i].reps : plan.repMin,
      done: false,
    }))
    return {
      planId: plan.id,
      name: plan.name,
      sets: plan.sets,
      repMin: plan.repMin,
      repMax: plan.repMax,
      increment: plan.increment,
      targetWeight: s.weight,
      suggestKind: s.kind,
      suggestReason: s.reason,
      setLogs,
    }
  })
  return {
    id: newId(),
    templateId: template.id,
    templateName: template.name,
    date: today(),
    startedAt: now,
    exercises,
  }
}

/** Marks a session finished; only finished sessions feed progression. */
export function finishSession(session: Session, now = Date.now()): Session {
  return { ...session, finishedAt: now }
}
