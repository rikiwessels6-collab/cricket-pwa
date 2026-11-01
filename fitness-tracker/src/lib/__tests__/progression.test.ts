import { describe, expect, it } from 'vitest'
import {
  estimated1RM,
  historyFor,
  outcomeOf,
  suggestNext,
  workingWeight,
} from '../progression'
import { buildSession } from '../workouts'
import type { ExerciseLog, ExercisePlan, Session, WorkoutTemplate } from '../types'

const plan: ExercisePlan = {
  id: 'p1',
  name: 'Bench Press',
  sets: 3,
  repMin: 6,
  repMax: 10,
  increment: 2.5,
  startWeight: 40,
}

function log(weight: number, reps: number[], done = reps.map(() => true)): ExerciseLog {
  return {
    planId: 'p1',
    name: 'Bench Press',
    sets: 3,
    repMin: 6,
    repMax: 10,
    increment: 2.5,
    targetWeight: weight,
    setLogs: reps.map((r, i) => ({ weight, reps: r, done: done[i] })),
  }
}

describe('outcomeOf', () => {
  it('detects hitting the top of the range on every set', () => {
    expect(outcomeOf(log(60, [10, 10, 10]))).toBe('hit-top')
  })
  it('detects being inside the range', () => {
    expect(outcomeOf(log(60, [10, 8, 7]))).toBe('hit-min')
  })
  it('counts a set below the minimum as a miss', () => {
    expect(outcomeOf(log(60, [8, 6, 5]))).toBe('missed')
  })
  it('counts unfinished sets as a miss', () => {
    expect(outcomeOf(log(60, [10, 10, 10], [true, true, false]))).toBe('missed')
  })
})

describe('workingWeight', () => {
  it('uses the lightest completed set', () => {
    const l = log(60, [10, 10, 10])
    l.setLogs[2].weight = 55
    expect(workingWeight(l)).toBe(55)
  })
  it('is null when nothing was completed', () => {
    expect(workingWeight(log(60, [10, 10], [false, false]))).toBeNull()
  })
})

describe('suggestNext', () => {
  it('starts at the starting weight with no history', () => {
    expect(suggestNext(plan, [])).toMatchObject({ weight: 40, kind: 'start' })
  })
  it('adds the increment after hitting the top of the range', () => {
    expect(suggestNext(plan, [log(60, [10, 10, 10])])).toMatchObject({ weight: 62.5, kind: 'increase' })
  })
  it('holds the weight while inside the range', () => {
    expect(suggestNext(plan, [log(60, [9, 8, 8])])).toMatchObject({ weight: 60, kind: 'hold' })
  })
  it('retries after a single miss', () => {
    expect(suggestNext(plan, [log(60, [7, 5, 4])])).toMatchObject({ weight: 60, kind: 'retry' })
  })
  it('deloads ~10% (rounded down to the increment) after two misses at the same weight', () => {
    const s = suggestNext(plan, [log(60, [7, 5, 4]), log(60, [6, 5, 5])])
    expect(s).toMatchObject({ weight: 52.5, kind: 'deload' })
  })
  it('does not deload when the two misses were at different weights', () => {
    expect(suggestNext(plan, [log(57.5, [5, 5, 5]), log(60, [6, 5, 5])]).kind).toBe('retry')
  })
  it('ignores logs with no completed sets', () => {
    const skipped = log(60, [0, 0, 0], [false, false, false])
    expect(suggestNext(plan, [log(60, [10, 10, 10]), skipped])).toMatchObject({ weight: 62.5 })
  })
  it('avoids floating point noise', () => {
    const p = { ...plan, increment: 0.1 }
    expect(suggestNext(p, [{ ...log(0.2, [10, 10, 10]), increment: 0.1 }]).weight).toBe(0.3)
  })
})

describe('estimated1RM', () => {
  it('uses the Epley formula', () => {
    expect(estimated1RM(100, 5)).toBeCloseTo(116.67, 2)
    expect(estimated1RM(100, 1)).toBe(100)
    expect(estimated1RM(100, 0)).toBe(0)
  })
})

function session(id: string, startedAt: number, exercises: ExerciseLog[], finished = true): Session {
  return {
    id,
    templateId: 't',
    templateName: 'T',
    date: '2026-01-01',
    startedAt,
    finishedAt: finished ? startedAt + 1 : undefined,
    exercises,
  }
}

describe('historyFor', () => {
  it('matches by name case-insensitively, oldest first, finished sessions only', () => {
    const a = session('a', 2, [log(62.5, [8, 8, 8])])
    const b = session('b', 1, [{ ...log(60, [10, 10, 10]), name: ' bench  press ' }])
    const c = session('c', 3, [log(65, [6, 6, 6])], false)
    const h = historyFor('Bench Press', [a, b, c])
    expect(h.map((x) => x.targetWeight)).toEqual([60, 62.5])
  })
})

describe('buildSession', () => {
  const template: WorkoutTemplate = { id: 't', name: 'Upper', exercises: [plan] }

  it('pre-fills the suggested weight and repMin reps on a fresh exercise', () => {
    const s = buildSession(template, [])
    expect(s.exercises[0].setLogs).toEqual([
      { weight: 40, reps: 6, done: false },
      { weight: 40, reps: 6, done: false },
      { weight: 40, reps: 6, done: false },
    ])
  })

  it('progresses the weight from the last finished session', () => {
    const s = buildSession(template, [session('a', 1, [log(60, [10, 10, 10])])])
    expect(s.exercises[0].targetWeight).toBe(62.5)
    expect(s.exercises[0].suggestKind).toBe('increase')
  })

  it("pre-fills last time's reps when repeating a weight", () => {
    const s = buildSession(template, [session('a', 1, [log(60, [9, 8, 7])])])
    expect(s.exercises[0].setLogs.map((x) => x.reps)).toEqual([9, 8, 7])
  })
})
