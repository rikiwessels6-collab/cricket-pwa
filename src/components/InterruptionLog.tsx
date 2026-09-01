import { useEffect, useMemo, useState } from "react";
import { interruptionMinutesLost } from "../lib/oversCalculator";
import type { Interruption, TeamNames } from "../lib/types";

interface InterruptionLogProps {
  interruptions: Interruption[];
  teamNames: TeamNames;
  onAdd: (interruption: Omit<Interruption, "id">) => void;
  onUpdate: (id: string, patch: Partial<Interruption>) => void;
  onRemove: (id: string) => void;
}

function toLocalInputValue(iso: string): string {
  const d = new Date(iso);
  const offset = d.getTimezoneOffset();
  const local = new Date(d.getTime() - offset * 60000);
  return local.toISOString().slice(0, 16);
}

function fromLocalInputValue(local: string): string {
  return new Date(local).toISOString();
}

export function InterruptionLog({ interruptions, teamNames, onAdd, onUpdate, onRemove }: InterruptionLogProps) {
  const [now, setNow] = useState(() => new Date());
  const [inningsForNewStop, setInningsForNewStop] = useState<1 | 2>(1);
  const [note, setNote] = useState("");

  const ongoing = useMemo(() => interruptions.find((i) => i.resumedAt === null), [interruptions]);

  useEffect(() => {
    if (!ongoing) return;
    const id = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(id);
  }, [ongoing]);

  function handleStopPlay() {
    onAdd({
      innings: inningsForNewStop,
      stoppedAt: new Date().toISOString(),
      resumedAt: null,
      note: note.trim() || undefined,
    });
    setNote("");
  }

  function handleResumePlay() {
    if (!ongoing) return;
    onUpdate(ongoing.id, { resumedAt: new Date().toISOString() });
  }

  function handleAddManual() {
    const stoppedAt = new Date(now.getTime() - 10 * 60000).toISOString();
    const resumedAt = now.toISOString();
    onAdd({ innings: inningsForNewStop, stoppedAt, resumedAt, note: note.trim() || undefined });
    setNote("");
  }

  return (
    <section className="card" aria-labelledby="interruptions-heading">
      <h2 id="interruptions-heading">Interruptions</h2>

      <div className="field-grid">
        <label className="field">
          <span>Innings affected</span>
          <select
            value={inningsForNewStop}
            onChange={(e) => setInningsForNewStop(Number(e.target.value) as 1 | 2)}
            disabled={!!ongoing}
          >
            <option value={1}>{teamNames.team1 || "Team 1"} (1st innings)</option>
            <option value={2}>{teamNames.team2 || "Team 2"} (2nd innings)</option>
          </select>
        </label>
        <label className="field">
          <span>Note (optional)</span>
          <input
            type="text"
            placeholder="e.g. rain, bad light"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
        </label>
      </div>

      <div className="button-row">
        {!ongoing ? (
          <button type="button" className="btn btn-danger" onClick={handleStopPlay}>
            Stop play now
          </button>
        ) : (
          <button type="button" className="btn btn-primary" onClick={handleResumePlay}>
            Resume play now
          </button>
        )}
        <button type="button" className="btn btn-secondary" onClick={handleAddManual} disabled={!!ongoing}>
          Add past stoppage (10 min)
        </button>
      </div>

      {ongoing && (
        <p className="live-banner" role="status">
          Play stopped for {ongoing.innings === 1 ? teamNames.team1 : teamNames.team2} —{" "}
          {Math.floor(interruptionMinutesLost(ongoing, now))} min and counting
        </p>
      )}

      {interruptions.length === 0 ? (
        <p className="hint">No interruptions recorded yet.</p>
      ) : (
        <ul className="interruption-list">
          {[...interruptions].reverse().map((i) => (
            <li key={i.id} className="interruption-item">
              <div className="interruption-summary">
                <strong>{i.innings === 1 ? teamNames.team1 : teamNames.team2}</strong>
                <span>{Math.round(interruptionMinutesLost(i, now))} min</span>
                {i.resumedAt === null && <span className="badge">ongoing</span>}
              </div>
              <div className="field-grid">
                <label className="field">
                  <span>Stopped</span>
                  <input
                    type="datetime-local"
                    value={toLocalInputValue(i.stoppedAt)}
                    onChange={(e) => onUpdate(i.id, { stoppedAt: fromLocalInputValue(e.target.value) })}
                  />
                </label>
                <label className="field">
                  <span>Resumed</span>
                  <input
                    type="datetime-local"
                    value={i.resumedAt ? toLocalInputValue(i.resumedAt) : ""}
                    onChange={(e) =>
                      onUpdate(i.id, { resumedAt: e.target.value ? fromLocalInputValue(e.target.value) : null })
                    }
                  />
                </label>
              </div>
              {i.note && <p className="hint">{i.note}</p>}
              <button type="button" className="btn btn-link" onClick={() => onRemove(i.id)}>
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
