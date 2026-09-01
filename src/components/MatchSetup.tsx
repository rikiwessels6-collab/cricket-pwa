import type { MatchSettings, RoundingRule, TeamNames } from "../lib/types";

interface MatchSetupProps {
  settings: MatchSettings;
  teamNames: TeamNames;
  onUpdateSettings: (patch: Partial<MatchSettings>) => void;
  onUpdateTeamNames: (patch: Partial<TeamNames>) => void;
}

export function MatchSetup({ settings, teamNames, onUpdateSettings, onUpdateTeamNames }: MatchSetupProps) {
  return (
    <section className="card" aria-labelledby="setup-heading">
      <h2 id="setup-heading">Match setup</h2>

      <div className="field-grid">
        <label className="field">
          <span>Team 1 (bats first)</span>
          <input
            type="text"
            value={teamNames.team1}
            onChange={(e) => onUpdateTeamNames({ team1: e.target.value })}
          />
        </label>
        <label className="field">
          <span>Team 2 (bats second)</span>
          <input
            type="text"
            value={teamNames.team2}
            onChange={(e) => onUpdateTeamNames({ team2: e.target.value })}
          />
        </label>
      </div>

      <div className="field-grid">
        <label className="field">
          <span>Overs per innings</span>
          <input
            type="number"
            min={1}
            step={1}
            value={settings.totalOvers}
            onChange={(e) => onUpdateSettings({ totalOvers: Number(e.target.value) })}
          />
        </label>
        <label className="field">
          <span>Overs per hour (scheduled rate)</span>
          <input
            type="number"
            min={1}
            step={0.1}
            value={settings.oversPerHour}
            onChange={(e) => onUpdateSettings({ oversPerHour: Number(e.target.value) })}
          />
        </label>
        <label className="field">
          <span>Minimum overs for a result</span>
          <input
            type="number"
            min={1}
            step={1}
            value={settings.minimumOvers}
            onChange={(e) => onUpdateSettings({ minimumOvers: Number(e.target.value) })}
          />
        </label>
        <label className="field">
          <span>Rounding rule for overs lost</span>
          <select
            value={settings.roundingRule}
            onChange={(e) => onUpdateSettings({ roundingRule: e.target.value as RoundingRule })}
          >
            <option value="nearest">Nearest whole over</option>
            <option value="down">Round down</option>
            <option value="up">Round up</option>
          </select>
        </label>
      </div>

      <p className="hint">
        These settings follow your league's own playing conditions — set the overs-per-hour rate, minimum
        overs and rounding rule from your league handbook. They apply to every overs-lost calculation below.
      </p>
    </section>
  );
}
