/* app.jsx — assembles all ContextBar screens on a design canvas + Tweaks. */

const MONO_STACKS = {
  'JetBrains Mono': "'JetBrains Mono', ui-monospace, monospace",
  'SF Mono': "ui-monospace, 'SF Mono', Menlo, monospace",
  'IBM Plex Mono': "'IBM Plex Mono', ui-monospace, monospace",
};

const ACCENTS = {
  Clay:   ['#C2553A', '#E68A66'],
  Indigo: ['#4F6BED', '#8AA0FF'],
  Teal:   ['#1F8A5B', '#3FCB8E'],
  Violet: ['#6E56CF', '#9B87F5'],
};

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accent": ["#C2553A", "#E68A66"],
  "mono": "JetBrains Mono",
  "threshold": 75,
  "showSessions": true,
  "showTools": true
}/*EDITMODE-END*/;

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);

  React.useEffect(() => {
    const r = document.documentElement.style;
    if (Array.isArray(t.accent)) { r.setProperty('--accent-l', t.accent[0]); r.setProperty('--accent-d', t.accent[1]); }
    r.setProperty('--mono', MONO_STACKS[t.mono] || MONO_STACKS['JetBrains Mono']);
  }, [t.accent, t.mono]);

  const pop = { threshold: t.threshold, showSessions: t.showSessions, showTools: t.showTools };

  return (
    <React.Fragment>
      <DesignCanvas>

        <DCSection id="foundations" title="Foundations" subtitle="Signature accent · type · spacing · components">
          <DCArtboard id="tile-l" label="Style tile · Light" width={760} height={902}><StyleTile theme="light" /></DCArtboard>
          <DCArtboard id="tile-d" label="Style tile · Dark" width={760} height={902}><StyleTile theme="dark" /></DCArtboard>
          <DCPostIt top={-4} left={1640} rotate={2} width={210}>One clay accent does all the chromatic work — bars, heatmap, over-threshold highlight. Everything else is neutral gray.</DCPostIt>
        </DCSection>

        <DCSection id="popover" title="1 · Popover" subtitle="360pt · the priority screen — hero context %, then supporting cards">
          <DCArtboard id="pop-l" label="Default · Light" width={384} height={824}><Popover theme="light" {...pop} /></DCArtboard>
          <DCArtboard id="pop-d" label="Default · Dark" width={384} height={824}><Popover theme="dark" {...pop} /></DCArtboard>
          <DCArtboard id="pop-load" label="Loading · Light" width={384} height={490}><Popover theme="light" variant="loading" {...pop} /></DCArtboard>
          <DCArtboard id="pop-empty" label="Empty · Dark" width={384} height={490}><Popover theme="dark" variant="empty" {...pop} /></DCArtboard>
          <DCPostIt top={-4} left={1620} rotate={-2} width={208}>Hero card owns the screen: 44px context % is the only big number. Sessions / limits / tools step down in weight.</DCPostIt>
        </DCSection>

        <DCSection id="popover-accent" title="Popover · accent directions" subtitle="Explore a few signature colors (hero + limits only) — change live in Tweaks">
          <DCArtboard id="acc-clay" label="Clay (recommended)" width={384} height={500}><Popover theme="light" showSessions={false} showTools={false} threshold={t.threshold} accentL="#C2553A" accentD="#E68A66" /></DCArtboard>
          <DCArtboard id="acc-indigo" label="Indigo" width={384} height={500}><Popover theme="light" showSessions={false} showTools={false} threshold={t.threshold} accentL="#4F6BED" accentD="#8AA0FF" /></DCArtboard>
          <DCArtboard id="acc-teal" label="Teal" width={384} height={500}><Popover theme="light" showSessions={false} showTools={false} threshold={t.threshold} accentL="#1F8A5B" accentD="#3FCB8E" /></DCArtboard>
        </DCSection>

        <DCSection id="stats" title="2 · Stats" subtitle="The densest screen — 6 metrics up front, the rest behind ‘more’. Heatmap & insights are the stars.">
          <DCArtboard id="stats-l" label="Light" width={820} height={742}><StatsWindow theme="light" /></DCArtboard>
          <DCArtboard id="stats-d" label="Dark" width={820} height={742}><StatsWindow theme="dark" /></DCArtboard>
        </DCSection>

        <DCSection id="cost" title="3 · Cost / Value" subtitle="Kept the ‘not a bill’ hero. Now with a per-model breakdown + a short note on how it’s calculated.">
          <DCArtboard id="cost-l" label="Light" width={820} height={1212}><CostWindow theme="light" /></DCArtboard>
          <DCArtboard id="cost-d" label="Dark" width={820} height={1212}><CostWindow theme="dark" /></DCArtboard>
        </DCSection>

        <DCSection id="models" title="3b · Model filter &amp; API-only billing" subtitle="A minimal filter. Scoping to an API-only model flips the hero from plan ‘value’ to a real bill.">
          <DCArtboard id="mf-l" label="Filter — open · Light" width={360} height={420}><ModelFilterMenu theme="light" /></DCArtboard>
          <DCArtboard id="mf-d" label="Filter — open · Dark" width={360} height={420}><ModelFilterMenu theme="dark" /></DCArtboard>
          <DCArtboard id="cost-api" label="Cost — Opus 4.8 (API-only)" width={820} height={1212}><CostWindow theme="light" mode="api" /></DCArtboard>
          <DCPostIt top={-4} left={1640} rotate={2} width={224}>Same tokens, same math — but an API-only model isn’t covered by the plan, so “estimated value” becomes “actual spend billed to your key.” The accent dot in the filter warns you before you pick one.</DCPostIt>
        </DCSection>

        <DCSection id="menubar" title="4 · Menubar title" subtitle="Three competing signals collapse into one gauge-dot whose color carries urgency">
          <DCArtboard id="mb-l" label="Light" width={512} height={640}><MenubarStates theme="light" /></DCArtboard>
          <DCArtboard id="mb-d" label="Dark" width={512} height={640}><MenubarStates theme="dark" /></DCArtboard>
        </DCSection>

        <DCSection id="settings" title="5 · General settings" subtitle="11 settings → 3 native groups: Appearance · Alerts · Behavior">
          <DCArtboard id="set-l" label="Light" width={820} height={708}><SettingsWindow theme="light" /></DCArtboard>
          <DCArtboard id="set-d" label="Dark" width={820} height={708}><SettingsWindow theme="dark" /></DCArtboard>
        </DCSection>

      </DesignCanvas>

      <TweaksPanel>
        <TweakSection label="Brand" />
        <TweakColor label="Accent" value={t.accent}
          options={Object.values(ACCENTS)}
          onChange={(v) => setTweak('accent', v)} />
        <TweakSelect label="Number font" value={t.mono}
          options={Object.keys(MONO_STACKS)}
          onChange={(v) => setTweak('mono', v)} />
        <TweakSection label="Popover" />
        <TweakSlider label="Context warning" value={t.threshold} min={50} max={95} step={5} unit="%"
          onChange={(v) => setTweak('threshold', v)} />
        <TweakToggle label="Parallel sessions card" value={t.showSessions}
          onChange={(v) => setTweak('showSessions', v)} />
        <TweakToggle label="Other tools card" value={t.showTools}
          onChange={(v) => setTweak('showTools', v)} />
      </TweaksPanel>
    </React.Fragment>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
