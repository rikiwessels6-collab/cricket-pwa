import { newId } from './id'
import type { AppData, ExercisePlan, WorkoutTemplate } from './types'

function plan(name: string, sets: number, repMin: number, repMax: number, increment: number, startWeight: number): ExercisePlan {
  return { id: newId(), name, sets, repMin, repMax, increment, startWeight }
}

export function starterTemplates(): WorkoutTemplate[] {
  return [
    {
      id: newId(),
      name: 'Upper A',
      exercises: [
        plan('Bench Press', 3, 6, 10, 2.5, 40),
        plan('Barbell Row', 3, 6, 10, 2.5, 40),
        plan('Overhead Press', 3, 6, 10, 2.5, 25),
        plan('Lat Pulldown', 3, 8, 12, 2.5, 35),
      ],
    },
    {
      id: newId(),
      name: 'Lower A',
      exercises: [
        plan('Back Squat', 3, 5, 8, 2.5, 50),
        plan('Romanian Deadlift', 3, 8, 12, 2.5, 40),
        plan('Leg Press', 3, 10, 15, 5, 80),
        plan('Calf Raise', 3, 10, 15, 5, 40),
      ],
    },
  ]
}

export function defaultData(): AppData {
  return {
    version: 1,
    settings: { unit: 'kg', calorieGoal: 2200, proteinGoal: 150, restSeconds: 90 },
    foods: [],
    savedFoods: [],
    templates: starterTemplates(),
    sessions: [],
    activeSession: null,
    bodyWeights: [],
  }
}
