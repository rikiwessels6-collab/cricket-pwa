/**
 * Unofficial, approximate resource-based par score estimator.
 *
 * This is NOT the official ICC Duckworth-Lewis-Stern (DLS) calculation. The real
 * DLS resource tables and software are proprietary and not publicly reproducible.
 * This model is an original approximation that captures the same shape (resource
 * depletes faster as overs run out, and faster still as wickets fall) so umpires
 * get a reasonable, explainable estimate — never a substitute for an official
 * DLS-certified device/app in a match that requires one.
 */

const OVERS_CURVE_EXPONENT = 1.5;
const WICKETS_CURVE_EXPONENT = 0.75;

/** Fraction (0-1) of batting resource remaining, given overs and wickets in hand. */
export function resourceFraction(oversRemaining: number, wicketsLost: number, totalOvers: number): number {
  if (totalOvers <= 0) return 0;
  const clampedOvers = Math.min(Math.max(oversRemaining, 0), totalOvers);
  const clampedWickets = Math.min(Math.max(wicketsLost, 0), 10);

  if (clampedWickets >= 10) return 0;

  const oversFactor = 1 - Math.pow(1 - clampedOvers / totalOvers, OVERS_CURVE_EXPONENT);
  const wicketFactor = Math.pow((10 - clampedWickets) / 10, WICKETS_CURVE_EXPONENT);
  return oversFactor * wicketFactor;
}

/** Resource percentage (0-100), rounded to one decimal place for display. */
export function resourcePercent(oversRemaining: number, wicketsLost: number, totalOvers: number): number {
  return Math.round(resourceFraction(oversRemaining, wicketsLost, totalOvers) * 1000) / 10;
}

export interface ParScoreInput {
  totalOvers: number;
  /** Team batting first: runs scored and the resource they actually used. */
  team1Runs: number;
  team1OversFaced: number;
  team1WicketsLost: number;
  /** Team batting second: overs they'll actually get (after reduction) and wickets down so far, if mid-chase. */
  team2OversAvailable: number;
  team2WicketsLost: number;
}

export interface ParScoreResult {
  team1ResourceUsedPercent: number;
  team2ResourceAvailablePercent: number;
  /** Estimated target for team 2 to win (par score + 1). */
  target: number;
  /** Estimated par score: the score team 2 needs to be level with team 1 at this point. */
  parScore: number;
}

/**
 * Estimates a revised target/par score for the team batting second using the
 * resource model above. When team 1's innings was itself interrupted, pass the
 * overs they actually faced (not the original scheduled overs) as team1OversFaced.
 */
export function estimateParScore(input: ParScoreInput): ParScoreResult {
  const { totalOvers, team1Runs, team1OversFaced, team1WicketsLost, team2OversAvailable, team2WicketsLost } = input;

  const team1OversRemainingAtEnd = Math.max(0, totalOvers - team1OversFaced);
  const team1ResourceRemaining = resourceFraction(team1OversRemainingAtEnd, team1WicketsLost, totalOvers);
  const team1ResourceUsed = Math.max(0, 1 - team1ResourceRemaining);

  const team2Resource = resourceFraction(team2OversAvailable, team2WicketsLost, totalOvers);

  const resourceRatio = team1ResourceUsed > 0 ? team2Resource / team1ResourceUsed : 0;
  const parScore = Math.max(0, Math.round(team1Runs * resourceRatio));

  return {
    team1ResourceUsedPercent: Math.round(team1ResourceUsed * 1000) / 10,
    team2ResourceAvailablePercent: Math.round(team2Resource * 1000) / 10,
    parScore,
    target: parScore + 1,
  };
}
