import type { DateKey, FoodEntry } from './types'

export interface DayTotals {
  kcal: number
  protein: number
  carbs: number
  fat: number
}

export function totalsFor(foods: FoodEntry[], date: DateKey): DayTotals {
  return foods
    .filter((f) => f.date === date)
    .reduce<DayTotals>(
      (t, f) => ({
        kcal: t.kcal + f.kcal,
        protein: t.protein + (f.protein ?? 0),
        carbs: t.carbs + (f.carbs ?? 0),
        fat: t.fat + (f.fat ?? 0),
      }),
      { kcal: 0, protein: 0, carbs: 0, fat: 0 },
    )
}

/** Average daily kcal across the given dates, counting only days with entries. */
export function averageKcal(foods: FoodEntry[], dates: DateKey[]): number | null {
  const logged = dates.map((d) => totalsFor(foods, d).kcal).filter((k) => k > 0)
  if (logged.length === 0) return null
  return Math.round(logged.reduce((a, b) => a + b, 0) / logged.length)
}
