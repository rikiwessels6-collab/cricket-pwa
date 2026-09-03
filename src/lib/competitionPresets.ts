import type { MatchSettings } from "./types";

export const CUSTOM_PRESET_ID = "custom";

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
  /** Human-readable citation of the clauses these numbers come from. */
  citation: string;
  sourceLabel: string;
  sourceUrl: string;
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
    citation: "cl. 13.7.2, 13.8.2, 16.1.2 & 16.4 — One Day Cup Playing Conditions",
    sourceLabel: "2026-27 One Day Cup Playing Conditions (1 September 2026)",
    sourceUrl: "https://drive.google.com/file/d/1PQiZB-rof6ceKTxC7FiBbI06oHlECsS9/view",
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
