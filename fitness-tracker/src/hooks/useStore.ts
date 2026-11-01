import { useSyncExternalStore } from 'react'
import { getState, subscribe } from '../lib/store'
import type { AppData } from '../lib/types'

export function useStore(): AppData {
  return useSyncExternalStore(subscribe, getState, getState)
}
