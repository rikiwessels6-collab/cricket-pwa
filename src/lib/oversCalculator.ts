import type { Interruption, MatchSettings, RoundingRule } from "./types";

/** Overs bowled in a valid cricket over increment (6 balls = 1 over, but we track fractional overs for time math). */
const MINUTES_PER_HOUR = 60;

export function applyRounding(value: number, rule: RoundingRule): number {
  switch (rule) {
    case "down":
      return Math.floor(value);
    case "up":
      return Math.ceil(value);
    case "nearest":
    default:
      return Math.round(value);
  }
}

/** Minutes lost by a single interruption. An ongoing interruption (no resume yet) is measured against `now`. */
export function interruptionMinutesLost(interruption: Interruption, now: Date = new Date()): number {
  const start = new Date(interruption.stoppedAt).getTime();
  const end = interruption.resumedAt ? new Date(interruption.resumedAt).getTime() : now.getTime();
  const minutes = (end - start) / 60000;
  return minutes > 0 ? minutes : 0;
}

/** Total minutes lost to interruptions affecting a given innings. */
export function totalMinutesLost(interruptions: Interruption[], innings: 1 | 2, now: Date = new Date()): number {
  return interruptions
    .filter((i) => i.innings === innings)
    .reduce((sum, i) => sum + interruptionMinutesLost(i, now), 0);
}

/**
 * Standard proportional formula:
 * overs lost = (minutes lost / 60) * overs-per-hour rate, then rounded per the league's rounding rule.
 */
export function oversLostFromMinutes(minutesLost: number, settings: MatchSettings): number {
  const rawOversLost = (minutesLost / MINUTES_PER_HOUR) * settings.oversPerHour;
  return applyRounding(rawOversLost, settings.roundingRule);
}

export interface RevisedOvers {
  oversLost: number;
  oversAvailable: number;
  /** True if the innings has dropped to/below the minimum-overs threshold for a valid result. */
  belowMinimum: boolean;
  /** True if the innings has been washed out entirely (0 overs possible). */
  washedOut: boolean;
}

/**
 * Revised overs available to an innings after deducting overs lost to interruptions,
 * floored at 0 and flagged against the league's minimum-overs-for-a-result rule.
 */
export function revisedOversForInnings(
  interruptions: Interruption[],
  innings: 1 | 2,
  settings: MatchSettings,
  now: Date = new Date(),
): RevisedOvers {
  const minutesLost = totalMinutesLost(interruptions, innings, now);
  const oversLost = oversLostFromMinutes(minutesLost, settings);
  const oversAvailable = Math.max(0, settings.totalOvers - oversLost);
  return {
    oversLost,
    oversAvailable,
    belowMinimum: oversAvailable < settings.minimumOvers,
    washedOut: oversAvailable <= 0,
  };
}

export function formatOvers(overs: number): string {
  const wholeOvers = Math.floor(overs);
  const balls = Math.round((overs - wholeOvers) * 6);
  return balls === 0 ? `${wholeOvers}` : `${wholeOvers}.${balls}`;
}
