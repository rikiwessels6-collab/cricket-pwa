import { useEffect, useState } from "react";
import { findPreset, intervalMinutesForTimeLost, overRateCutoffMinutes } from "../lib/competitionPresets";
import type { OverRateCutoff } from "../lib/competitionPresets";
import { formatOvers, revisedOversForInnings, statusClassFor } from "../lib/oversCalculator";
import type { Interruption, MatchSettings, TeamNames } from "../lib/types";

interface OversSummaryProps {
  settings: MatchSettings;
  interruptions: Interruption[];
  teamNames: TeamNames;
  competitionId: string;
  extraTimeUsedMinutes: number;
  onUpdateExtraTimeUsed: (minutes: number) => void;
}

function InningsCard({
  label,
  innings,
  settings,
  interruptions,
  extraTimeUsedMinutes,
  bowlerOversLimitDivisor,
  overRateCutoff,
}: {
  label: string;
  innings: 1 | 2;
  settings: MatchSettings;
  interruptions: Interruption[];
  extraTimeUsedMinutes: number;
  bowlerOversLimitDivisor?: number;
  overRateCutoff?: OverRateCutoff;
}) {
  const revised = revisedOversForInnings(interruptions, innings, settings, extraTimeUsedMinutes);
  const statusClass = statusClassFor(revised);
  const maxOversPerBowler =
    bowlerOversLimitDivisor && revised.oversLost > 0
      ? Math.ceil(revised.oversAvailable / bowlerOversLimitDivisor)
      : null;
  const cutoffMinutes = overRateCutoff ? overRateCutoffMinutes(overRateCutoff, settings, revised.oversAvailable) : null;

  return (
    <div className={`innings-card ${statusClass}`}>
      <h3>{label}</h3>
      <p className="overs-figure">
        {formatOvers(revised.oversAvailable)} <span>/ {settings.totalOvers} overs</span>
      </p>
      <p className="hint">
        {revised.oversLost > 0 ? `${revised.oversLost} over(s) lost to interruptions` : "No overs lost yet"}
      </p>
      {revised.washedOut && <p className="status-message">Innings washed out — no overs remain.</p>}
      {!revised.washedOut && revised.belowMinimum && (
        <p className="status-message">
          Below the minimum of {settings.minimumOvers} overs — check your league's rules on whether a result is
          still possible.
        </p>
      )}
      {maxOversPerBowler !== null && (
        <p className="hint">Max {maxOversPerBowler} overs per bowler in this reduced innings.</p>
      )}
      {cutoffMinutes !== null && (
        <p className="hint">Last over must start by minute {cutoffMinutes} of playing time (over-rate cut-off).</p>
      )}
    </div>
  );
}

export function OversSummary({
  settings,
  interruptions,
  teamNames,
  competitionId,
  extraTimeUsedMinutes,
  onUpdateExtraTimeUsed,
}: OversSummaryProps) {
  const preset = findPreset(competitionId);
  const revised1 = revisedOversForInnings(interruptions, 1, settings, extraTimeUsedMinutes);
  const interval = preset ? intervalMinutesForTimeLost(preset, revised1.netMinutesLost) : null;

  const allowanceCap = preset?.extraTimeAllowanceMinutes ?? 0;
  const [allowanceStartedAt, setAllowanceStartedAt] = useState<Date | null>(null);
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    if (!allowanceStartedAt) return;
    const id = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(id);
  }, [allowanceStartedAt]);

  const liveAllowanceMinutes = allowanceStartedAt
    ? Math.floor((now.getTime() - allowanceStartedAt.getTime()) / 60000)
    : 0;

  function handleStartAllowance() {
    setAllowanceStartedAt(new Date());
  }

  function handleStopAllowance() {
    if (!allowanceStartedAt) return;
    const elapsedMinutes = Math.round((Date.now() - allowanceStartedAt.getTime()) / 60000);
    onUpdateExtraTimeUsed(Math.min(allowanceCap, extraTimeUsedMinutes + elapsedMinutes));
    setAllowanceStartedAt(null);
  }

  return (
    <section className="card" aria-labelledby="overs-heading">
      <h2 id="overs-heading">Overs remaining</h2>

      {preset?.extraTimeAllowanceMinutes !== undefined && preset.extraTimeAllowanceMinutes > 0 && (
        <div className="field">
          <span>Extra time used (of {preset.extraTimeAllowanceMinutes} min allowance, offsets 1st innings delay)</span>
          <div className="button-row">
            {!allowanceStartedAt ? (
              <button type="button" className="btn btn-danger" onClick={handleStartAllowance}>
                Start allowance
              </button>
            ) : (
              <button type="button" className="btn btn-primary" onClick={handleStopAllowance}>
                Stop allowance (+{liveAllowanceMinutes} min)
              </button>
            )}
            <input
              type="number"
              min={0}
              max={preset.extraTimeAllowanceMinutes}
              value={extraTimeUsedMinutes}
              onChange={(e) => onUpdateExtraTimeUsed(Number(e.target.value))}
              disabled={!!allowanceStartedAt}
              aria-label="Extra time used, in minutes"
            />
          </div>
          {allowanceStartedAt && (
            <p className="live-banner" role="status">
              Allowance clock running — {liveAllowanceMinutes} min and counting
            </p>
          )}
        </div>
      )}

      <div className="innings-grid">
        <InningsCard
          label={`${teamNames.team1 || "Team 1"} (1st innings)`}
          innings={1}
          settings={settings}
          interruptions={interruptions}
          extraTimeUsedMinutes={extraTimeUsedMinutes}
          bowlerOversLimitDivisor={preset?.bowlerOversLimitDivisor}
          overRateCutoff={preset?.overRateCutoff}
        />
        <InningsCard
          label={`${teamNames.team2 || "Team 2"} (2nd innings)`}
          innings={2}
          settings={settings}
          interruptions={interruptions}
          extraTimeUsedMinutes={0}
          bowlerOversLimitDivisor={preset?.bowlerOversLimitDivisor}
          overRateCutoff={preset?.overRateCutoff}
        />
      </div>

      {interval !== null && (
        <p className="hint">
          Interval before 2nd innings: {interval} min
          {interval !== preset?.intervalMinutesDefault ? " (reduced for time lost)" : ""}
        </p>
      )}
    </section>
  );
}
