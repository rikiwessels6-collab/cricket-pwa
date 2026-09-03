import "./App.css";
import { InterruptionLog } from "./components/InterruptionLog";
import { MatchSetup } from "./components/MatchSetup";
import { OversSummary } from "./components/OversSummary";
import { ParScorePanel } from "./components/ParScorePanel";
import { useMatchState } from "./hooks/useMatchState";

function App() {
  const {
    state,
    updateSettings,
    updateTeamNames,
    updateTeam1,
    updateTeam2,
    addInterruption,
    updateInterruption,
    removeInterruption,
    resetMatch,
    selectCompetition,
    setIsFinal,
  } = useMatchState();

  return (
    <div className="app">
      <header className="app-header">
        <h1>Rain Calc</h1>
        <p className="subtitle">Overs-lost &amp; par score calculator for cricket umpires</p>
        <button
          type="button"
          className="btn btn-link reset-btn"
          onClick={() => {
            if (confirm("Start a new match? This clears all current match data.")) {
              resetMatch();
            }
          }}
        >
          New match
        </button>
      </header>

      <main className="app-main">
        <MatchSetup
          settings={state.settings}
          teamNames={state.teamNames}
          competitionId={state.competitionId}
          isFinal={state.isFinal}
          onUpdateSettings={updateSettings}
          onUpdateTeamNames={updateTeamNames}
          onSelectCompetition={selectCompetition}
          onSetIsFinal={setIsFinal}
        />

        <InterruptionLog
          interruptions={state.interruptions}
          teamNames={state.teamNames}
          onAdd={addInterruption}
          onUpdate={updateInterruption}
          onRemove={removeInterruption}
        />

        <OversSummary
          settings={state.settings}
          interruptions={state.interruptions}
          teamNames={state.teamNames}
          competitionId={state.competitionId}
        />

        <ParScorePanel
          settings={state.settings}
          interruptions={state.interruptions}
          teamNames={state.teamNames}
          team1={state.team1}
          team2={state.team2}
          onUpdateTeam1={updateTeam1}
          onUpdateTeam2={updateTeam2}
        />
      </main>

      <footer className="app-footer">
        <p>Works offline once installed. Your match data stays on this device.</p>
      </footer>
    </div>
  );
}

export default App;
