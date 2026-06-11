/* popover.jsx — the 360pt menubar popover (priority screen).
   Exports window.Popover({theme, variant, threshold, showSessions, showTools, accentL, accentD}) */

const SESSIONS = [
  { proj: 'api-gateway',    model: 'Sonnet 4.5', pct: 34, time: '12m' },
  { proj: 'web-dashboard',  model: 'Opus 4.1',   pct: 61, time: '3m'  },
  { proj: 'infra-scripts',  model: 'Sonnet 4.5', pct: 19, time: '1h2m' },
];
const TOOLS = [
  { name: 'Gemini',  icon: 'sparkle',  tok: '1.2M', freq: '8×/wk',  model: '2.5 Pro' },
  { name: 'Copilot', icon: 'terminal', tok: '318k', freq: '23×/wk', model: 'GPT-4o' },
];

function PopCap({ children, right }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', margin: '0 4px 8px' }}>
      <span className="caption">{children}</span>
      {right && <span className="caption" style={{ letterSpacing: '0.02em' }}>{right}</span>}
    </div>
  );
}

function HeroCard({ threshold }) {
  return (
    <div className="cb-card" style={{ borderRadius: 'var(--r-hero)', padding: 16, boxShadow: 'var(--shadow-hero)',
      background: 'var(--card-solid)', position: 'relative', overflow: 'hidden' }}>
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 2.5, background: 'var(--accent)' }} />
      {/* top row */}
      <div className="cb-row" style={{ justifyContent: 'space-between', marginBottom: 14 }}>
        <div className="cb-row" style={{ gap: 8, minWidth: 0 }}>
          <span className="cb-dot live" />
          <span className="title" style={{ fontSize: 16, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>claude-context-bar</span>
        </div>
        <Glyph name="sparkle" size={28} icon={16} />
      </div>
      {/* hero metric */}
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', marginBottom: 10 }}>
        <div>
          <div className="caption" style={{ marginBottom: 2 }}>Context window</div>
          <div className="num" style={{ fontSize: 44, fontWeight: 600, color: 'var(--text)', lineHeight: 0.95 }}>78<span style={{ fontSize: 24, color: 'var(--text-2)' }}>%</span></div>
        </div>
        <div style={{ textAlign: 'right', paddingBottom: 4 }}>
          <div className="num" style={{ fontSize: 13, fontWeight: 600, color: 'var(--text)' }}>156.2k</div>
          <div className="body" style={{ fontSize: 10.5, color: 'var(--text-3)' }}>/ 200k tokens</div>
        </div>
      </div>
      <Bar pct={78} threshold={threshold} thick />
      <div className="cb-row" style={{ justifyContent: 'space-between', marginTop: 12 }}>
        <span className="body" style={{ fontSize: 11.5 }}>Claude · Sonnet 4.5</span>
        <span className="body" style={{ fontSize: 11.5 }}><span className="num">2m</span> ago · <span className="num">45m</span> running</span>
      </div>
    </div>
  );
}

function SessionsCard() {
  return (
    <div>
      <PopCap right={SESSIONS.length + ' active'}>Parallel sessions</PopCap>
      <div className="cb-card" style={{ padding: '4px 14px' }}>
        {SESSIONS.map((s, i) => (
          <div key={i} className="cb-row" style={{ gap: 10, padding: '9px 0', borderTop: i ? '0.5px solid var(--hair)' : 'none' }}>
            <span className="cb-dot idle" style={{ width: 6, height: 6 }} />
            <div style={{ minWidth: 0, flex: '0 0 116px' }}>
              <div className="body" style={{ fontSize: 12, color: 'var(--text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{s.proj}</div>
              <div className="body" style={{ fontSize: 10, color: 'var(--text-3)' }}>{s.model}</div>
            </div>
            <div style={{ flex: 1 }}><Bar pct={s.pct} thin /></div>
            <span className="num" style={{ fontSize: 11.5, color: 'var(--text-2)', width: 30, textAlign: 'right' }}>{s.pct}%</span>
            <span className="num" style={{ fontSize: 10.5, color: 'var(--text-3)', width: 36, textAlign: 'right' }}>{s.time}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function LimitRow({ label, pct, reset, threshold }) {
  return (
    <div style={{ padding: '11px 0' }}>
      <div className="cb-row" style={{ justifyContent: 'space-between', marginBottom: 7 }}>
        <span className="body" style={{ fontSize: 12, color: 'var(--text)' }}>{label}</span>
        <span className="cb-row" style={{ gap: 8 }}>
          {reset && <span className="body" style={{ fontSize: 10.5, color: 'var(--text-3)' }}><Icon name="refresh" size={10} style={{ display: 'inline', verticalAlign: '-1px' }} /> {reset}</span>}
          <span className="num" style={{ fontSize: 12, fontWeight: 600, color: 'var(--text)' }}>{pct}%</span>
        </span>
      </div>
      <Bar pct={pct} threshold={threshold} />
    </div>
  );
}

function LimitsCard({ threshold }) {
  return (
    <div>
      <PopCap>Usage limits</PopCap>
      <div className="cb-card" style={{ padding: '2px 14px' }}>
        <LimitRow label="5-hour rolling" pct={64} reset="1h47m" threshold={threshold} />
        <div className="cb-div" />
        <LimitRow label="7-day rolling" pct={41} threshold={threshold} />
        <div className="cb-div" />
        <div className="cb-row" style={{ justifyContent: 'space-between', padding: '11px 0' }}>
          <span className="body" style={{ fontSize: 12, color: 'var(--text)' }}>Session total</span>
          <span className="num" style={{ fontSize: 13, fontWeight: 600, color: 'var(--text)' }}>312.6k <span style={{ color: 'var(--text-3)', fontWeight: 400, fontSize: 11 }}>tok</span></span>
        </div>
      </div>
    </div>
  );
}

function ToolsCard() {
  return (
    <div>
      <PopCap>Other tools</PopCap>
      <div className="cb-card" style={{ padding: '4px 14px' }}>
        {TOOLS.map((t, i) => (
          <div key={i} className="cb-row" style={{ gap: 10, padding: '9px 0', borderTop: i ? '0.5px solid var(--hair)' : 'none' }}>
            <Glyph name={t.icon} size={22} icon={13} color="var(--text-2)" bg="var(--quiet-2)" />
            <span className="body" style={{ fontSize: 12, color: 'var(--text)', flex: 1 }}>{t.name}</span>
            <span className="num" style={{ fontSize: 11, color: 'var(--text-2)' }}>{t.tok}</span>
            <span className="body" style={{ fontSize: 10.5, color: 'var(--text-3)', width: 50, textAlign: 'right' }}>{t.freq}</span>
            <span className="body" style={{ fontSize: 10.5, color: 'var(--text-3)', width: 52, textAlign: 'right' }}>{t.model}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function Footer() {
  const btns = [['share', 'Share'], ['gear', 'Settings'], ['refresh', 'Refresh']];
  return (
    <div className="cb-row" style={{ justifyContent: 'space-between', padding: '4px 4px 0' }}>
      <div className="cb-row" style={{ gap: 2 }}>
        {btns.map(([ic, t]) => <button key={ic} className="cb-footbtn" title={t}><Icon name={ic} size={16} /></button>)}
      </div>
      <button className="cb-footbtn" title="Quit"><Icon name="power" size={16} /></button>
    </div>
  );
}

function PopBody({ variant, threshold, showSessions, showTools }) {
  if (variant === 'loading') {
    return (
      <div style={{ padding: '52px 16px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16 }}>
        <div className="cb-spin" style={{ width: 26, height: 26, borderRadius: 99, border: '2.5px solid var(--track)', borderTopColor: 'var(--accent)' }} />
        <div className="body" style={{ fontSize: 12.5, color: 'var(--text-2)' }}>Gathering session data…</div>
        <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 10, marginTop: 6 }}>
          {[0, 1, 2].map((i) => (
            <div key={i} className="cb-card" style={{ height: i === 0 ? 64 : 40, opacity: 0.5 - i * 0.12 }} />
          ))}
        </div>
      </div>
    );
  }
  if (variant === 'empty') {
    return (
      <div style={{ padding: '56px 24px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14, textAlign: 'center' }}>
        <Glyph name="stack" size={48} icon={26} color="var(--text-3)" bg="var(--quiet-2)" />
        <div>
          <div className="title" style={{ fontSize: 15, marginBottom: 4 }}>No agent data yet</div>
          <div className="body" style={{ fontSize: 12, maxWidth: 230 }}>Start a Claude Code or Codex session and ContextBar will read it from your local transcripts.</div>
        </div>
        <button className="cb-chip" style={{ marginTop: 4, padding: '6px 12px', color: 'var(--accent)', borderColor: 'var(--accent-soft)', background: 'var(--accent-softer)' }}>
          <Icon name="info" size={12} /> How it works
        </button>
      </div>
    );
  }
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <HeroCard threshold={threshold} />
      {showSessions && <SessionsCard />}
      <LimitsCard threshold={threshold} />
      {showTools && <ToolsCard />}
    </div>
  );
}

function Popover({ theme = 'light', variant = 'default', threshold = 75, showSessions = true, showTools = true, accentL, accentD }) {
  const dark = theme === 'dark';
  const accentStyle = {};
  if (accentL) accentStyle['--accent-l'] = accentL;
  if (accentD) accentStyle['--accent-d'] = accentD;
  const pct = variant === 'loading' || variant === 'empty' ? null : 78;

  return (
    <div className={'cb ' + (dark ? 'cb-wall-dark' : 'cb-wall-light')} style={{ overflow: 'hidden', ...accentStyle }}>
      {/* faux menubar */}
      <div className={'cb-menubar ' + (dark ? 'cb-menubar-dark' : 'cb-menubar-light')} style={{ justifyContent: 'flex-end' }}>
        <span style={{ marginRight: 'auto', fontWeight: 600, opacity: .8 }}> </span>
        <span className="num" style={{ fontSize: 11.5, opacity: .55 }}>100%</span>
        <span style={{ fontSize: 12, opacity: .55 }}>Wed 14:32</span>
        <span className="cb-row" style={{ gap: 6, padding: '2px 8px', borderRadius: 6,
          background: dark ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.07)' }}>
          <span className="cb-dot" style={{ width: 6, height: 6, background: dark ? 'var(--accent-d)' : 'var(--accent-l)' }} />
          <span className="num" style={{ fontSize: 11.5, fontWeight: 600 }}>{pct != null ? pct + '%' : '—'}</span>
        </span>
      </div>

      {/* pointer + popover, right aligned under the menubar item */}
      <div style={{ position: 'absolute', top: 24, right: 8, width: 360 }}>
        <div className="cb-pointer" style={{ marginLeft: 'auto', marginRight: 18 }}>
          <i style={{ background: dark ? 'rgba(34,33,31,0.80)' : 'rgba(244,243,241,0.86)',
            boxShadow: dark ? '0 0 0 0.5px rgba(255,255,255,0.10)' : '0 0 0 0.5px rgba(0,0,0,0.10)' }} />
        </div>
        <div className={'cb cb-popover ' + (dark ? 'cb-dark' : 'cb-light')} style={{ padding: 16 }}>
          <PopBody variant={variant} threshold={threshold} showSessions={showSessions} showTools={showTools} />
          <div className="cb-div" style={{ margin: '14px -16px 12px' }} />
          <Footer />
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Popover });
