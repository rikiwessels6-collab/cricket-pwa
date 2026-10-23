import { describe, expect, it } from "vitest";
import { estimateParScore, resourceFraction, resourcePercent } from "../parScore";

describe("resourceFraction", () => {
  it("is 100% at full overs and no wickets down", () => {
    expect(resourceFraction(50, 0, 50)).toBeCloseTo(1, 5);
  });

  it("is 0 when no overs remain", () => {
    expect(resourceFraction(0, 3, 50)).toBe(0);
  });

  it("is 0 when all 10 wickets are down, regardless of overs left", () => {
    expect(resourceFraction(30, 10, 50)).toBe(0);
  });

  it("decreases as wickets fall, for the same overs remaining", () => {
    const noWickets = resourceFraction(25, 0, 50);
    const fiveDown = resourceFraction(25, 5, 50);
    expect(fiveDown).toBeLessThan(noWickets);
  });

  it("decreases as overs remaining decreases, for the same wickets", () => {
    const moreOvers = resourceFraction(30, 2, 50);
    const fewerOvers = resourceFraction(10, 2, 50);
    expect(fewerOvers).toBeLessThan(moreOvers);
  });

  it("clamps out-of-range inputs instead of producing nonsense", () => {
    expect(resourceFraction(-5, 0, 50)).toBe(resourceFraction(0, 0, 50));
    expect(resourceFraction(60, 0, 50)).toBe(resourceFraction(50, 0, 50));
  });
});

describe("resourcePercent", () => {
  it("returns a 0-100 percentage rounded to one decimal", () => {
    expect(resourcePercent(50, 0, 50)).toBe(100);
    expect(resourcePercent(0, 0, 50)).toBe(0);
  });
});

describe("estimateParScore", () => {
  it("scales the target down when team 2 has fewer overs than team 1 used", () => {
    // Team 1 batted all 50 overs, lost 6 wickets, scored 250.
    // Team 2 only gets 30 overs due to a rain delay, 0 wickets down (start of chase).
    const result = estimateParScore({
      totalOvers: 50,
      team1Runs: 250,
      team1OversFaced: 50,
      team1WicketsLost: 6,
      team2OversAvailable: 30,
      team2WicketsLost: 0,
    });
    expect(result.parScore).toBeLessThan(250);
    expect(result.parScore).toBeGreaterThan(0);
    expect(result.target).toBe(result.parScore + 1);
  });

  it("matches team1 runs when resources are identical (uninterrupted match)", () => {
    const result = estimateParScore({
      totalOvers: 50,
      team1Runs: 200,
      team1OversFaced: 50,
      team1WicketsLost: 10,
      team2OversAvailable: 50,
      team2WicketsLost: 0,
    });
    // Team 1 used 100% of resources (all out), team 2 starts with 100% available.
    expect(result.parScore).toBe(200);
  });

  it("accounts for wickets already lost by team 2 mid-chase", () => {
    const early = estimateParScore({
      totalOvers: 50,
      team1Runs: 250,
      team1OversFaced: 50,
      team1WicketsLost: 6,
      team2OversAvailable: 30,
      team2WicketsLost: 0,
    });
    const afterCollapse = estimateParScore({
      totalOvers: 50,
      team1Runs: 250,
      team1OversFaced: 50,
      team1WicketsLost: 6,
      team2OversAvailable: 30,
      team2WicketsLost: 7,
    });
    expect(afterCollapse.parScore).toBeLessThan(early.parScore);
  });

  it("never returns a negative par score", () => {
    const result = estimateParScore({
      totalOvers: 50,
      team1Runs: 250,
      team1OversFaced: 50,
      team1WicketsLost: 10,
      team2OversAvailable: 0,
      team2WicketsLost: 0,
    });
    expect(result.parScore).toBe(0);
  });
});
