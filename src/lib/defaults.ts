import { CUSTOM_PRESET_ID } from "./competitionPresets";
import type { MatchState } from "./types";

export const DEFAULT_MATCH_STATE: MatchState = {
  settings: {
    totalOvers: 50,
    oversPerHour: 14.3,
    minimumOvers: 20,
    roundingRule: "nearest",
  },
  teamNames: {
    team1: "Team 1",
    team2: "Team 2",
  },
  interruptions: [],
  team1: {
    runs: 0,
    oversFaced: 0,
    wicketsLost: 0,
  },
  team2: {
    wicketsLost: 0,
  },
  competitionId: CUSTOM_PRESET_ID,
  isFinal: false,
  extraTimeUsedMinutes: 0,
};
