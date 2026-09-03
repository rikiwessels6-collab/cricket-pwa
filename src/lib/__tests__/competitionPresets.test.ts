import { describe, expect, it } from "vitest";
import {
  COMPETITION_PRESETS,
  findPreset,
  intervalMinutesForTimeLost,
  overRateCutoffMinutes,
  settingsForPreset,
} from "../competitionPresets";

const odc = findPreset("odc-2026-27")!;
const wncl = findPreset("wncl-2026-27")!;
const bbl = findPreset("bbl-2024-25")!;
const wbbl = findPreset("wbbl-2025-26")!;

describe("COMPETITION_PRESETS", () => {
  it("includes all four Cricket Australia competitions", () => {
    const ids = COMPETITION_PRESETS.map((p) => p.id);
    expect(ids).toEqual(["odc-2026-27", "wncl-2026-27", "bbl-2024-25", "wbbl-2025-26"]);
  });
});

describe("settingsForPreset", () => {
  it("uses the regular minimum overs when not a Final", () => {
    expect(settingsForPreset(odc, false).minimumOvers).toBe(15);
  });

  it("switches to the Final minimum overs when isFinal", () => {
    expect(settingsForPreset(odc, true).minimumOvers).toBe(20);
  });

  it("leaves minimum overs unchanged for presets without a Final distinction", () => {
    expect(settingsForPreset(bbl, true).minimumOvers).toBe(5);
  });
});

describe("intervalMinutesForTimeLost", () => {
  it("returns the default interval when no time has been lost", () => {
    expect(intervalMinutesForTimeLost(odc, 0)).toBe(30);
    expect(intervalMinutesForTimeLost(wncl, 0)).toBe(40);
  });

  it("steps ODC's interval down to 20 once 60+ minutes are lost (cl. 11.3.2.1)", () => {
    expect(intervalMinutesForTimeLost(odc, 59)).toBe(30);
    expect(intervalMinutesForTimeLost(odc, 60)).toBe(20);
  });

  it("applies WNCL's two-step reduction (cl. 11.3.2.1.1-2)", () => {
    expect(intervalMinutesForTimeLost(wncl, 0)).toBe(40);
    expect(intervalMinutesForTimeLost(wncl, 1)).toBe(30);
    expect(intervalMinutesForTimeLost(wncl, 59)).toBe(30);
    expect(intervalMinutesForTimeLost(wncl, 60)).toBe(20);
  });

  it("applies the BBL/WBBL single-step reductions", () => {
    expect(intervalMinutesForTimeLost(bbl, 20)).toBe(15);
    expect(intervalMinutesForTimeLost(bbl, 21)).toBe(10);
    expect(intervalMinutesForTimeLost(wbbl, 15)).toBe(15);
    expect(intervalMinutesForTimeLost(wbbl, 16)).toBe(10);
  });
});

describe("overRateCutoffMinutes", () => {
  it("returns the full-innings cut-off at the scheduled overs (cl. 12.8.1)", () => {
    expect(overRateCutoffMinutes(odc.overRateCutoff!, odc.settings, 50)).toBe(206);
    expect(overRateCutoffMinutes(wncl.overRateCutoff!, wncl.settings, 50)).toBe(187);
    expect(overRateCutoffMinutes(bbl.overRateCutoff!, bbl.settings, 20)).toBe(79);
    expect(overRateCutoffMinutes(wbbl.overRateCutoff!, wbbl.settings, 20)).toBe(73);
  });

  it("scales down for a reduced ODC/WNCL innings using a negative adjustment", () => {
    // 40 overs @ 4.2 min/over - 4 = 164
    expect(overRateCutoffMinutes(odc.overRateCutoff!, odc.settings, 40)).toBe(164);
  });

  it("scales down for a reduced BBL/WBBL innings using the (overs-1) formula", () => {
    // (19-1) * 4.0 + 3 = 75
    expect(overRateCutoffMinutes(bbl.overRateCutoff!, bbl.settings, 19)).toBe(75);
  });

  it("returns null below the competition's minimum-overs-for-cutoff threshold", () => {
    expect(overRateCutoffMinutes(odc.overRateCutoff!, odc.settings, 24)).toBeNull();
    expect(overRateCutoffMinutes(bbl.overRateCutoff!, bbl.settings, 9)).toBeNull();
  });
});
