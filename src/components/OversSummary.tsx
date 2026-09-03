import { findPreset } from "../lib/competitionPresets";
import { formatOvers, revisedOversForInnings } from "../lib/oversCalculator";
import type { Interruption, MatchSettings, TeamNames } from "../lib/types";

interface OversSummaryProps {
  settings: MatchSettings;
  interruptions: Interruption[];
  teamNames: TeamNames;
  competitionId: string;
}

function InningsCard({
  label,
  innings,
  settings,
  interruptions,
  bowlerOversLimitDivisor,
}: {
  label: string;
  innings: 1 | 2;
  settings: MatchSettings;
  interruptions: Interruption[];
  bowlerOversLimitDivisor?: number;
}) {
  const revised = revisedOversForInnings(interruptions, innings, settings);
  const statusClass = revised.washedOut ? "status-danger" : revised.belowMinimum ? "status-warning" : "status-ok";
  const maxOversPerBowler =
    bowlerOversLimitDivisor && revised.oversLost > 0
      ? Math.ceil(revised.oversAvailable / bowlerOversLimitDivisor)
      : null;

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
    </div>
  );
}

export function OversSummary({ settings, interruptions, teamNames, competitionId }: OversSummaryProps) {
  const preset = findPreset(competitionId);

  return (
    <section className="card" aria-labelledby="overs-heading">
      <h2 id="overs-heading">Overs remaining</h2>
      <div className="innings-grid">
        <InningsCard
          label={`${teamNames.team1 || "Team 1"} (1st innings)`}
          innings={1}
          settings={settings}
          interruptions={interruptions}
          bowlerOversLimitDivisor={preset?.bowlerOversLimitDivisor}
        />
        <InningsCard
          label={`${teamNames.team2 || "Team 2"} (2nd innings)`}
          innings={2}
          settings={settings}
          interruptions={interruptions}
          bowlerOversLimitDivisor={preset?.bowlerOversLimitDivisor}
        />
      </div>
    </section>
  );
}
