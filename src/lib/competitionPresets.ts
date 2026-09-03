import type { MatchSettings } from "./types";

export const CUSTOM_PRESET_ID = "custom";

export interface IntervalReductionStep {
  /** The interval steps down to newIntervalMinutes once minutes lost in the 1st innings reaches this. */
  minutesLostThreshold: number;
  newIntervalMinutes: number;
}

export interface OverRateCutoff {
  /** Minutes of playing time into a full, unreduced innings by which the last over must start. */
  fullInningsMinutes: number;
  /** Adjustment applied per over when the innings is reduced (mirrors each competition's own formula). */
  extraMinutes: number;
  /** Below this many overs, the over-rate cut-off no longer applies. */
  minimumOversForCutoff?: number;
}

export interface CompetitionPreset {
  id: string;
  label: string;
  season: string;
  /** Settings applied when this preset is selected and it is not a Final. */
  settings: MatchSettings;
  /** Minimum overs required for a result when the match is a Final, if different. */
  minimumOversFinal?: number;
  /** If set, no bowler may bowl more than 1/N of the total overs once the innings is reduced. */
  bowlerOversLimitDivisor?: number;
  /** Minutes of "extra time" that may be used to make up lost playing time before overs/interval are reduced. */
  extraTimeAllowanceMinutes?: number;
  /** Default interval between innings, and how it steps down as time is lost in the 1st innings. */
  intervalMinutesDefault?: number;
  intervalReductions?: IntervalReductionStep[];
  overRateCutoff?: OverRateCutoff;
  /** Human-readable citation of the clauses these numbers come from. */
  citation: string;
  sourceLabel: string;
  sourceUrl?: string;
}

export const COMPETITION_PRESETS: CompetitionPreset[] = [
  {
    id: "odc-2026-27",
    label: "Marsh One Day Cup",
    season: "2026-27",
    settings: {
      totalOvers: 50,
      oversPerHour: 14.28,
      minimumOvers: 15,
      roundingRule: "down",
    },
    minimumOversFinal: 20,
    bowlerOversLimitDivisor: 5,
    intervalMinutesDefault: 30,
    intervalReductions: [{ minutesLostThreshold: 60, newIntervalMinutes: 20 }],
    overRateCutoff: { fullInningsMinutes: 206, extraMinutes: -4, minimumOversForCutoff: 25 },
    citation: "cl. 11.3.2, 12.7-12.8, 13.7.2, 13.8.2, 16.1.2 & 16.4 — One Day Cup Playing Conditions",
    sourceLabel: "2026-27 One Day Cup Playing Conditions (1 September 2026)",
    sourceUrl: "https://drive.google.com/file/d/1PQiZB-rof6ceKTxC7FiBbI06oHlECsS9/view",
  },
  {
    id: "wncl-2026-27",
    label: "WNCL",
    season: "2026-27",
    settings: {
      totalOvers: 50,
      oversPerHour: 15.79,
      minimumOvers: 15,
      roundingRule: "down",
    },
    minimumOversFinal: 20,
    bowlerOversLimitDivisor: 5,
    extraTimeAllowanceMinutes: 60,
    intervalMinutesDefault: 40,
    intervalReductions: [
      { minutesLostThreshold: 1, newIntervalMinutes: 30 },
      { minutesLostThreshold: 60, newIntervalMinutes: 20 },
    ],
    overRateCutoff: { fullInningsMinutes: 187, extraMinutes: -3, minimumOversForCutoff: 25 },
    citation: "cl. 11.3.2, 12.7-12.8, 13.7.2, 13.8.2, 16.1.2 & 16.4 — WNCL Playing Conditions",
    sourceLabel: "2026-27 WNCL Playing Conditions (1 September 2026)",
    sourceUrl: "https://drive.google.com/file/d/1JBXThE77gVjPJ0cv5A4i0eNyJA6g5ZSe/view",
  },
  {
    id: "bbl-2024-25",
    label: "Big Bash League",
    season: "2024-25",
    settings: {
      totalOvers: 20,
      oversPerHour: 15,
      minimumOvers: 5,
      roundingRule: "down",
    },
    bowlerOversLimitDivisor: 5,
    intervalMinutesDefault: 15,
    intervalReductions: [{ minutesLostThreshold: 21, newIntervalMinutes: 10 }],
    overRateCutoff: { fullInningsMinutes: 79, extraMinutes: 3, minimumOversForCutoff: 10 },
    citation: "cl. 11.3, 12.7-12.8, 13.7.2, 13.8.2 & 16.1.2 — Big Bash League Playing Conditions",
    sourceLabel: "BBL Playing Conditions Almanac 2024/25",
  },
  {
    id: "wbbl-2025-26",
    label: "WBBL",
    season: "2025-26",
    settings: {
      totalOvers: 20,
      oversPerHour: 16,
      minimumOvers: 5,
      roundingRule: "down",
    },
    bowlerOversLimitDivisor: 5,
    intervalMinutesDefault: 15,
    intervalReductions: [{ minutesLostThreshold: 16, newIntervalMinutes: 10 }],
    overRateCutoff: { fullInningsMinutes: 73, extraMinutes: 2, minimumOversForCutoff: 10 },
    citation: "cl. 11.3, 12.7-12.8, 13.7.2, 13.8.2 & 16.1.2 — WBBL Playing Conditions",
    sourceLabel: "WBBL Playing Conditions Almanac 2025/26",
  },
];

export function findPreset(id: string): CompetitionPreset | undefined {
  return COMPETITION_PRESETS.find((p) => p.id === id);
}

export function settingsForPreset(preset: CompetitionPreset, isFinal: boolean): MatchSettings {
  if (isFinal && preset.minimumOversFinal !== undefined) {
    return { ...preset.settings, minimumOvers: preset.minimumOversFinal };
  }
  return { ...preset.settings };
}

/** The interval between innings for this preset, stepped down per minutes lost in the 1st innings. */
export function intervalMinutesForTimeLost(preset: CompetitionPreset, minutesLost: number): number | null {
  if (preset.intervalMinutesDefault === undefined) return null;
  const steps = preset.intervalReductions ?? [];
  const applicable = steps
    .filter((s) => minutesLost >= s.minutesLostThreshold)
    .sort((a, b) => b.minutesLostThreshold - a.minutesLostThreshold);
  return applicable.length > 0 ? applicable[0].newIntervalMinutes : preset.intervalMinutesDefault;
}

/** Minutes of playing time by which the last over of an innings with this many overs must start, or null if no cut-off applies. */
export function overRateCutoffMinutes(cutoff: OverRateCutoff, settings: MatchSettings, overs: number): number | null {
  if (cutoff.minimumOversForCutoff !== undefined && overs < cutoff.minimumOversForCutoff) return null;

  const totalOvers = settings.totalOvers;
  const minutesPerOver = 60 / settings.oversPerHour;
  if (overs >= totalOvers) return cutoff.fullInningsMinutes;

  if (cutoff.extraMinutes > 0) {
    return Math.round((overs - 1) * minutesPerOver + cutoff.extraMinutes);
  }
  return Math.round(overs * minutesPerOver + cutoff.extraMinutes);
}
