export type RoundingRule = "nearest" | "down" | "up";

export interface MatchSettings {
  /** Scheduled overs per innings before any reduction, e.g. 50, 20 */
  totalOvers: number;
  /** Contracted over rate used to convert lost time into lost overs */
  oversPerHour: number;
  /** Fewest overs a side must face for the match to produce a valid result */
  minimumOvers: number;
  /** How fractional overs-lost are rounded before being applied */
  roundingRule: RoundingRule;
}

export interface Interruption {
  id: string;
  /** Which innings the stoppage occurred in */
  innings: 1 | 2;
  stoppedAt: string; // ISO timestamp
  resumedAt: string | null; // ISO timestamp, null while ongoing
  note?: string;
}

export interface InningsState {
  /** Overs actually available to this innings after all reductions so far */
  oversAvailable: number;
  /** Total overs lost to interruptions in this innings */
  oversLost: number;
  /** Wickets down at the point the innings ended or is currently at (for par score) */
  wicketsLost: number;
  /** Runs scored (for par score calculation of a chase) */
  runs: number;
}

export interface TeamNames {
  team1: string;
  team2: string;
}

/** Manually-entered figures for team 1's completed (or in-progress) innings, used for the par score estimate. */
export interface Team1Figures {
  runs: number;
  oversFaced: number;
  wicketsLost: number;
}

/** Manually-entered figures for team 2's chase so far, used for the par score estimate. */
export interface Team2Figures {
  wicketsLost: number;
}

export interface MatchState {
  settings: MatchSettings;
  teamNames: TeamNames;
  interruptions: Interruption[];
  team1: Team1Figures;
  team2: Team2Figures;
  /** Id of the loaded playing-conditions preset ("custom" if hand-configured) */
  competitionId: string;
  /** Whether this match is a Final, for competitions with a different minimum-overs rule in Finals */
  isFinal: boolean;
  /** Minutes of a competition's "extra time" allowance used to offset time lost in the 1st innings */
  extraTimeUsedMinutes: number;
}
