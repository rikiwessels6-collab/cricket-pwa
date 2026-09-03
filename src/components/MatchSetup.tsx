import { COMPETITION_PRESETS, CUSTOM_PRESET_ID, findPreset } from "../lib/competitionPresets";
import type { MatchSettings, RoundingRule, TeamNames } from "../lib/types";

interface MatchSetupProps {
  settings: MatchSettings;
  teamNames: TeamNames;
  competitionId: string;
  isFinal: boolean;
  onUpdateSettings: (patch: Partial<MatchSettings>) => void;
  onUpdateTeamNames: (patch: Partial<TeamNames>) => void;
  onSelectCompetition: (competitionId: string) => void;
  onSetIsFinal: (isFinal: boolean) => void;
}

export function MatchSetup({
  settings,
  teamNames,
  competitionId,
  isFinal,
  onUpdateSettings,
  onUpdateTeamNames,
  onSelectCompetition,
  onSetIsFinal,
}: MatchSetupProps) {
  const preset = findPreset(competitionId);

  return (
    <section className="card" aria-labelledby="setup-heading">
      <h2 id="setup-heading">Match setup</h2>

      <label className="field">
        <span>Playing conditions</span>
        <select value={competitionId} onChange={(e) => onSelectCompetition(e.target.value)}>
          <option value={CUSTOM_PRESET_ID}>Custom / other league</option>
          {COMPETITION_PRESETS.map((p) => (
            <option key={p.id} value={p.id}>
              {p.label} {p.season}
            </option>
          ))}
        </select>
      </label>

      {preset && (
        <div className="preset-info">
          {preset.minimumOversFinal !== undefined && (
            <label className="checkbox-field">
              <input type="checkbox" checked={isFinal} onChange={(e) => onSetIsFinal(e.target.checked)} />
              <span>
                This is the Final (minimum overs increases to {preset.minimumOversFinal})
              </span>
            </label>
          )}
          <p className="hint">
            Loaded from <strong>{preset.sourceLabel}</strong> ({preset.citation}).{" "}
            <a href={preset.sourceUrl} target="_blank" rel="noopener noreferrer">
              View official playing conditions (PDF)
            </a>
            . Fields below are pre-filled but still editable if conditions change.
          </p>
        </div>
      )}

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
            step={0.01}
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
            <option value="down">Round down (fraction ignored)</option>
            <option value="up">Round up</option>
          </select>
        </label>
      </div>

      <p className="hint">
        These settings follow your league's own playing conditions — set the overs-per-hour rate, minimum
        overs and rounding rule from your league handbook, or pick a competition above to load them
        automatically. They apply to every overs-lost calculation below.
      </p>
    </section>
  );
}
