# ContextBar CLI demo — recorded with vhs (https://github.com/charmbracelet/vhs).
# Run via scripts/record-demo.sh (it seeds a sandbox HOME with synthetic Claude
# Code + Codex transcripts and puts `context-bar` on PATH).
# The story: one command shows Claude + Codex usage and API-equivalent cost,
# straight from local transcripts.

Output context-bar-cli-demo.gif
Require context-bar

Set Shell bash
Set FontSize 15
Set Width 1120
Set Height 660
Set Padding 24
Set Theme "Dracula"
Set TypingSpeed 35ms

Hide
Type "clear" Enter
Show

Type "# Claude Code + Codex usage & API-equivalent cost — from local transcripts"
Enter
Sleep 900ms

Type "context-bar monthly --offline"
Enter
Sleep 4500ms

Hide
Type "clear" Enter
Show

Type "# per-model breakdown (plan value vs API-billed)"
Enter
Sleep 700ms
Type "context-bar monthly --breakdown --offline"
Enter
Sleep 5000ms

Hide
Type "clear" Enter
Show

Type "context-bar daily --offline"
Enter
Sleep 4000ms
