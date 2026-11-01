import type { ExerciseLog, ExercisePlan, Session } from './types'

export type SuggestionKind = 'start' | 'increase' | 'hold' | 'retry' | 'deload'

export interface Suggestion {
  weight: number
  kind: SuggestionKind
  reason: string
}

/** Fraction of working weight kept after two failed sessions in a row. */
export const DELOAD_FACTOR = 0.9

/** Exercises are matched across templates by name, case-insensitively. */
export function exerciseKey(name: string): string {
  return name.trim().toLowerCase().replace(/\s+/g, ' ')
}

/** Round to 2 dp to avoid float noise like 62.50000001. */
function tidy(n: number): number {
  return Math.round(n * 100) / 100
}

function roundDownTo(n: number, step: number): number {
  if (step <= 0) return tidy(n)
  return tidy(Math.floor(n / step + 1e-9) * step)
}

export type Outcome = 'hit-top' | 'hit-min' | 'missed'

/**
 * The weight an exercise was actually worked at: the lightest completed set.
 * Using the minimum is conservative — progress is only credited at a weight
 * every completed set was done at.
 */
export function workingWeight(log: ExerciseLog): number | null {
  const done = log.setLogs.filter((s) => s.done)
  if (done.length === 0) return null
  return Math.min(...done.map((s) => s.weight))
}

/**
 * Classifies one logged exercise against its rep range.
 * Sets that weren't completed count as missed.
 */
export function outcomeOf(log: ExerciseLog): Outcome {
  const done = log.setLogs.filter((s) => s.done)
  if (done.length < log.sets) return 'missed'
  if (done.every((s) => s.reps >= log.repMax)) return 'hit-top'
  if (done.every((s) => s.reps >= log.repMin)) return 'hit-min'
  return 'missed'
}

/**
 * Double progression:
 *  - first time: use the plan's starting weight
 *  - every set hit the top of the rep range → add the increment
 *  - every set within the range → same weight, chase more reps
 *  - missed the bottom of the range once → same weight, retry
 *  - missed twice in a row at the same weight → deload ~10%
 *
 * `history` is this exercise's completed logs, oldest first.
 */
export function suggestNext(plan: ExercisePlan, history: ExerciseLog[]): Suggestion {
  const usable = history.filter((h) => workingWeight(h) !== null)
  const last = usable[usable.length - 1]
  if (!last) {
    return { weight: plan.startWeight, kind: 'start', reason: 'Starting weight' }
  }
  const w = workingWeight(last)!
  const outcome = outcomeOf(last)

  if (outcome === 'hit-top') {
    return {
      weight: tidy(w + plan.increment),
      kind: 'increase',
      reason: `Hit ${plan.repMax} reps on every set last time — add ${plan.increment}`,
    }
  }
  if (outcome === 'hit-min') {
    return { weight: w, kind: 'hold', reason: `Same weight — aim for ${plan.repMax} reps on every set` }
  }

  const prev = usable[usable.length - 2]
  if (prev && outcomeOf(prev) === 'missed' && workingWeight(prev) === w) {
    const deloaded = Math.max(0, roundDownTo(w * DELOAD_FACTOR, plan.increment))
    return { weight: deloaded, kind: 'deload', reason: 'Missed reps two sessions running — deload and rebuild' }
  }
  return { weight: w, kind: 'retry', reason: `Missed ${plan.repMin} reps last time — retry this weight` }
}

/** All completed logs for an exercise, oldest first. */
export function historyFor(name: string, sessions: Session[]): ExerciseLog[] {
  const key = exerciseKey(name)
  return sessions
    .filter((s) => s.finishedAt)
    .slice()
    .sort((a, b) => a.startedAt - b.startedAt)
    .flatMap((s) => s.exercises.filter((e) => exerciseKey(e.name) === key))
}

/** Epley estimated one-rep max. */
export function estimated1RM(weight: number, reps: number): number {
  if (reps <= 0) return 0
  if (reps === 1) return weight
  return tidy(weight * (1 + reps / 30))
}

export function bestE1RM(log: ExerciseLog): number {
  return Math.max(0, ...log.setLogs.filter((s) => s.done).map((s) => estimated1RM(s.weight, s.reps)))
}

export function volume(log: ExerciseLog): number {
  return log.setLogs.filter((s) => s.done).reduce((t, s) => t + s.weight * s.reps, 0)
}
