/* cb-ui.jsx — shared primitives for ContextBar screens.
   Exports to window: Icon, Bar, Seg, Glyph, Heat, fmt. */

// SF-Symbols-flavored line icons. 24×24 viewBox, stroke = currentColor.
const CB_ICONS = {
  share:      'M12 3v12M12 3L8.5 6.5M12 3l3.5 3.5M5 12v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6',
  gear:       'M12 9.2a2.8 2.8 0 1 0 0 5.6 2.8 2.8 0 0 0 0-5.6Z;M19.2 12c0-.5-.05-1-.13-1.45l1.7-1.32-1.8-3.1-2 .8a6.9 6.9 0 0 0-2.5-1.45L14.1 3h-3.6l-.37 2.48a6.9 6.9 0 0 0-2.5 1.45l-2-.8-1.8 3.1 1.7 1.32a7.2 7.2 0 0 0 0 2.9l-1.7 1.32 1.8 3.1 2-.8a6.9 6.9 0 0 0 2.5 1.45L10.5 21h3.6l.37-2.48a6.9 6.9 0 0 0 2.5-1.45l2 .8 1.8-3.1-1.7-1.32c.08-.46.13-.95.13-1.45Z',
  refresh:    'M20 11a8 8 0 1 0-.5 3.5;M20 6v5h-5',
  power:      'M12 4v8;M7.5 6.6a7 7 0 1 0 9 0',
  flame:      'M12 3c.5 3-2.5 4-2.5 7a2.5 2.5 0 0 0 5 0c0-1-.5-1.8-.5-1.8.8.4 2.5 1.8 2.5 4.3a4.5 4.5 0 1 1-9 0C9.5 8 12 6.5 12 3Z',
  clock:      'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z;M12 7.5V12l3 2',
  calendar:   'M4.5 8.5h15M7 3.5v3M17 3.5v3;M5.5 5.5h13a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1h-13a1 1 0 0 1-1-1v-12a1 1 0 0 1 1-1Z',
  bolt:       'M13 3 5 13h5l-1 8 8-10h-5l1-8Z',
  sparkle:    'M12 3l1.6 5.4L19 10l-5.4 1.6L12 17l-1.6-5.4L5 10l5.4-1.6L12 3Z',
  terminal:   'M5 5.5h14a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-11a1 1 0 0 1 1-1Z;M7.5 9.5l3 2.5-3 2.5M13 15h4',
  stack:      'M12 3.5 3.5 8 12 12.5 20.5 8 12 3.5Z;M3.5 12 12 16.5 20.5 12;M3.5 16 12 20.5 20.5 16',
  gauge:      'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z;M12 12l4-3',
  people:     'M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z;M3.5 19a5.5 5.5 0 0 1 11 0;M16 5.2a3 3 0 0 1 0 5.6;M16.5 13.4a5.5 5.5 0 0 1 4 5.6',
  chart:      'M4 20h16;M7 20v-6;M12 20V8;M17 20v-9',
  info:       'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z;M12 11v5M12 7.6h.01',
  search:     'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14Z;M20 20l-4-4',
  chevR:      'M9 5l7 7-7 7',
  chevD:      'M5 9l7 7 7-7',
  dollar:     'M12 3v18;M16 7.5C16 5.6 14.2 4.5 12 4.5S8 5.6 8 7.5s1.8 2.6 4 3 4 1.5 4 3.5-1.8 3-4 3-4-1.1-4-3',
  trend:      'M4 15l5-5 4 3 7-8;M16 5h4v4',
  globe:      'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z;M3.5 12h17;M12 3a14 14 0 0 1 0 18;M12 3a14 14 0 0 0 0 18',
  bell:       'M6.5 17V11a5.5 5.5 0 0 1 11 0v6l1.5 2H5l1.5-2Z;M10 19a2 2 0 0 0 4 0',
  paint:      'M12 3a9 9 0 0 0 0 18c1.2 0 1.8-1 1.8-2 0-1.4-1.2-1.6-1.2-2.6 0-.7.6-1.2 1.5-1.2H17a4 4 0 0 0 4-4c0-4.4-4-8.2-9-8.2Z;M7.5 11.5h.01M10.5 8h.01M14 8h.01',
  sliders:    'M5 8h9;M17 8h2;M5 16h2;M10 16h9;M14 6v4;M7 14v4',
  sun:        'M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z;M12 2.5v2M12 19.5v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M2.5 12h2M19.5 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4',
  check:      'M5 12.5l4.5 4.5L19 7',
  plus:       'M12 5v14M5 12h14',
};

function Icon({ name, size = 16, sw = 1.6, fill = false, style }) {
  const d = CB_ICONS[name] || '';
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round"
      style={{ flex: '0 0 auto', display: 'block', ...style }}>
      {d.split(';').map((p, i) => (
        <path key={i} d={p} fill={fill ? 'currentColor' : 'none'} stroke={fill ? 'none' : 'currentColor'} />
      ))}
    </svg>
  );
}

// progress bar. pct 0..100. threshold drives the "hot" class.
function Bar({ pct, threshold = 75, thin, thick, tick, accent }) {
  const hot = pct >= threshold;
  const cls = 'cb-bar' + (thin ? ' thin' : '') + (thick ? ' thick' : '') + (hot ? ' hot' : '');
  return (
    <div className={cls}>
      <i style={{ width: Math.min(100, pct) + '%', background: accent }} />
      {tick != null && <span className="tick" style={{ left: tick + '%' }} />}
    </div>
  );
}

// glyph chip with an icon inside
function Glyph({ name, size = 26, icon = 15, color, bg, style }) {
  return (
    <span className="cb-glyph" style={{ width: size, height: size, color, background: bg, ...style }}>
      <Icon name={name} size={icon} />
    </span>
  );
}

// GitHub-style year heatmap. weeks × 7. data: array of 0..4 intensity by day.
function Heat({ weeks = 52, data, accentVar = 'var(--accent)' }) {
  const cells = [];
  const total = weeks * 7;
  for (let i = 0; i < total; i++) {
    const lvl = data ? data[i] : 0;
    let bg = 'var(--quiet-2)';
    if (lvl === 1) bg = `color-mix(in oklab, ${accentVar} 28%, transparent)`;
    else if (lvl === 2) bg = `color-mix(in oklab, ${accentVar} 52%, transparent)`;
    else if (lvl === 3) bg = `color-mix(in oklab, ${accentVar} 76%, transparent)`;
    else if (lvl >= 4) bg = accentVar;
    cells.push(<b key={i} style={{ background: bg }} />);
  }
  return <div className="cb-heat">{cells}</div>;
}

// deterministic pseudo-random heatmap data so it looks organic & stable
function heatData(weeks = 52, seed = 7) {
  const out = []; let s = seed;
  const rnd = () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; };
  for (let w = 0; w < weeks; w++) {
    const wk = 0.35 + 0.65 * Math.min(1, w / weeks + 0.15); // ramps up over the year
    for (let d = 0; d < 7; d++) {
      const weekend = d === 0 || d === 6 ? 0.45 : 1;
      const r = rnd() * wk * weekend;
      let lvl = 0;
      if (r > 0.78) lvl = 4; else if (r > 0.58) lvl = 3; else if (r > 0.36) lvl = 2; else if (r > 0.16) lvl = 1;
      out.push(lvl);
    }
  }
  return out;
}

Object.assign(window, { Icon, Bar, Glyph, Heat, heatData });
