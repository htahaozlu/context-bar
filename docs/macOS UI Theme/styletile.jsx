/* styletile.jsx — Foundations specimen. Exports window.StyleTile(props{theme}) */

function StyleTile({ theme }) {
  const dark = theme === 'dark';
  const pad = 28;
  const Cap = ({ children }) => <div className="caption" style={{ marginBottom: 12 }}>{children}</div>;
  const Block = ({ children, style }) => <section style={{ marginBottom: 26, ...style }}>{children}</section>;

  return (
    <div className={'cb ' + (dark ? 'cb-dark' : 'cb-light')}
      style={{ background: 'var(--window)', padding: pad, overflow: 'hidden' }}>

      {/* header */}
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 22 }}>
        <div>
          <div style={{ fontSize: 20, fontWeight: 650, color: 'var(--text)', letterSpacing: '-0.02em' }}>ContextBar — Foundations</div>
          <div className="body" style={{ marginTop: 3 }}>One signature accent over a neutral gray scale · numbers always mono &amp; tabular</div>
        </div>
        <div className="cb-chip"><span className="cb-dot live" />{dark ? 'Dark' : 'Light'}</div>
      </div>

      {/* accent */}
      <Block>
        <Cap>Signature accent — clay</Cap>
        <div style={{ display: 'flex', gap: 14, alignItems: 'stretch' }}>
          <div style={{ flex: '0 0 168px', height: 96, borderRadius: 'var(--r-hero)', background: 'var(--accent)',
            display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', padding: 14, color: '#fff' }}>
            <div style={{ fontSize: 12, fontWeight: 600, opacity: .85 }}>accent</div>
            <div className="num" style={{ fontSize: 15, fontWeight: 600 }}>{dark ? '#E68A66' : '#C2553A'}</div>
          </div>
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 8, justifyContent: 'center' }}>
            <div style={{ display: 'flex', gap: 6, height: 26 }}>
              {[8, 16, 28, 52, 76, 100].map((a, i) => (
                <div key={i} style={{ flex: 1, borderRadius: 6, background: `color-mix(in oklab, var(--accent) ${a}%, transparent)` }} />
              ))}
            </div>
            <div className="body" style={{ fontSize: 11 }}>Intensity ramp drives bars, the year heatmap, and over-threshold highlights — the only chromatic note in the UI.</div>
          </div>
        </div>
      </Block>

      {/* neutral scale */}
      <Block>
        <Cap>Neutral scale</Cap>
        <div style={{ display: 'flex', gap: 6 }}>
          {(dark
            ? ['#0E0F12', '#1C1B19', '#2B2A28', 'rgba(245,245,245,.40)', 'rgba(245,245,245,.58)', '#F5F5F5']
            : ['#ECEAE6', '#ffffff', 'rgba(0,0,0,.09)', 'rgba(20,20,20,.40)', 'rgba(20,20,20,.56)', '#141414']
          ).map((c, i) => (
            <div key={i} style={{ flex: 1, height: 40, borderRadius: 8, background: c, border: '0.5px solid var(--hair)' }} />
          ))}
        </div>
      </Block>

      {/* type */}
      <Block>
        <Cap>Type · SF Pro for UI · JetBrains Mono for numbers</Cap>
        <div style={{ display: 'flex', gap: 36, alignItems: 'flex-end', flexWrap: 'wrap' }}>
          <div>
            <div className="num" style={{ fontSize: 40, fontWeight: 600, color: 'var(--text)', lineHeight: 1 }}>71%</div>
            <div className="body" style={{ fontSize: 10.5, marginTop: 4 }}>Display / hero · 40 · 600</div>
          </div>
          <div>
            <div className="num" style={{ fontSize: 25, fontWeight: 600, color: 'var(--text)', lineHeight: 1 }}>$2,847</div>
            <div className="body" style={{ fontSize: 10.5, marginTop: 4 }}>Metric · 25 · 600</div>
          </div>
          <div>
            <div className="title" style={{ fontSize: 15 }}>Title · semibold</div>
            <div className="body" style={{ fontSize: 10.5, marginTop: 4 }}>Title · 15 · 600</div>
          </div>
          <div>
            <div className="body" style={{ fontSize: 12, color: 'var(--text)' }}>Body copy · regular</div>
            <div className="body" style={{ fontSize: 10.5, marginTop: 4 }}>Body · 12 · 400</div>
          </div>
          <div>
            <div className="caption">Caption label</div>
            <div className="body" style={{ fontSize: 10.5, marginTop: 4 }}>Caption · 10 · 600 · 0.07em</div>
          </div>
        </div>
      </Block>

      {/* radius + spacing */}
      <Block style={{ display: 'flex', gap: 40 }}>
        <div style={{ flex: 1 }}>
          <Cap>Radius</Cap>
          <div style={{ display: 'flex', gap: 12, alignItems: 'flex-end' }}>
            {[['chip', 8], ['card', 12], ['hero', 16], ['pop', 20]].map(([n, r]) => (
              <div key={n} style={{ textAlign: 'center' }}>
                <div style={{ width: 52, height: 52, borderTopLeftRadius: r, background: 'var(--quiet-2)', border: '0.5px solid var(--hair-strong)' }} />
                <div className="num" style={{ fontSize: 10, color: 'var(--text-3)', marginTop: 5 }}>{r}</div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ flex: 1.2 }}>
          <Cap>Spacing · 4 8 12 16 20 24 32</Cap>
          <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end' }}>
            {[4, 8, 12, 16, 20, 24, 32].map((s) => (
              <div key={s} style={{ textAlign: 'center' }}>
                <div style={{ width: s, height: s, background: 'var(--accent)', borderRadius: 2, marginInline: 'auto' }} />
                <div className="num" style={{ fontSize: 9.5, color: 'var(--text-3)', marginTop: 6 }}>{s}</div>
              </div>
            ))}
          </div>
        </div>
      </Block>

      {/* components */}
      <Block style={{ marginBottom: 0 }}>
        <Cap>Components</Cap>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
          <div className="cb-card" style={{ padding: 14, display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span className="body" style={{ fontSize: 11, color: 'var(--text-2)' }}>Context</span>
              <span className="num" style={{ fontSize: 12, color: 'var(--text)', fontWeight: 600 }}>71%</span>
            </div>
            <Bar pct={71} />
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span className="body" style={{ fontSize: 11, color: 'var(--text-2)' }}>Over threshold</span>
              <span className="num" style={{ fontSize: 12, color: 'var(--accent)', fontWeight: 600 }}>88%</span>
            </div>
            <Bar pct={88} />
          </div>
          <div className="cb-card" style={{ padding: 14, display: 'flex', flexDirection: 'column', gap: 12, alignItems: 'flex-start' }}>
            <div className="cb-seg-ctrl">
              <button className="on">Claude</button>
              <button>Codex</button>
            </div>
            <div style={{ display: 'flex', gap: 8 }}>
              <span className="cb-chip"><span className="cb-dot live" />live</span>
              <span className="cb-chip"><Icon name="clock" size={11} />45m</span>
            </div>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <Glyph name="sparkle" />
              <Glyph name="terminal" />
              <Glyph name="flame" />
            </div>
          </div>
        </div>
        <div className="cb-insight" style={{ marginTop: 14 }}>
          <Glyph name="people" size={30} icon={17} />
          <div>
            <div className="num" style={{ fontSize: 17, fontWeight: 650, color: 'var(--text)' }}>24%</div>
            <div className="body" style={{ fontSize: 11.5 }}>of fresh tokens went to sub-agents — insight cards turn a metric into a sentence.</div>
          </div>
        </div>
      </Block>
    </div>
  );
}

Object.assign(window, { StyleTile });
