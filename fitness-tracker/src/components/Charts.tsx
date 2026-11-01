export interface Point { label: string; value: number }
export interface Series { name: string; color: string; points: Point[]; dashed?: boolean }

const W = 340, H = 170, PAD_L = 36, PAD_R = 8, PAD_T = 10, PAD_B = 22

function niceRange(values: number[]): [number, number] {
  let lo = Math.min(...values), hi = Math.max(...values)
  if (lo === hi) { lo -= 1; hi += 1 }
  const pad = (hi - lo) * 0.1
  return [Math.max(0, Math.floor(lo - pad)), Math.ceil(hi + pad)]
}

export function LineChart({ series, label }: { series: Series[]; label: string }) {
  const n = Math.max(...series.map((s) => s.points.length))
  const all = series.flatMap((s) => s.points.map((p) => p.value))
  if (n === 0 || all.length === 0) return null
  const [lo, hi] = niceRange(all)
  const x = (i: number) => PAD_L + (n === 1 ? (W - PAD_L - PAD_R) / 2 : (i / (n - 1)) * (W - PAD_L - PAD_R))
  const y = (v: number) => PAD_T + (1 - (v - lo) / (hi - lo)) * (H - PAD_T - PAD_B)
  const ticks = [lo, (lo + hi) / 2, hi]
  const labels = series[0].points
  const every = Math.max(1, Math.ceil(labels.length / 5))
  return (
    <svg className="chart" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={label}>
      {ticks.map((t) => (
        <g key={t}>
          <line x1={PAD_L} x2={W - PAD_R} y1={y(t)} y2={y(t)} stroke="var(--border)" strokeWidth="1" />
          <text x={PAD_L - 6} y={y(t) + 4} textAnchor="end">{Math.round(t)}</text>
        </g>
      ))}
      {labels.map((p, i) => (i % every === 0 || i === labels.length - 1) && (
        <text key={i} x={x(i)} y={H - 6} textAnchor="middle">{p.label}</text>
      ))}
      {series.map((s) => (
        <g key={s.name}>
          <polyline
            fill="none" stroke={s.color} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round"
            strokeDasharray={s.dashed ? '5 4' : undefined}
            points={s.points.map((p, i) => `${x(i)},${y(p.value)}`).join(' ')}
          />
          {s.points.map((p, i) => <circle key={i} cx={x(i)} cy={y(p.value)} r="3.5" fill={s.color}><title>{`${p.label}: ${p.value}`}</title></circle>)}
        </g>
      ))}
    </svg>
  )
}

export function BarChart({ points, goal, label }: { points: Point[]; goal: number; label: string }) {
  const max = Math.max(goal * 1.15, ...points.map((p) => p.value), 1)
  const bw = (W - PAD_L - PAD_R) / points.length
  const y = (v: number) => PAD_T + (1 - v / max) * (H - PAD_T - PAD_B)
  return (
    <svg className="chart" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={label}>
      <text x={PAD_L - 6} y={y(goal) + 4} textAnchor="end">{goal}</text>
      {points.map((p, i) => (
        <g key={i}>
          <rect
            x={PAD_L + i * bw + 2} width={Math.max(2, bw - 4)} y={y(p.value)} height={Math.max(0, H - PAD_B - y(p.value))} rx="3"
            fill={p.value > goal ? 'var(--danger)' : 'var(--accent)'} opacity={p.value === 0 ? 0 : 0.9}
          ><title>{`${p.label}: ${p.value} kcal`}</title></rect>
          {(i % 2 === 0 || i === points.length - 1) && <text x={PAD_L + i * bw + bw / 2} y={H - 6} textAnchor="middle">{p.label}</text>}
        </g>
      ))}
      <line x1={PAD_L} x2={W - PAD_R} y1={y(goal)} y2={y(goal)} stroke="var(--text-muted)" strokeDasharray="4 4" />
    </svg>
  )
}
