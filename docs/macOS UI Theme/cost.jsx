/* cost.jsx — Cost / Value tab, 820×680. Exports window.CostWindow({theme}) */

// 30-day cost series (deterministic, organic)
function costSeries() {
  const out = []; let s = 42;
  const rnd = () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
  for (let i = 0; i < 30; i++) {
    const trend = 40 + i * 2.0;
    const weekend = (i % 7 === 5 || i % 7 === 6) ? 0.4 : 1;
    out.push(Math.max(6, (trend + rnd() * 70) * weekend));
  }
  return out;
}

function AreaChart({ data, w = 720, h = 104 }) {
  const max = Math.max(...data) * 1.12;
  const stepX = w / (data.length - 1);
  const y = (v) => h - (v / max) * h;
  const pts = data.map((v, i) => [i * stepX, y(v)]);
  const line = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
  const area = `${line} L${w} ${h} L0 ${h} Z`;
  const hi = 22; // hover index
  const hp = pts[hi];
  return (
    <svg viewBox={`0 0 ${w} ${h + 4}`} style={{ width: '100%', height: h + 4, display: 'block', overflow: 'visible' }}>
      <defs>
        <linearGradient id="cbarea" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.26" />
          <stop offset="100%" stopColor="var(--accent)" stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill="url(#cbarea)" />
      <path d={line} fill="none" stroke="var(--accent)" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
      <line x1={hp[0]} y1="0" x2={hp[0]} y2={h} stroke="var(--hair-strong)" strokeWidth="1" strokeDasharray="3 3" />
      <circle cx={hp[0]} cy={hp[1]} r="4" fill="var(--accent)" stroke="var(--card-solid)" strokeWidth="2" />
    </svg>
  );
}

const DAILY = [
  { date: 'Jun 9',  proj: 'context-bar',   io: [16, 30, 54], total: '$118' },
  { date: 'Jun 8',  proj: 'api-gateway',   io: [22, 24, 54], total: '$96', open: true },
  { date: 'Jun 7',  proj: 'web-dashboard', io: [12, 20, 68], total: '$74' },
  { date: 'Jun 6',  proj: 'context-bar',   io: [18, 28, 54], total: '$61' },
  { date: 'Jun 5',  proj: 'infra-scripts', io: [9, 14, 77],  total: '$38' },
];

function DailyRow({ d }) {
  const segColors = ['var(--accent)', 'color-mix(in oklab, var(--accent) 58%, transparent)', 'color-mix(in oklab, var(--accent) 24%, transparent)'];
  return (
    <div style={{ borderTop: '0.5px solid var(--hair)' }}>
      <div className="cb-row" style={{ gap: 12, padding: '10px 0' }}>
        <span className="num" style={{ fontSize: 11, color: 'var(--text-2)', width: 46 }}>{d.date}</span>
        <span className="body" style={{ fontSize: 12, color: 'var(--text)', width: 116, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{d.proj}</span>
        <div className="cb-seg" style={{ flex: 1, height: 7 }}>
          {d.io.map((v, i) => <span key={i} style={{ width: v + '%', background: segColors[i] }} />)}
        </div>
        <span className="num" style={{ fontSize: 12.5, fontWeight: 600, color: 'var(--text)', width: 48, textAlign: 'right' }}>{d.total}</span>
        <Icon name={d.open ? 'chevD' : 'chevR'} size={13} style={{ color: 'var(--text-3)' }} />
      </div>
      {d.open && (
        <div className="cb-row" style={{ gap: 20, padding: '4px 0 12px 58px', flexWrap: 'wrap' }}>
          {[['Input', '0.42M', segColors[0]], ['Output', '0.31M', segColors[1]], ['Cache write', '1.1M', segColors[2]], ['Cache read', '4.8M', 'var(--text-3)']].map(([k, v, c]) => (
            <span key={k} className="cb-row" style={{ gap: 6 }}>
              <b style={{ width: 8, height: 8, borderRadius: 2, background: c, display: 'block' }} />
              <span className="body" style={{ fontSize: 10.5 }}>{k}</span>
              <span className="num" style={{ fontSize: 10.5, color: 'var(--text)', fontWeight: 600 }}>{v}</span>
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

function CostWindow({ theme = 'light', mode = 'plan' }) {
  const data = costSeries();
  const api = mode === 'api';
  return (
    <WinChrome theme={theme} tab="Cost">
      <div className="cb-winbody" style={{ display: 'flex', flexDirection: 'column', gap: 13 }}>

        <div className="cb-row" style={{ justifyContent: 'space-between' }}>
          <div>
            <div style={{ fontSize: 17, fontWeight: 650, color: 'var(--text)', letterSpacing: '-0.02em' }}>Cost &amp; value</div>
            <div className="body" style={{ fontSize: 11.5 }}>{api ? 'Real spend on models outside your plan' : 'API-equivalent estimate from local transcripts'}</div>
          </div>
          <div className="cb-row" style={{ gap: 10 }}>
            <SegCtrl options={['Claude', 'Codex']} value="Claude" />
            <ModelFilter label={api ? 'Opus 4.8' : 'All models'} billed={api} />
          </div>
        </div>

        {/* hero clarity + tiles */}
        <div style={{ display: 'grid', gridTemplateColumns: '1.5fr 1fr', gap: 16 }}>
          {/* hero clarity ⭐ */}
          <div className="cb-tile" style={{ padding: 18, gap: 0, borderRadius: 'var(--r-hero)', boxShadow: 'var(--shadow-hero)', position: 'relative', overflow: 'hidden' }}>
            <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 2.5, background: 'var(--accent)' }} />
            <div className="cb-row" style={{ justifyContent: 'space-between', marginBottom: 12 }}>
              <span className="caption">{api ? 'Actual API spend · billed to your key' : 'Estimated value · not a bill'}</span>
              {api
                ? <span className="cb-chip"><Icon name="info" size={11} /> API key ····7f2a</span>
                : <span className="cb-chip">Max 5× · <b className="num" style={{ color: 'var(--text)', fontWeight: 600 }}>$100/mo</b></span>}
            </div>
            <div className="cb-row" style={{ alignItems: 'flex-end', gap: 10, marginBottom: 14 }}>
              <span className="num" style={{ fontSize: 46, fontWeight: 600, color: 'var(--text)', lineHeight: 1 }}>{api ? '$57' : '≈ $2,847'}</span>
              <span className="body" style={{ fontSize: 14, color: 'var(--text-3)', paddingBottom: 6 }}>{api ? '/cycle' : '/mo'}</span>
            </div>
            <div className="body" style={{ fontSize: 12, maxWidth: 360, marginBottom: 14 }}>
              {api
                ? <React.Fragment>Opus&nbsp;4.8 isn't included in your plan. These tokens are charged straight to your Anthropic API key at standard rates — a real bill, not an estimate.</React.Fragment>
                : <React.Fragment>What your tokens would cost at pay-as-you-go API rates. You pay the flat plan — this is the value you're getting, not what you owe.</React.Fragment>}
            </div>
            <div className="cb-row" style={{ gap: 10, marginBottom: 16 }}>
              {api ? (
                <React.Fragment>
                  <span className="cb-row" style={{ gap: 6, padding: '5px 10px', borderRadius: 'var(--r-chip)', background: 'var(--accent-soft)', color: 'var(--accent)' }}>
                    <Icon name="dollar" size={13} /><b className="num" style={{ fontSize: 13, fontWeight: 650 }}>+ $57</b>
                    <span style={{ fontSize: 11.5, fontWeight: 600 }}>on top of plan</span>
                  </span>
                  <span className="body" style={{ fontSize: 11 }}>charged this cycle, separate from your $100 plan</span>
                </React.Fragment>
              ) : (
                <React.Fragment>
                  <span className="cb-row" style={{ gap: 6, padding: '5px 10px', borderRadius: 'var(--r-chip)', background: 'var(--positive-soft)', color: 'var(--positive)' }}>
                    <Icon name="trend" size={13} /><b className="num" style={{ fontSize: 13, fontWeight: 650 }}>28×</b>
                    <span style={{ fontSize: 11.5, fontWeight: 600 }}>plan value</span>
                  </span>
                  <span className="body" style={{ fontSize: 11 }}>$2,747 more than your $100 plan</span>
                </React.Fragment>
              )}
            </div>
            <div>
              <div className="cb-row" style={{ justifyContent: 'space-between', marginBottom: 6 }}>
                <span className="caption" style={{ fontSize: 9.5 }}>{api ? 'Budget alert' : 'Billing cycle pace'}</span>
                <span className="num" style={{ fontSize: 10.5, color: 'var(--text-2)' }}>{api ? '$57 / $150 cap' : 'day 18 / 30'}</span>
              </div>
              <Bar pct={api ? 38 : 60} threshold={api ? 100 : 200} />
            </div>
          </div>
          {/* tiles */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gridTemplateRows: '1fr 1fr', gap: 12 }}>
            <Tile k="Today" v="$94" s="↑ 12% vs avg" />
            <Tile k="7 days" v="$612" s="≈ $87/day" />
            <Tile k="30 days" v="$2,847" s="full window" />
            <div className="cb-tile" style={{ padding: 13, gap: 8, justifyContent: 'center' }}>
              <div className="k">In · Out</div>
              <div className="cb-seg" style={{ height: 7 }}>
                <span style={{ width: '21%', background: 'var(--accent)' }} />
                <span style={{ width: '79%', background: 'color-mix(in oklab, var(--accent) 40%, transparent)' }} />
              </div>
              <div className="cb-row" style={{ justifyContent: 'space-between' }}>
                <span className="num" style={{ fontSize: 12, color: 'var(--text)', fontWeight: 600 }}>$612</span>
                <span className="num" style={{ fontSize: 12, color: 'var(--text-2)', fontWeight: 600 }}>$2,235</span>
              </div>
            </div>
          </div>
        </div>

        {/* trend */}
        <div className="cb-tile" style={{ padding: 16, gap: 10 }}>
          <div className="cb-row" style={{ justifyContent: 'space-between' }}>
            <span className="caption">30-day cost trend</span>
            <span className="cb-chip" style={{ borderColor: 'var(--accent-soft)', background: 'var(--accent-softer)', color: 'var(--text)' }}>
              Jun 1 · <b className="num" style={{ fontWeight: 600 }}>$132</b>
            </span>
          </div>
          <AreaChart data={data} />
        </div>

        {/* model filter made visible: per-model cost + how it's calculated */}
        <div style={{ display: 'grid', gridTemplateColumns: '1.55fr 1fr', gap: 16, alignItems: 'start' }}>
          <ModelBreakdown />
          <CalcNote />
        </div>

        {/* daily cost — simplified to bars */}
        <div className="cb-tile" style={{ padding: '8px 16px 12px', gap: 0 }}>
          <div className="cb-row" style={{ justifyContent: 'space-between', padding: '8px 0 2px' }}>
            <span className="caption">Daily breakdown</span>
            <span className="caption" style={{ fontSize: 9.5 }}>input · output · cache</span>
          </div>
          {DAILY.map((d) => <DailyRow key={d.date} d={d} />)}
        </div>

      </div>
    </WinChrome>
  );
}

Object.assign(window, { CostWindow });
