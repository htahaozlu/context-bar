/* models.jsx — model filter + availability/billing.
   The cost calc is plan-equivalent VALUE for plan models, but a real BILL for
   API-only models (e.g. a model removed from the plan after a date, or a future
   model only offered via API). Exports:
     window.MODELS, ModelFilter, ModelFilterMenu, ModelBreakdown, CalcNote */

// avail: 'plan' (covered) · 'sunset' (leaves plan on `date`, API-only after) · 'api' (never in plan, billed)
const MODELS = [
  { name: 'Sonnet 4.5', avail: 'plan',   pct: 100, val: '$1,840' },
  { name: 'Opus 4.1',   avail: 'plan',   pct: 38,  val: '$640'   },
  { name: 'Haiku 4.5',  avail: 'plan',   pct: 9,   val: '$120'   },
  { name: 'Sonnet 3.7', avail: 'sunset', pct: 12,  val: '$190', date: 'Jun 22' },
  { name: 'Opus 4.8',   avail: 'api',    pct: 5,   val: '$57'    },
];

function availSub(m) {
  if (m.avail === 'plan')   return 'In your plan';
  if (m.avail === 'sunset') return 'Plan ends ' + m.date;
  return 'Billed to API key';
}

// small text badge — neutral for plan, accent for anything that costs real money
function AvailBadge({ avail, date, mini }) {
  const base = {
    fontSize: mini ? 10 : 10.5, fontWeight: 600, letterSpacing: '-0.01em',
    padding: mini ? '2px 6px' : '2px 7px', borderRadius: 6, whiteSpace: 'nowrap', lineHeight: 1.3,
  };
  if (avail === 'plan')
    return <span style={{ ...base, color: 'var(--text-3)', background: 'var(--quiet-2)' }}>In plan</span>;
  if (avail === 'sunset')
    return <span style={{ ...base, color: 'var(--accent)', background: 'var(--accent-softer)', border: '0.5px solid var(--accent-soft)' }}>Plan → API · {date}</span>;
  return <span style={{ ...base, color: 'var(--accent)', background: 'var(--accent-soft)' }}>API-only</span>;
}

// ---- collapsed filter trigger (lives in a window header) ----
function ModelFilter({ label = 'All models', billed }) {
  return (
    <span className="cb-row" style={{ gap: 7, padding: '4px 8px 4px 10px', borderRadius: 7,
      background: 'var(--card-solid)', border: '0.5px solid var(--hair-strong)', boxShadow: '0 0.5px 1px rgba(0,0,0,.1)' }}>
      <Icon name="stack" size={12} style={{ color: 'var(--text-3)' }} />
      <span style={{ fontSize: 12, color: 'var(--text)', fontWeight: 500 }}>{label}</span>
      {billed && <span className="cb-dot" style={{ width: 6, height: 6 }} title="billed model in scope" />}
      <svg width="9" height="6" viewBox="0 0 9 6" fill="none" stroke="var(--text-3)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M1.5 1.5 4.5 4.5 7.5 1.5" />
      </svg>
    </span>
  );
}

// ---- tiny rounded checkbox ----
function Check({ on }) {
  return (
    <span style={{ width: 15, height: 15, borderRadius: 4, flex: '0 0 auto',
      background: on ? 'var(--accent)' : 'transparent',
      border: on ? '0.5px solid var(--accent)' : '1px solid var(--hair-strong)',
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
      {on && <Icon name="check" size={10} sw={2.4} style={{ color: '#fff' }} />}
    </span>
  );
}

// ---- the open dropdown (its own artboard) ----
function ModelFilterMenu({ theme = 'light' }) {
  const dark = theme === 'dark';
  return (
    <div className={'cb ' + (dark ? 'cb-dark' : 'cb-light')} style={{ height: '100%' }}>
      <div style={{ background: 'var(--window)', height: '100%', padding: 20, display: 'flex', alignItems: 'flex-start', justifyContent: 'center' }}>
        <div style={{ width: 300, background: 'var(--card-solid)', borderRadius: 12, padding: 6,
          border: '0.5px solid var(--hair)', boxShadow: 'var(--shadow-hero)' }}>
          <div className="caption" style={{ padding: '7px 10px 7px' }}>Filter by model</div>

          <div className="cb-row" style={{ gap: 10, padding: '7px 10px', borderRadius: 7 }}>
            <Check on />
            <span style={{ fontSize: 12.5, color: 'var(--text)', flex: 1, fontWeight: 500 }}>All models</span>
          </div>

          <div className="cb-div" style={{ margin: '4px 6px' }} />

          {MODELS.map((m, i) => (
            <div key={i} className="cb-row" style={{ gap: 10, padding: '7px 10px', borderRadius: 7,
              background: m.avail === 'api' ? 'var(--quiet)' : 'transparent' }}>
              <Check on={m.avail !== 'api'} />
              <span style={{ fontSize: 12.5, color: 'var(--text)', flex: 1 }}>{m.name}</span>
              <AvailBadge avail={m.avail} date={m.date} mini />
            </div>
          ))}

          <div className="cb-div" style={{ margin: '4px 6px' }} />

          <div className="cb-row" style={{ gap: 8, padding: '8px 10px', alignItems: 'flex-start' }}>
            <Icon name="info" size={12} style={{ color: 'var(--text-3)', marginTop: 1, flex: '0 0 auto' }} />
            <span className="body" style={{ fontSize: 10.5, lineHeight: 1.4 }}>
              API-only models are billed to your API key — not covered by your plan.
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

// ---- per-model cost breakdown (a card inside the Cost window) ----
function ModelBreakdown() {
  return (
    <div className="cb-tile" style={{ padding: '8px 16px 14px', gap: 0 }}>
      <div className="cb-row" style={{ justifyContent: 'space-between', padding: '8px 0 2px' }}>
        <span className="caption">Cost by model · 30d</span>
        <span className="caption" style={{ fontSize: 9.5 }}>value · billed</span>
      </div>
      {MODELS.map((m, i) => {
        const billed = m.avail !== 'plan';
        return (
          <div key={i} className="cb-row" style={{ gap: 12, padding: '10px 0', borderTop: '0.5px solid var(--hair)' }}>
            <div style={{ width: 118, minWidth: 0 }}>
              <div className="body" style={{ fontSize: 12, color: 'var(--text)' }}>{m.name}</div>
              <div className="body" style={{ fontSize: 10, color: billed ? 'var(--accent)' : 'var(--text-3)' }}>{availSub(m)}</div>
            </div>
            <div style={{ flex: 1 }}><Bar pct={m.pct} thin /></div>
            <div style={{ width: 56, textAlign: 'right' }}>
              <div className="num" style={{ fontSize: 12, fontWeight: 600, color: m.avail === 'api' ? 'var(--accent)' : 'var(--text)' }}>{m.val}</div>
              <div className="body" style={{ fontSize: 9, color: 'var(--text-3)' }}>{m.avail === 'api' ? 'billed' : 'value'}</div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ---- compact "how it's calculated" note ----
function CalcNote() {
  return (
    <div className="cb-tile" style={{ padding: 14, gap: 8 }}>
      <div className="cb-row" style={{ gap: 7 }}>
        <Icon name="info" size={13} style={{ color: 'var(--text-2)' }} />
        <span className="caption" style={{ margin: 0 }}>How this is calculated</span>
      </div>
      <div className="body" style={{ fontSize: 11.5 }}>
        Tokens are read from your local transcripts and multiplied by each model's published
        per-million rates — input, output, cache-write (<span className="num">×1.25</span>) and
        cache-read (<span className="num">×0.1</span>).{' '}
        <b style={{ color: 'var(--text)', fontWeight: 600 }}>Plan models</b> show the API-equivalent
        value your flat plan already covers;{' '}
        <b style={{ color: 'var(--text)', fontWeight: 600 }}>API-only models</b> show real spend
        billed to your key.
      </div>
      <div className="num" style={{ fontSize: 10.5, color: 'var(--text-3)' }}>Σ ( tokensₘ ÷ 1M × rateₘ )  for each model m</div>
    </div>
  );
}

Object.assign(window, { MODELS, ModelFilter, ModelFilterMenu, ModelBreakdown, CalcNote });
