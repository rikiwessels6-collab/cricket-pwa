import { useState } from 'react'
import { FoodView } from './components/FoodView'
import { TrainView } from './components/TrainView'
import { ProgressView } from './components/ProgressView'
import { SettingsView } from './components/SettingsView'
import { TabIcon } from './components/icons'
import { useStore } from './hooks/useStore'

export type Tab = 'food' | 'train' | 'progress' | 'settings'

const TABS: { id: Tab; label: string }[] = [
  { id: 'food', label: 'Food' },
  { id: 'train', label: 'Train' },
  { id: 'progress', label: 'Progress' },
  { id: 'settings', label: 'Settings' },
]

function readTab(): Tab {
  try {
    const t = sessionStorage.getItem('tab') as Tab | null
    if (t && TABS.some((x) => x.id === t)) return t
  } catch {
    /* ignore */
  }
  return 'food'
}

export default function App() {
  const [tab, setTabState] = useState<Tab>(readTab)
  const data = useStore()

  const setTab = (t: Tab) => {
    setTabState(t)
    window.scrollTo({ top: 0 })
    try {
      sessionStorage.setItem('tab', t)
    } catch {
      /* ignore */
    }
  }

  return (
    <div className="app">
      {data.activeSession && tab !== 'train' && (
        <div className="banner">
          <span>
            <b>{data.activeSession.templateName}</b> in progress
          </span>
          <button className="btn sm primary" onClick={() => setTab('train')}>
            Resume
          </button>
        </div>
      )}
      {tab === 'food' && <FoodView />}
      {tab === 'train' && <TrainView />}
      {tab === 'progress' && <ProgressView />}
      {tab === 'settings' && <SettingsView />}

      <nav className="tabbar" aria-label="Sections">
        {TABS.map((t) => (
          <button key={t.id} aria-current={tab === t.id ? 'page' : undefined} onClick={() => setTab(t.id)}>
            <TabIcon tab={t.id} />
            {t.label}
          </button>
        ))}
      </nav>
    </div>
  )
}
