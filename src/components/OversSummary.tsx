import { formatOvers, revisedOversForInnings } from "../lib/oversCalculator";
import type { Interruption, MatchSettings, TeamNames } from "../lib/types";

interface OversSummaryProps {
  settings: MatchSettings;
  interruptions: Interruption[];
  teamNames: TeamNames;
}

function InningsCard({
  label,
  innings,
  settings,
  interruptions,
}: {
  label: string;
  innings: 1 | 2;
  settings: MatchSettings;
  interruptions: Interruption[];
}) {
  const revised = revisedOversForInnings(interruptions, innings, settings);
  const statusClass = revised.washedOut ? "status-danger" : revised.belowMinimum ? "status-warning" : "status-ok";

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
    </div>
  );
}

export function OversSummary({ settings, interruptions, teamNames }: OversSummaryProps) {
  return (
    <section className="card" aria-labelledby="overs-heading">
      <h2 id="overs-heading">Overs remaining</h2>
      <div className="innings-grid">
        <InningsCard
          label={`${teamNames.team1 || "Team 1"} (1st innings)`}
          innings={1}
          settings={settings}
          interruptions={interruptions}
        />
        <InningsCard
          label={`${teamNames.team2 || "Team 2"} (2nd innings)`}
          innings={2}
          settings={settings}
          interruptions={interruptions}
        />
      </div>
    </section>
  );
}
