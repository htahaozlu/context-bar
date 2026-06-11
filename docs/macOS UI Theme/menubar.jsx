/* menubar.jsx — menubar title states, unified. Exports window.MenubarStates({theme}) */

// tiny radial gauge that doubles as the status dot: arc fills with context %,
// color ramps with urgency — one glyph carries both signals.
function Gauge({ pct, color, size = 13 }) {
  const r = (size - 3) / 2, c = 2 * Math.PI * r, cx = size / 2;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ display: 'block', flex: '0 0 auto' }}>
      <circle cx={cx} cy={cx} r={r} fill="none" stroke="currentColor" strokeWidth="2" opacity="0.22" />
      <circle cx={cx} cy={cx} r={r} fill="none" stroke={color} strokeWidth="2" strokeLinecap="round"
        strokeDasharray={`${(c * pct) / 100} ${c}`} transform={`rotate(-90 ${cx} ${cx})`} />
    </svg>
  );
}

function BarItem({ dark, children, style }) {
  return (
    <div className={'cb-menubar ' + (dark ? 'cb-menubar-dark' : 'cb-menubar-light')}
      style={{ borderRadius: 8, height: 26, gap: 0, justifyContent: 'flex-end', boxShadow: dark ? '0 1px 2px rgba(0,0,0,.4)' : '0 1px 2px rgba(0,0,0,.12)', ...style }}>
      {children}
    </div>
  );
}

function Title({ pct, color, label = 'my-repo', extra, idle }) {
  return (
    <span className="cb-row" style={{ gap: 6, padding: '2px 9px', borderRadius: 6, color: 'currentColor', whiteSpace: 'nowrap' }}>
      {idle ? <span style={{ width: 11, height: 11, borderRadius: 99, border: '1.5px solid currentColor', opacity: 0.5 }} />
            : <span style={{ color }}><Gauge pct={pct} color={color} /></span>}
      <span style={{ fontSize: 12, fontWeight: 550 }}>Claude</span>
      <span style={{ opacity: 0.4 }}>·</span>
      <span style={{ fontSize: 12, opacity: 0.85 }}>{label}</span>
      {!idle && <><span style={{ opacity: 0.4 }}>·</span><span className="num" style={{ fontSize: 12, fontWeight: 600 }}>{pct}%</span></>}
      {extra && <span className="num" style={{ fontSize: 10.5, fontWeight: 600, opacity: 0.55, marginLeft: 2 }}>{extra}</span>}
      {idle && <span style={{ fontSize: 12, opacity: 0.55 }}>idle</span>}
    </span>
  );
}

function StateRow({ dark, title, desc, children }) {
  return (
    <div className="cb-row" style={{ gap: 16, alignItems: 'center' }}>
      <div style={{ flex: '0 0 236px' }}>{children}</div>
      <div style={{ minWidth: 0 }}>
        <div className="title" style={{ fontSize: 12.5 }}>{title}</div>
        <div className="body" style={{ fontSize: 11 }}>{desc}</div>
      </div>
    </div>
  );
}

function MenubarStates({ theme = 'light' }) {
  const dark = theme === 'dark';
  const amber = dark ? '#F2B33D' : '#D98A0B';
  const red = dark ? '#FF6B5E' : '#E0452F';
  const acc = 'var(--accent)';
  return (
    <div className={'cb ' + (dark ? 'cb-dark cb-wall-dark' : 'cb-light cb-wall-light')} style={{ padding: 24, overflow: 'hidden' }}>
      <div style={{ marginBottom: 18 }}>
        <div style={{ fontSize: 17, fontWeight: 650, color: 'var(--text)', letterSpacing: '-0.02em' }}>Menubar title</div>
        <div className="body" style={{ fontSize: 11.5 }}>One gauge-dot carries both context fill and urgency — no more competing badges.</div>
      </div>

      {/* before */}
      <div style={{ marginBottom: 20 }}>
        <div className="caption" style={{ marginBottom: 8 }}>Before · three signals fighting</div>
        <BarItem dark={dark}>
          <span className="cb-row" style={{ gap: 5, padding: '2px 9px', borderRadius: 6 }}>
            <span style={{ width: 7, height: 7, borderRadius: 99, background: red }} />
            <span style={{ width: 7, height: 7, borderRadius: 99, background: amber }} />
            <span className="cb-row" style={{ gap: 3 }}><Icon name="flame" size={12} style={{ color: red }} /></span>
            <span style={{ fontSize: 12, fontWeight: 550 }}>Claude</span>
            <span style={{ opacity: 0.4 }}>·</span>
            <span style={{ fontSize: 12, opacity: 0.85 }}>my-repo</span>
            <span style={{ opacity: 0.4 }}>·</span>
            <span className="num" style={{ fontSize: 12, fontWeight: 600 }}>88%</span>
          </span>
        </BarItem>
      </div>

      <div className="caption" style={{ marginBottom: 10 }}>After · one unified state</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <StateRow dark={dark} title="Healthy" desc="Arc shows context fill. Calm accent.">
          <BarItem dark={dark}><Title pct={42} color={acc} /></BarItem>
        </StateRow>
        <StateRow dark={dark} title="Context filling" desc="Arc nears full at the same accent — no new color needed.">
          <BarItem dark={dark}><Title pct={88} color={acc} /></BarItem>
        </StateRow>
        <StateRow dark={dark} title="Needs attention" desc="Limit or budget pace high → the one dot warms to amber.">
          <BarItem dark={dark}><Title pct={64} color={amber} /></BarItem>
        </StateRow>
        <StateRow dark={dark} title="At the limit" desc="Most urgent signal only ever shows as red. Click to see which.">
          <BarItem dark={dark}><Title pct={97} color={red} /></BarItem>
        </StateRow>
        <StateRow dark={dark} title="Multiple sessions" desc="Lead agent + a quiet count, not five badges.">
          <BarItem dark={dark}><Title pct={42} color={acc} extra="+2" /></BarItem>
        </StateRow>
        <StateRow dark={dark} title="Idle" desc="Hollow ring, no number — nothing running.">
          <BarItem dark={dark}><Title idle /></BarItem>
        </StateRow>
      </div>

      {/* key */}
      <div className="cb-row" style={{ gap: 16, marginTop: 20, paddingTop: 16, borderTop: '0.5px solid var(--hair)' }}>
        <span className="caption" style={{ margin: 0 }}>Urgency ramp</span>
        {[['Calm', acc], ['Attention', amber], ['Limit', red]].map(([l, c]) => (
          <span key={l} className="cb-row" style={{ gap: 6 }}>
            <span style={{ color: c }}><Gauge pct={70} color={c} size={12} /></span>
            <span className="body" style={{ fontSize: 11 }}>{l}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { MenubarStates });
