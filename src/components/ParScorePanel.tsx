import { formatOvers, revisedOversForInnings } from "../lib/oversCalculator";
import { estimateParScore } from "../lib/parScore";
import type { Interruption, MatchSettings, Team1Figures, Team2Figures, TeamNames } from "../lib/types";

interface ParScorePanelProps {
  settings: MatchSettings;
  interruptions: Interruption[];
  teamNames: TeamNames;
  team1: Team1Figures;
  team2: Team2Figures;
  onUpdateTeam1: (patch: Partial<Team1Figures>) => void;
  onUpdateTeam2: (patch: Partial<Team2Figures>) => void;
}

export function ParScorePanel({
  settings,
  interruptions,
  teamNames,
  team1,
  team2,
  onUpdateTeam1,
  onUpdateTeam2,
}: ParScorePanelProps) {
  const team2Revised = revisedOversForInnings(interruptions, 2, settings);

  const result = estimateParScore({
    totalOvers: settings.totalOvers,
    team1Runs: team1.runs,
    team1OversFaced: team1.oversFaced,
    team1WicketsLost: team1.wicketsLost,
    team2OversAvailable: team2Revised.oversAvailable,
    team2WicketsLost: team2.wicketsLost,
  });

  return (
    <section className="card" aria-labelledby="par-score-heading">
      <h2 id="par-score-heading">Par score estimate</h2>
      <p className="disclaimer">
        This is an <strong>unofficial, approximate</strong> estimate based on a resource-depletion model built for
        this app. It is <strong>not</strong> the official ICC Duckworth-Lewis-Stern (DLS) calculation — those
        tables are proprietary. Do not use this figure to decide a match result where an official DLS-certified
        calculation is required; use it only as a rough guide.
      </p>

      <h3>{teamNames.team1 || "Team 1"} innings (completed or in progress)</h3>
      <div className="field-grid">
        <label className="field">
          <span>Runs scored</span>
          <input
            type="number"
            min={0}
            value={team1.runs}
            onChange={(e) => onUpdateTeam1({ runs: Number(e.target.value) })}
          />
        </label>
        <label className="field">
          <span>Overs faced</span>
          <input
            type="number"
            min={0}
            step={0.1}
            value={team1.oversFaced}
            onChange={(e) => onUpdateTeam1({ oversFaced: Number(e.target.value) })}
          />
        </label>
        <label className="field">
          <span>Wickets lost</span>
          <input
            type="number"
            min={0}
            max={10}
            value={team1.wicketsLost}
            onChange={(e) => onUpdateTeam1({ wicketsLost: Number(e.target.value) })}
          />
        </label>
      </div>

      <h3>{teamNames.team2 || "Team 2"} chase</h3>
      <div className="field-grid">
        <label className="field">
          <span>Overs available (from Overs Remaining above)</span>
          <input type="text" value={formatOvers(team2Revised.oversAvailable)} disabled />
        </label>
        <label className="field">
          <span>Wickets lost so far</span>
          <input
            type="number"
            min={0}
            max={10}
            value={team2.wicketsLost}
            onChange={(e) => onUpdateTeam2({ wicketsLost: Number(e.target.value) })}
          />
        </label>
      </div>

      <div className="par-score-result">
        <div>
          <span className="result-label">Par score</span>
          <span className="result-value">{result.parScore}</span>
        </div>
        <div>
          <span className="result-label">Target to win</span>
          <span className="result-value">{result.target}</span>
        </div>
      </div>
      <p className="hint">
        {teamNames.team1 || "Team 1"} used {result.team1ResourceUsedPercent}% of resources.{" "}
        {teamNames.team2 || "Team 2"} has {result.team2ResourceAvailablePercent}% available.
      </p>
    </section>
  );
}
