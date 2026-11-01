import { describe, expect, it } from 'vitest'
import { averageKcal, totalsFor } from '../nutrition'
import type { FoodEntry } from '../types'

const f = (date: string, kcal: number, protein?: number): FoodEntry => ({
  id: Math.random().toString(),
  date,
  meal: 'lunch',
  name: 'x',
  kcal,
  protein,
})

describe('nutrition', () => {
  const foods = [f('2026-11-01', 500, 30), f('2026-11-01', 300), f('2026-11-02', 2000, 100)]

  it('totals a single day', () => {
    expect(totalsFor(foods, '2026-11-01')).toEqual({ kcal: 800, protein: 30, carbs: 0, fat: 0 })
  })
  it('averages only days with entries', () => {
    expect(averageKcal(foods, ['2026-11-01', '2026-11-02', '2026-11-03'])).toBe(1400)
    expect(averageKcal(foods, ['2026-10-01'])).toBeNull()
  })
})
