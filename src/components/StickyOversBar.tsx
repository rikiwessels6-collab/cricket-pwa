import { formatOvers, revisedOversForInnings, statusClassFor } from "../lib/oversCalculator";
import type { Interruption, MatchSettings, TeamNames } from "../lib/types";

interface StickyOversBarProps {
  settings: MatchSettings;
  interruptions: Interruption[];
  teamNames: TeamNames;
  extraTimeUsedMinutes: number;
}

/**
 * Always-on-screen overs-remaining strip, independent of scroll position, so the
 * live figure stays visible while an umpire is working in the interruption log or
 * par score panel further down the page.
 */
export function StickyOversBar({ settings, interruptions, teamNames, extraTimeUsedMinutes }: StickyOversBarProps) {
  const revised1 = revisedOversForInnings(interruptions, 1, settings, extraTimeUsedMinutes);
  const revised2 = revisedOversForInnings(interruptions, 2, settings, 0);

  return (
    <div className="sticky-overs-bar" role="status" aria-label="Overs remaining">
      <div className={`sticky-overs-chip ${statusClassFor(revised1)}`}>
        <span className="sticky-overs-label">{teamNames.team1 || "Team 1"}</span>
        <span className="sticky-overs-value">
          {formatOvers(revised1.oversAvailable)}/{settings.totalOvers}
        </span>
      </div>
      <div className={`sticky-overs-chip ${statusClassFor(revised2)}`}>
        <span className="sticky-overs-label">{teamNames.team2 || "Team 2"}</span>
        <span className="sticky-overs-value">
          {formatOvers(revised2.oversAvailable)}/{settings.totalOvers}
        </span>
      </div>
    </div>
  );
}
