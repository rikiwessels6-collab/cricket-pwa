export type Unit = 'kg' | 'lb'
export type Meal = 'breakfast' | 'lunch' | 'dinner' | 'snack'

/** ISO calendar date in local time, e.g. "2026-11-01". */
export type DateKey = string

export interface Macros {
  protein?: number
  carbs?: number
  fat?: number
}

export interface FoodEntry extends Macros {
  id: string
  date: DateKey
  meal: Meal
  name: string
  kcal: number
}

/** A food remembered for one-tap re-logging. */
export interface SavedFood extends Macros {
  id: string
  name: string
  kcal: number
}

/** How one exercise is programmed inside a workout template. */
export interface ExercisePlan {
  id: string
  name: string
  sets: number
  repMin: number
  repMax: number
  /** Weight added when every set reaches repMax. */
  increment: number
  /** Weight used the very first time this exercise is done. */
  startWeight: number
}

export interface WorkoutTemplate {
  id: string
  name: string
  exercises: ExercisePlan[]
}

export interface SetLog {
  weight: number
  reps: number
  done: boolean
}

export interface ExerciseLog {
  planId: string
  name: string
  sets: number
  repMin: number
  repMax: number
  increment: number
  /** The weight the app suggested for this session. */
  targetWeight: number
  /** Why the app chose targetWeight (shown during the session). */
  suggestKind?: 'start' | 'increase' | 'hold' | 'retry' | 'deload'
  suggestReason?: string
  setLogs: SetLog[]
}

export interface Session {
  id: string
  templateId: string
  templateName: string
  date: DateKey
  startedAt: number
  finishedAt?: number
  exercises: ExerciseLog[]
}

export interface BodyWeightEntry {
  date: DateKey
  weight: number
}

export interface Settings {
  unit: Unit
  calorieGoal: number
  proteinGoal: number
  restSeconds: number
}

export interface AppData {
  version: 1
  settings: Settings
  foods: FoodEntry[]
  savedFoods: SavedFood[]
  templates: WorkoutTemplate[]
  sessions: Session[]
  activeSession: Session | null
  bodyWeights: BodyWeightEntry[]
}
