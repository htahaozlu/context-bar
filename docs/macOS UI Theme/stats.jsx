/* stats.jsx — Stats tab, 820×680 window. Exports window.StatsWindow({theme}) */

function WinChrome({ theme, tab, children }) {
  const dark = theme === 'dark';
  const tabs = ['Stats', 'Cost', 'Settings'];
  return (
    <div className={'cb ' + (dark ? 'cb-dark' : 'cb-light')} style={{ height: '100%' }}>
      <div className="cb-win">
        <div className="cb-titlebar">
          <div className="cb-traffic">
            <i style={{ background: '#ff5f57' }} /><i style={{ background: '#febc2e' }} /><i style={{ background: '#28c840' }} />
          </div>
          <div className="cb-tabs">
            {tabs.map((t) => (
              <span key={t} className={'cb-tab' + (t === tab ? ' on' : '')}>
                <Icon name={t === 'Stats' ? 'chart' : t === 'Cost' ? 'dollar' : 'gear'} size={13} /> {t}
              </span>
            ))}
          </div>
          <div style={{ marginLeft: 'auto' }} className="cb-row">
            <span className="cb-chip"><span className="cb-dot live" />Live</span>
          </div>
        </div>
        {children}
      </div>
    </div>
  );
}

function SegCtrl({ options, value }) {
  return (
    <div className="cb-seg-ctrl">
      {options.map((o) => <button key={o} className={o === value ? 'on' : ''}>{o}</button>)}
    </div>
  );
}

function Tile({ k, v, vsub, s, accent }) {
  return (
    <div className="cb-tile" style={{ padding: 13, gap: 6 }}>
      <div className="k">{k}</div>
      <div className="num v" style={{ fontSize: 23, color: accent ? 'var(--accent)' : 'var(--text)' }}>{v}{vsub && <span style={{ fontSize: 13, color: 'var(--text-3)', fontWeight: 500 }}>{vsub}</span>}</div>
      {s && <div className="s">{s}</div>}
    </div>
  );
}

function Insight({ icon, metric, text }) {
  return (
    <div className="cb-insight">
      <Glyph name={icon} size={32} icon={17} />
      <div style={{ minWidth: 0 }}>
        <div className="num" style={{ fontSize: 18, fontWeight: 650, color: 'var(--text)', lineHeight: 1, marginBottom: 4 }}>{metric}</div>
        <div className="body" style={{ fontSize: 11.5 }}>{text}</div>
      </div>
    </div>
  );
}

const TOP_PROJECTS = [
  { name: 'context-bar', pct: 100, val: '14.8M' },
  { name: 'api-gateway', pct: 68, val: '10.1M' },
  { name: 'web-dashboard', pct: 47, val: '7.0M' },
  { name: 'infra-scripts', pct: 22, val: '3.3M' },
];

function StatsWindow({ theme = 'light' }) {
  const months = ['Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
  const data = heatData(52, 11);
  return (
    <WinChrome theme={theme} tab="Stats">
      <div className="cb-winbody" style={{ display: 'flex', flexDirection: 'column', gap: 15 }}>

        {/* controls */}
        <div className="cb-row" style={{ justifyContent: 'space-between' }}>
          <div>
            <div style={{ fontSize: 17, fontWeight: 650, color: 'var(--text)', letterSpacing: '-0.02em' }}>Activity</div>
            <div className="body" style={{ fontSize: 11.5 }}>All Claude Code sessions on this Mac</div>
          </div>
          <div className="cb-row" style={{ gap: 10 }}>
            <SegCtrl options={['Claude', 'Codex']} value="Claude" />
            <ModelFilter label="All models" />
            <SegCtrl options={['All time', '30d', '7d']} value="All time" />
          </div>
        </div>

        {/* overview — 6 highlighted */}
        <div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: 10 }}>
            <Tile k="Sessions" v="1,284" s="across 96 days" />
            <Tile k="Tokens" v="48.2" vsub="M" s="input + output" />
            <Tile k="Active days" v="96" s="of 142" />
            <Tile k="Current streak" v="12" vsub="d" s="best 21d" accent />
            <Tile k="Sub-agent share" v="24" vsub="%" s="of fresh tokens" />
            <Tile k="Favorite model" v="Sonnet" s="4.5 · 71%" />
          </div>
          <div className="cb-more" style={{ marginTop: 8 }}><Icon name="chevR" size={12} /> 4 more — longest streak, longest session, most active day, total cost</div>
        </div>

        {/* heatmap ⭐ */}
        <div className="cb-tile" style={{ padding: 14, gap: 10 }}>
          <div className="cb-row" style={{ justifyContent: 'space-between' }}>
            <span className="body" style={{ fontSize: 12.5, color: 'var(--text)' }}><b className="num" style={{ fontWeight: 650 }}>1,284</b> sessions in the last year</span>
            <div className="cb-row" style={{ gap: 6 }}>
              <span className="caption" style={{ fontSize: 9.5 }}>Less</span>
              <div className="cb-row" style={{ gap: 3 }}>
                {[8, 28, 52, 76, 100].map((a) => <b key={a} style={{ width: 11, height: 11, borderRadius: 2.5, background: `color-mix(in oklab, var(--accent) ${a}%, transparent)`, display: 'block' }} />)}
              </div>
              <span className="caption" style={{ fontSize: 9.5 }}>More</span>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <div style={{ display: 'grid', gridTemplateRows: 'repeat(7,1fr)', gap: 3, fontSize: 9, color: 'var(--text-3)', paddingTop: 16 }}>
              <span /><span>Mon</span><span /><span>Wed</span><span /><span>Fri</span><span />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="cb-row" style={{ justifyContent: 'space-between', marginBottom: 5, paddingLeft: 2 }}>
                {months.map((m) => <span key={m} className="num" style={{ fontSize: 9, color: 'var(--text-3)' }}>{m}</span>)}
              </div>
              <Heat weeks={52} data={data} />
            </div>
          </div>
        </div>

        {/* bottom: token composition + top projects (left), insights (right) */}
        <div style={{ display: 'grid', gridTemplateColumns: '1.35fr 1fr', gap: 16 }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div className="cb-tile" style={{ padding: 16, gap: 12 }}>
              <div className="cb-row" style={{ justifyContent: 'space-between' }}>
                <span className="caption">Token composition</span>
                <span className="num" style={{ fontSize: 11, color: 'var(--text-2)' }}>48.2M total</span>
              </div>
              <div className="cb-seg">
                <span style={{ width: '14%', background: 'var(--accent)' }} />
                <span style={{ width: '22%', background: 'color-mix(in oklab, var(--accent) 60%, transparent)' }} />
                <span style={{ width: '64%', background: 'color-mix(in oklab, var(--accent) 26%, transparent)' }} />
              </div>
              <div className="cb-row" style={{ gap: 16 }}>
                {[['Input', '14%', 'var(--accent)'], ['Output', '22%', 'color-mix(in oklab, var(--accent) 60%, transparent)'], ['Cache', '64%', 'color-mix(in oklab, var(--accent) 26%, transparent)']].map(([l, v, c]) => (
                  <span key={l} className="cb-row" style={{ gap: 6 }}>
                    <b style={{ width: 9, height: 9, borderRadius: 2, background: c, display: 'block' }} />
                    <span className="body" style={{ fontSize: 11, color: 'var(--text-2)' }}>{l} <b className="num" style={{ color: 'var(--text)', fontWeight: 600 }}>{v}</b></span>
                  </span>
                ))}
              </div>
            </div>
            <div className="cb-tile" style={{ padding: 16, gap: 11 }}>
              <span className="caption">Top projects · 30d</span>
              {TOP_PROJECTS.map((p) => (
                <div key={p.name} className="cb-row" style={{ gap: 10 }}>
                  <span className="body" style={{ fontSize: 11.5, color: 'var(--text)', width: 110, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.name}</span>
                  <div style={{ flex: 1 }}><Bar pct={p.pct} thin /></div>
                  <span className="num" style={{ fontSize: 11, color: 'var(--text-2)', width: 44, textAlign: 'right' }}>{p.val}</span>
                </div>
              ))}
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <Insight icon="people" metric="24%" text="of fresh tokens went to sub-agents — most of your work is delegated." />
            <Insight icon="gauge" metric="71% avg" text="context fill at compaction. You rarely hit the wall." />
          </div>
        </div>

      </div>
    </WinChrome>
  );
}

Object.assign(window, { StatsWindow, WinChrome, SegCtrl });
