import { describe, expect, it } from "vitest";
import {
  applyRounding,
  formatOvers,
  interruptionMinutesLost,
  oversLostFromMinutes,
  revisedOversForInnings,
  totalMinutesLost,
} from "../oversCalculator";
import type { Interruption, MatchSettings } from "../types";

const baseSettings: MatchSettings = {
  totalOvers: 50,
  oversPerHour: 14.28,
  minimumOvers: 20,
  roundingRule: "nearest",
};

function interruption(overrides: Partial<Interruption> = {}): Interruption {
  return {
    id: "1",
    innings: 1,
    stoppedAt: "2026-09-01T10:00:00.000Z",
    resumedAt: "2026-09-01T11:00:00.000Z",
    ...overrides,
  };
}

describe("applyRounding", () => {
  it("rounds down", () => {
    expect(applyRounding(4.7, "down")).toBe(4);
  });
  it("rounds up", () => {
    expect(applyRounding(4.2, "up")).toBe(5);
  });
  it("rounds to nearest", () => {
    expect(applyRounding(4.5, "nearest")).toBe(5);
    expect(applyRounding(4.4, "nearest")).toBe(4);
  });
});

describe("interruptionMinutesLost", () => {
  it("computes minutes between stop and resume", () => {
    const i = interruption();
    expect(interruptionMinutesLost(i)).toBe(60);
  });

  it("measures an ongoing interruption against now", () => {
    const i = interruption({ resumedAt: null, stoppedAt: "2026-09-01T10:00:00.000Z" });
    const now = new Date("2026-09-01T10:30:00.000Z");
    expect(interruptionMinutesLost(i, now)).toBe(30);
  });

  it("never returns a negative duration", () => {
    const i = interruption({ stoppedAt: "2026-09-01T11:00:00.000Z", resumedAt: "2026-09-01T10:00:00.000Z" });
    expect(interruptionMinutesLost(i)).toBe(0);
  });
});

describe("totalMinutesLost", () => {
  it("sums only interruptions for the requested innings", () => {
    const interruptions = [
      interruption({ id: "a", innings: 1 }), // 60 min
      interruption({ id: "b", innings: 2, stoppedAt: "2026-09-01T12:00:00.000Z", resumedAt: "2026-09-01T12:20:00.000Z" }), // 20 min
    ];
    expect(totalMinutesLost(interruptions, 1)).toBe(60);
    expect(totalMinutesLost(interruptions, 2)).toBe(20);
  });
});

describe("oversLostFromMinutes", () => {
  it("applies the proportional formula: minutes/60 * oversPerHour", () => {
    // 60 minutes lost at 15 overs/hour => 15 overs lost
    expect(oversLostFromMinutes(60, { ...baseSettings, oversPerHour: 15 })).toBe(15);
  });

  it("rounds the result per the settings rounding rule", () => {
    // 10 minutes at 15/hr = 2.5 overs -> nearest rounds to 2 (banker's/Math.round rounds .5 up) => 3
    expect(oversLostFromMinutes(10, { ...baseSettings, oversPerHour: 15, roundingRule: "down" })).toBe(2);
    expect(oversLostFromMinutes(10, { ...baseSettings, oversPerHour: 15, roundingRule: "up" })).toBe(3);
  });
});

describe("revisedOversForInnings", () => {
  it("deducts overs lost from total overs", () => {
    const interruptions = [interruption({ innings: 1 })]; // 60 min lost
    const settings = { ...baseSettings, oversPerHour: 15 };
    const result = revisedOversForInnings(interruptions, 1, settings);
    expect(result.oversLost).toBe(15);
    expect(result.oversAvailable).toBe(35);
    expect(result.belowMinimum).toBe(false);
    expect(result.washedOut).toBe(false);
  });

  it("flags belowMinimum when overs drop under the threshold", () => {
    const interruptions = [
      interruption({ innings: 1, stoppedAt: "2026-09-01T10:00:00.000Z", resumedAt: "2026-09-01T12:30:00.000Z" }), // 150 min
    ];
    const settings = { ...baseSettings, oversPerHour: 15, minimumOvers: 20 };
    const result = revisedOversForInnings(interruptions, 1, settings);
    // 150 min @ 15/hr = 37.5 -> nearest = 38 overs lost, 50-38=12 available
    expect(result.oversLost).toBe(38);
    expect(result.oversAvailable).toBe(12);
    expect(result.belowMinimum).toBe(true);
    expect(result.washedOut).toBe(false);
  });

  it("never goes below zero overs and flags washedOut", () => {
    const interruptions = [
      interruption({ innings: 1, stoppedAt: "2026-09-01T10:00:00.000Z", resumedAt: "2026-09-01T20:00:00.000Z" }), // 10 hours
    ];
    const settings = { ...baseSettings, oversPerHour: 15 };
    const result = revisedOversForInnings(interruptions, 1, settings);
    expect(result.oversAvailable).toBe(0);
    expect(result.washedOut).toBe(true);
  });

  it("ignores interruptions from the other innings", () => {
    const interruptions = [interruption({ innings: 2 })];
    const settings = { ...baseSettings, oversPerHour: 15 };
    const result = revisedOversForInnings(interruptions, 1, settings);
    expect(result.oversLost).toBe(0);
    expect(result.oversAvailable).toBe(50);
  });
});

describe("formatOvers", () => {
  it("formats whole overs without a ball fraction", () => {
    expect(formatOvers(35)).toBe("35");
  });
  it("formats fractional overs as ball counts", () => {
    expect(formatOvers(35.5)).toBe("35.3");
    expect(formatOvers(12.1667)).toBe("12.1");
  });
});
