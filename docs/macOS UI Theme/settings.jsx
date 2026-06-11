/* settings.jsx — General settings, 3 grouped sections. Exports window.SettingsWindow({theme}) */

function Switch({ on }) {
  return (
    <span style={{ width: 34, height: 20, borderRadius: 99, background: on ? 'var(--accent)' : 'var(--track)',
      position: 'relative', flex: '0 0 auto', transition: 'background .15s' }}>
      <span style={{ position: 'absolute', top: 2, left: on ? 16 : 2, width: 16, height: 16, borderRadius: 99,
        background: '#fff', boxShadow: '0 1px 2px rgba(0,0,0,.3)' }} />
    </span>
  );
}

function Popup({ value }) {
  return (
    <span className="cb-row" style={{ gap: 8, padding: '4px 8px 4px 10px', borderRadius: 7, background: 'var(--card-solid)',
      border: '0.5px solid var(--hair-strong)', boxShadow: '0 0.5px 1px rgba(0,0,0,.1)' }}>
      <span style={{ fontSize: 12, color: 'var(--text)', fontWeight: 500 }}>{value}</span>
      <svg width="9" height="13" viewBox="0 0 9 13" fill="none" stroke="var(--text-3)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M2 5l2.5-2.5L7 5M2 8l2.5 2.5L7 8" />
      </svg>
    </span>
  );
}

function SRow({ label, desc, control, last }) {
  return (
    <div className="cb-row" style={{ gap: 16, padding: '8px 14px', borderTop: last ? 'none' : '0.5px solid var(--hair)', minHeight: 38 }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 12.5, color: 'var(--text)', fontWeight: 500 }}>{label}</div>
        {desc && <div className="body" style={{ fontSize: 10.5, color: 'var(--text-3)', marginTop: 1 }}>{desc}</div>}
      </div>
      <div style={{ flex: '0 0 auto' }}>{control}</div>
    </div>
  );
}

function Group({ icon, title, children }) {
  return (
    <div>
      <div className="cb-row" style={{ gap: 7, margin: '0 4px 8px' }}>
        <Icon name={icon} size={13} style={{ color: 'var(--text-2)' }} />
        <span className="caption" style={{ margin: 0 }}>{title}</span>
      </div>
      <div className="cb-card" style={{ overflow: 'hidden' }}>{children}</div>
    </div>
  );
}

function SettingsWindow({ theme = 'light' }) {
  return (
    <WinChrome theme={theme} tab="Settings">
      <div className="cb-winbody" style={{ display: 'flex', justifyContent: 'center', overflow: 'hidden' }}>
        <div style={{ width: 580, display: 'flex', flexDirection: 'column', gap: 16 }}>

          <Group icon="paint" title="Appearance">
            <SRow last label="Theme" control={<SegCtrl options={['System', 'Light', 'Dark']} value="System" />} />
            <SRow label="Language" control={<Popup value="English" />} />
            <SRow label="Menu-bar separator" desc="Character between title fields" control={<Popup value="·  dot" />} />
            <SRow label="Title fields" desc="Project · Model · Context %" control={<Popup value="3 shown" />} />
            <SRow label="Live preview" desc="Show this menu-bar title sample while editing" control={<Switch on />} />
          </Group>

          <Group icon="bell" title="Alerts">
            <SRow last label="Context bar marks" desc="Tick the bar at your warning threshold" control={<Popup value="75%" />} />
            <SRow label="Background sessions" desc="Notify when an idle session changes state" control={<Switch on />} />
            <SRow label="Provider status" desc="Surface Anthropic / OpenAI incidents" control={<Switch /> } />
            <SRow label="Budget alerts" desc="Warn as API-equivalent value passes a cap" control={<Popup value="$150/mo" />} />
          </Group>

          <Group icon="sliders" title="Behavior">
            <SRow last label="Limit reset style" desc="How rolling-window resets are shown" control={<SegCtrl options={['Countdown', 'Clock']} value="Countdown" />} />
            <SRow label="Delight" desc="Celebrate streaks and milestones" control={<Switch on />} />
          </Group>

          <div className="body" style={{ fontSize: 10.5, textAlign: 'center', color: 'var(--text-3)' }}>
            ContextBar 2.0 · all data stays on this Mac · no account, no server
          </div>
        </div>
      </div>
    </WinChrome>
  );
}

Object.assign(window, { SettingsWindow });
