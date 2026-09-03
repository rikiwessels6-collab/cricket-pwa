import { useCallback, useEffect, useState } from "react";
import { CUSTOM_PRESET_ID, findPreset, settingsForPreset } from "../lib/competitionPresets";
import { DEFAULT_MATCH_STATE } from "../lib/defaults";
import { generateId } from "../lib/id";
import type { Interruption, MatchSettings, MatchState, Team1Figures, Team2Figures, TeamNames } from "../lib/types";

const STORAGE_KEY = "cricket-pwa/match-state";

function loadInitialState(): MatchState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_MATCH_STATE;
    const parsed = JSON.parse(raw) as MatchState;
    return {
      ...DEFAULT_MATCH_STATE,
      ...parsed,
      settings: { ...DEFAULT_MATCH_STATE.settings, ...parsed.settings },
      teamNames: { ...DEFAULT_MATCH_STATE.teamNames, ...parsed.teamNames },
      team1: { ...DEFAULT_MATCH_STATE.team1, ...parsed.team1 },
      team2: { ...DEFAULT_MATCH_STATE.team2, ...parsed.team2 },
      interruptions: parsed.interruptions ?? [],
    };
  } catch {
    return DEFAULT_MATCH_STATE;
  }
}

export function useMatchState() {
  const [state, setState] = useState<MatchState>(loadInitialState);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } catch {
      // localStorage unavailable (private mode, quota) — state still works in-memory.
    }
  }, [state]);

  const updateSettings = useCallback((patch: Partial<MatchSettings>) => {
    setState((prev) => ({ ...prev, settings: { ...prev.settings, ...patch } }));
  }, []);

  const updateTeamNames = useCallback((patch: Partial<TeamNames>) => {
    setState((prev) => ({ ...prev, teamNames: { ...prev.teamNames, ...patch } }));
  }, []);

  const updateTeam1 = useCallback((patch: Partial<Team1Figures>) => {
    setState((prev) => ({ ...prev, team1: { ...prev.team1, ...patch } }));
  }, []);

  const updateTeam2 = useCallback((patch: Partial<Team2Figures>) => {
    setState((prev) => ({ ...prev, team2: { ...prev.team2, ...patch } }));
  }, []);

  const addInterruption = useCallback((interruption: Omit<Interruption, "id">) => {
    setState((prev) => ({
      ...prev,
      interruptions: [...prev.interruptions, { ...interruption, id: generateId() }],
    }));
  }, []);

  const updateInterruption = useCallback((id: string, patch: Partial<Interruption>) => {
    setState((prev) => ({
      ...prev,
      interruptions: prev.interruptions.map((i) => (i.id === id ? { ...i, ...patch } : i)),
    }));
  }, []);

  const removeInterruption = useCallback((id: string) => {
    setState((prev) => ({
      ...prev,
      interruptions: prev.interruptions.filter((i) => i.id !== id),
    }));
  }, []);

  const resetMatch = useCallback(() => {
    setState(DEFAULT_MATCH_STATE);
  }, []);

  const selectCompetition = useCallback((competitionId: string) => {
    setState((prev) => {
      if (competitionId === CUSTOM_PRESET_ID) {
        return { ...prev, competitionId, extraTimeUsedMinutes: 0 };
      }
      const preset = findPreset(competitionId);
      if (!preset) return prev;
      return {
        ...prev,
        competitionId,
        isFinal: false,
        settings: settingsForPreset(preset, false),
        extraTimeUsedMinutes: 0,
      };
    });
  }, []);

  const setIsFinal = useCallback((isFinal: boolean) => {
    setState((prev) => {
      const preset = findPreset(prev.competitionId);
      if (!preset) return { ...prev, isFinal };
      return { ...prev, isFinal, settings: settingsForPreset(preset, isFinal) };
    });
  }, []);

  const updateExtraTimeUsed = useCallback((minutes: number) => {
    setState((prev) => {
      const preset = findPreset(prev.competitionId);
      const allowance = preset?.extraTimeAllowanceMinutes ?? 0;
      const clamped = Math.min(Math.max(0, minutes), allowance);
      return { ...prev, extraTimeUsedMinutes: clamped };
    });
  }, []);

  return {
    state,
    updateSettings,
    updateTeamNames,
    updateTeam1,
    updateTeam2,
    addInterruption,
    updateInterruption,
    removeInterruption,
    resetMatch,
    selectCompetition,
    setIsFinal,
    updateExtraTimeUsed,
  };
}
