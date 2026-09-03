#!/usr/bin/env python3
"""Generates the Zephra context-sidebar artboards from the app's real tokens."""
import json, os
OUT = os.path.dirname(os.path.abspath(__file__))

# ---- tokens, lifted from ZephraChrome / Color+Palette / Chip / ChromePanel (dark appearance)
GROUND = "#17181B"        # CanvasBackground (dark)
AMBER = "#E8A85A"         # Safelight (dark)
DOTS = ["#D88692", "#6FA8DC", "#7BBE88", "#A794D4"]  # ModelDot1-4 (dark)
ACCENT = "#0A84FF"
SIDEBAR = "#212123"
WINDOW = "#1E1E20"
TITLEBAR = "#242426"
HAIR = "rgba(255,255,255,.10)"
P1, P2, P3 = "rgba(255,255,255,.85)", "rgba(255,255,255,.55)", "rgba(255,255,255,.30)"
Q_FILL, T_FILL = "rgba(255,255,255,.07)", "rgba(255,255,255,.14)"

CSS = f"""
body{{margin:0;font-family:-apple-system,"SF Pro Text","Helvetica Neue",Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;color:{P1};font-size:13px;background:{GROUND}}}
a{{color:{ACCENT}}} a:hover{{color:#409CFF}}
.mono{{font-family:ui-monospace,"SF Mono",Menlo,monospace}}
.tnum{{font-variant-numeric:tabular-nums}}
.sec{{color:{P2}}} .ter{{color:{P3}}}
.hdr{{font-size:11px;font-weight:600;color:{P2};display:flex;align-items:center;gap:6px}}
.row{{height:28px;border-radius:6px;display:flex;align-items:center;gap:8px;padding:0 10px;font-size:13px;white-space:nowrap}}
.row.sel{{background:{T_FILL}}}
.cnt{{margin-left:auto;color:{P3};font-variant-numeric:tabular-nums}}
.chip{{height:22px;padding:0 9px;border-radius:11px;display:flex;align-items:center;gap:4px;font-size:12px;color:{P2};background:{Q_FILL};white-space:nowrap}}
.chip.on{{color:{P1};background:{T_FILL}}}
.tb{{height:28px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.10);display:flex;align-items:center;gap:6px;padding:0 10px;font-size:12.5px;color:{P1};white-space:nowrap}}
.tb.icon{{width:34px;padding:0;justify-content:center}}
.thumb{{border-radius:8px;overflow:hidden;background:{Q_FILL};aspect-ratio:1;position:relative}}
.thumb img{{width:100%;height:100%;object-fit:cover;display:block}}
.ring{{box-shadow:inset 0 0 0 2px {ACCENT}}}
.pending{{border-radius:8px;aspect-ratio:1;border:1px dashed rgba(255,255,255,.18);display:flex;align-items:center;justify-content:center;gap:3px}}
.pending i{{width:4px;height:4px;border-radius:50%;background:{P3};display:block}}
.acc{{height:22px;padding:0 6px;border-radius:5px;display:flex;align-items:center;gap:4px;font-size:12px;color:{P1};white-space:nowrap}}
.lbl{{font-size:11px;color:{P3};margin-bottom:4px;white-space:nowrap}}
"""

# ---- icons: stroke-based, 1.5px, on a 16 grid
def ic(name, size=14, color=P2, sw=1.6):
    paths = {
        "search": '<circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5 14 14"/>',
        "sidebar": '<rect x="1.5" y="3" width="13" height="10" rx="2"/><path d="M6 3v10"/>',
        "sidebar-r": '<rect x="1.5" y="3" width="13" height="10" rx="2"/><path d="M10 3v10"/>',
        "chev-d": '<path d="M4 6.5 8 10.5 12 6.5"/>',
        "chev-u": '<path d="M4 10 8 6 12 10"/>',
        "gear": '<circle cx="8" cy="8" r="2.2"/><path d="M8 1.8v2M8 12.2v2M1.8 8h2M12.2 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M3.6 12.4 5 11M11 5l1.4-1.4"/>',
        "sort": '<path d="M5 13V3M2.5 5.5 5 3l2.5 2.5M11 3v10M8.5 10.5 11 13l2.5-2.5"/>',
        "photo": '<rect x="2" y="3" width="12" height="10" rx="1.5"/><circle cx="5.5" cy="6.5" r="1"/><path d="M2.5 12 6 8.5l2.5 2.5L11 8l3 4"/>',
        "grid": '<rect x="2" y="2" width="5" height="5" rx="1"/><rect x="9" y="2" width="5" height="5" rx="1"/><rect x="2" y="9" width="5" height="5" rx="1"/><rect x="9" y="9" width="5" height="5" rx="1"/>',
        "stack": '<rect x="2" y="4" width="10" height="9" rx="1.5"/><path d="M5 4V3.5A1.5 1.5 0 0 1 6.5 2H12.5A1.5 1.5 0 0 1 14 3.5V9.5A1.5 1.5 0 0 1 12.5 11H12"/>',
        "star": '<path d="M8 1.8l1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.6l-3.8 2 .7-4.3-3.1-3 4.3-.6z"/>',
        "clock": '<circle cx="8" cy="8" r="6"/><path d="M8 4.5V8l2.5 1.5"/>',
        "folder": '<path d="M1.5 4.5A1.5 1.5 0 0 1 3 3h3.2l1.5 1.5H13a1.5 1.5 0 0 1 1.5 1.5v6A1.5 1.5 0 0 1 13 13.5H3a1.5 1.5 0 0 1-1.5-1.5z"/>',
        "trash": '<path d="M2.5 4.5h11M6 4.5V3h4v1.5M4 4.5l.7 8.5h6.6l.7-8.5M6.7 7v4M9.3 7v4"/>',
        "plus-c": '<circle cx="8" cy="8" r="6"/><path d="M8 5v6M5 8h6"/>',
        "x-c": '<circle cx="8" cy="8" r="6"/><path d="M5.8 5.8l4.4 4.4M10.2 5.8l-4.4 4.4"/>',
        "shuffle": '<path d="M2 4h2.5l6 8H13M2 12h2.5l1.6-2.1M8.9 6.1 10.5 4H13M11.5 2.5 13 4l-1.5 1.5M11.5 10.5 13 12l-1.5 1.5"/>',
        "lock": '<rect x="3.5" y="7" width="9" height="7" rx="1.5"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v1"/>',
        "photo-plus": '<rect x="2" y="3" width="9" height="10" rx="1.5"/><path d="M2.5 12 5.5 8.5 8 11l1-1"/><circle cx="12.5" cy="4.5" r="2.5" fill="{bg}"/><path d="M12.5 3.2v2.6M11.2 4.5h2.6"/>',
        "ellipsis": '<circle cx="3.5" cy="8" r="1.2" fill="{c}" stroke="none"/><circle cx="8" cy="8" r="1.2" fill="{c}" stroke="none"/><circle cx="12.5" cy="8" r="1.2" fill="{c}" stroke="none"/>',
        "bolt": '<path d="M9 1.5 3.5 9H8l-1 5.5L12.5 7H8z"/>',
    }
    p = paths[name].replace("{bg}", SIDEBAR).replace("{c}", color)
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 16 16" fill="none" stroke="{color}" '
            f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" style="flex:none;display:block">{p}</svg>')

def head(extra_css=""):
    return f'''<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>{CSS}{extra_css}</style>
</helmet>
'''
TAIL = "</x-dc>\n</body>\n</html>\n"

# ---- toolbar ------------------------------------------------------------------------------
def toolbar(pane, subtitle, library=False):
    seg_on = f'background:{T_FILL};color:{P1}'
    seg_off = f'color:{P2}'
    def seg(label, icon, on):
        return (f'<div style="height:24px;padding:0 11px;border-radius:12px;display:flex;align-items:center;gap:6px;font-size:12.5px;{seg_on if on else seg_off}">'
                f'{ic(icon, 13, P1 if on else P2)}<span>{label}</span></div>')
    zoom = ""
    if library:
        zoom = (f'<div style="display:flex;align-items:center;gap:8px;margin-left:10px" title="Thumbnail size">'
                f'{ic("photo", 11, P2)}'
                f'<div style="position:relative;width:110px;height:14px">'
                f'<div style="position:absolute;left:0;right:0;top:5px;height:4px;border-radius:2px;background:rgba(255,255,255,.18)"></div>'
                f'<div style="position:absolute;left:0;width:36%;top:5px;height:4px;border-radius:2px;background:{ACCENT}"></div>'
                f'<div style="position:absolute;left:calc(36% - 7px);top:0;width:14px;height:14px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.5)"></div>'
                f'</div>{ic("photo", 15, P2)}</div>')
    trailing = ""
    if library:
        trailing += f'<div class="tb icon" title="Sort">{ic("sort", 14, P1)}</div>'
    trailing += f'<div class="tb">FLUX.2 klein 4B · 4-bit {ic("chev-d", 12, P2)}</div>'
    if library:
        trailing += f'<div class="tb icon" title="Inspector">{ic("sidebar-r", 15, P1)}</div>'
    trailing += f'<div class="tb icon" title="Settings">{ic("gear", 15, P1)}</div>'
    return f'''
<div style="height:52px;background:{TITLEBAR};border-bottom:1px solid {HAIR};display:flex;align-items:center;flex:none">
  <div style="width:280px;flex:none;display:flex;align-items:center;padding:0 12px 0 20px;gap:8px;height:100%">
    <div style="display:flex;gap:8px">
      <div style="width:12px;height:12px;border-radius:50%;background:#FF5F57"></div>
      <div style="width:12px;height:12px;border-radius:50%;background:#FEBC2E"></div>
      <div style="width:12px;height:12px;border-radius:50%;background:#28C840"></div>
    </div>
    <div style="flex:1"></div>
    <div style="width:30px;height:26px;border-radius:6px;display:flex;align-items:center;justify-content:center">{ic("sidebar", 16, P1)}</div>
  </div>
  <div style="flex:1;display:flex;align-items:center;gap:12px;padding:0 14px;min-width:0">
    <div style="display:flex;height:28px;padding:2px;border-radius:14px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.10);gap:2px;box-sizing:border-box">
      {seg("Canvas", "photo", pane == "canvas")}{seg("Library", "grid", pane == "library")}
    </div>
    <div style="display:flex;flex-direction:column;gap:1px;margin-left:6px;min-width:0">
      <div style="font-size:13px;font-weight:600;color:{P1}">Zephra</div>
      <div class="tnum" style="font-size:11px;color:{P2};white-space:nowrap">{subtitle}</div>
    </div>
    {zoom}
    <div style="flex:1"></div>
    <div style="display:flex;align-items:center;gap:8px">{trailing}</div>
  </div>
</div>'''

# ---- sidebar pieces -----------------------------------------------------------------------
def search_field():
    return (f'<div style="height:26px;border-radius:6px;background:{Q_FILL};display:flex;align-items:center;gap:6px;padding:0 8px">'
            f'{ic("search", 11, P3)}<span style="flex:1;font-size:12px;color:{P3}">Search prompts and seeds</span>'
            f'<span class="mono" style="font-size:11px;color:rgba(255,255,255,.22)">⌘F</span></div>')

def thumb(src, ring=False, star=False):
    r = ' ring' if ring else ''
    s = (f'<div style="position:absolute;right:6px;bottom:6px;filter:drop-shadow(0 1px 2px rgba(0,0,0,.5))">'
         f'{ic("star", 12, "#fff")}</div>') if star else ''
    return f'<div class="thumb{r}"><img src="{src}"></div>' if not star else f'<div class="thumb{r}"><img src="{src}">{s}</div>'

def pending():
    return '<div class="pending"><i></i><i></i><i></i></div>'

def segments(total, done):
    cells = "".join(f'<div style="flex:1;background:{AMBER if i < done else "rgba(255,255,255,.18)"}"></div>' for i in range(total))
    return f'<div style="display:flex;gap:2px;height:3px">{cells}</div>'

def run_grid(tiles):
    return f'<div style="display:grid;grid-template-columns:repeat(2, minmax(0, 1fr));gap:6px">{"".join(tiles)}</div>'

def sidebar_canvas():
    waiting = f'''
<div style="display:flex;flex-direction:column;gap:6px">
  <div style="border-radius:8px;background:{Q_FILL};padding:8px 10px;display:flex;align-items:center;gap:8px">
    <span style="flex:1;font-size:12px;color:{P1};overflow:hidden;text-overflow:ellipsis;white-space:nowrap">the same wall, no bicycle</span>
    <span class="tnum" style="font-size:11px;color:{P2};white-space:nowrap">1024 × 1024</span>
    {ic("x-c", 13, P3)}
  </div>
  {run_grid([pending(), pending()])}
</div>'''
    running = f'''
<div style="display:flex;flex-direction:column;gap:6px">
  <div style="border-radius:8px;background:rgba(232,168,90,.12);border:1px solid rgba(232,168,90,.28);padding:8px 10px;display:flex;flex-direction:column;gap:7px">
    <span style="font-size:12px;color:{P1};overflow:hidden;text-overflow:ellipsis;white-space:nowrap">a red bicycle against a limestone wall</span>
    {segments(4, 3)}
  </div>
  {run_grid([thumb("t-a2.jpg", ring=True), thumb("t-a3.jpg"), thumb("t-a1.jpg"), pending()])}
</div>'''
    def finished(caption, tiles):
        return (f'<div style="display:flex;flex-direction:column;gap:6px">'
                f'<div style="font-size:11px;color:{P2};overflow:hidden;text-overflow:ellipsis;white-space:nowrap;padding:0 2px">{caption}</div>'
                f'{run_grid(tiles)}</div>')
    return f'''
<div style="width:280px;flex:none;background:{SIDEBAR};border-right:1px solid {HAIR};display:flex;flex-direction:column;min-height:0">
  <div style="padding:12px 14px">{search_field()}</div>
  <div style="height:1px;background:{HAIR}"></div>
  <div style="flex:1;overflow:hidden;padding:12px 14px 0;display:flex;flex-direction:column;gap:14px">
    <div class="hdr"><span>Today</span><span class="tnum" style="color:{P3};font-weight:500">35</span><span style="flex:1"></span><a style="font-size:11px;font-weight:500;text-decoration:none">Clear queue</a></div>
    {waiting}
    {running}
    {finished("a chrome android reading the paper on a park bench, golden hour", [thumb("t-g10.jpg"), thumb("t-g11.jpg"), thumb("t-g12.jpg"), thumb("t-g14.jpg", star=True)])}
    {finished("neon side street after rain, Tokyo, 35mm", [thumb("t-a4.jpg"), thumb("t-a1.jpg")])}
  </div>
  <div style="padding:9px 18px;border-top:1px solid {HAIR}"><a style="font-size:12px;text-decoration:none">Show all 35 in Library</a></div>
</div>'''

def lib_rows(editing=False, drop_on=None):
    def row(icon, label, count, sel=False, dot=None):
        lead = f'<span style="width:8px;height:8px;border-radius:50%;background:{dot};flex:none"></span>' if dot else ic(icon, 14, P2 if not sel else P1)
        return f'<div class="row{" sel" if sel else ""}">{lead}<span style="overflow:hidden;text-overflow:ellipsis">{label}</span><span class="cnt">{count}</span></div>'
    def album(label, count, target=False):
        style = f' style="box-shadow:inset 0 0 0 2px {ACCENT}"' if target else ''
        return f'<div class="row"{style}>{ic("folder", 14, P2)}<span>{label}</span><span class="cnt">{count}</span></div>'
    edit_row = ""
    if editing:
        edit_row = (f'<div class="row" style="padding-right:6px">{ic("folder", 14, P2)}'
                    f'<div style="flex:1;height:22px;border-radius:4px;background:rgba(0,0,0,.35);border:1px solid rgba(255,255,255,.18);box-shadow:0 0 0 3px rgba(10,132,255,.45);display:flex;align-items:center;padding:0 4px;font-size:13px">'
                    f'<span style="background:rgba(10,132,255,.55);border-radius:2px;padding:0 1px">Untitled Album</span><span style="width:1px;height:14px;background:{P1};margin-left:1px"></span></div></div>')
    return f'''
    <div class="hdr" style="padding:0 10px 6px">Library</div>
    {row("photo", "All images", "35", sel=True)}
    {row("star", "Favourites", "1")}
    {row("clock", "Last 7 days", "35")}
    <div class="hdr" style="padding:16px 10px 6px">Models</div>
    {row(None, "Z-Image Turbo · 8-bit", "4", dot=DOTS[0])}
    {row(None, "Z-Image Turbo · 4-bit", "7", dot=DOTS[1])}
    {row(None, "Qwen-Image 2512 · 4-bit", "7", dot=DOTS[2])}
    {row(None, "FLUX.2 klein 4B · 4-bit", "15", dot=DOTS[3])}
    {row(None, "FLUX.2 klein 4B · 8-bit", "2", dot=DOTS[0])}
    <div class="hdr" style="padding:16px 10px 6px">Tags</div>
    <div style="display:flex;flex-wrap:wrap;gap:6px;padding:2px 10px"><div class="chip">neon</div><div class="chip">robots</div></div>
    <div class="hdr" style="padding:16px 10px 6px">Albums</div>
    {album("Aliens", "6")}
    {album("Bicycles", "3", target=(drop_on == "Bicycles"))}
    {edit_row}'''

def drag_ghost():
    def card(src, rot, dx):
        return (f'<div style="position:absolute;left:{dx}px;top:0;width:64px;height:64px;border-radius:6px;overflow:hidden;transform:rotate({rot}deg);'
                f'box-shadow:0 6px 18px rgba(0,0,0,.55);border:1px solid rgba(255,255,255,.25)"><img src="{src}" style="width:100%;height:100%;object-fit:cover;display:block"></div>')
    return (f'<div style="position:absolute;left:150px;top:0;width:90px;height:78px;pointer-events:none;opacity:.92">'
            f'{card("t-a2.jpg", -8, 0)}{card("t-a1.jpg", 4, 8)}{card("t-a4.jpg", -2, 16)}'
            f'<div style="position:absolute;left:66px;top:-8px;min-width:20px;height:20px;padding:0 6px;border-radius:10px;background:{ACCENT};color:#fff;font-size:11px;font-weight:600;display:flex;align-items:center;justify-content:center;box-shadow:0 1px 3px rgba(0,0,0,.4)">3</div>'
            f'</div>')

def sidebar_library(editing=False, drop_on=None, ghost=False, height=None):
    h = f'height:{height}px;' if height else ''
    ghost_html = drag_ghost() if ghost else ""
    return f'''
<div style="width:280px;flex:none;{h}background:{SIDEBAR};border-right:1px solid {HAIR};display:flex;flex-direction:column;min-height:0;box-sizing:border-box">
  <div style="padding:12px 14px;display:flex;flex-direction:column;gap:8px">
    {search_field()}
    <div style="display:flex;gap:6px"><div class="chip on">All</div><div class="chip">Favourites</div></div>
  </div>
  <div style="height:1px;background:{HAIR}"></div>
  <div style="flex:1;overflow:hidden;padding:10px 10px 0;position:relative">
    {lib_rows(editing=editing, drop_on=drop_on)}
    <div style="position:absolute;left:0;top:{'532' if ghost else '0'}px;width:280px;height:0">{ghost_html}</div>
  </div>
  <div style="border-top:1px solid {HAIR};padding:9px 18px;display:flex;align-items:center;gap:8px;font-size:12px;color:{P2}">{ic("trash", 14, P2)}<span>Recently Deleted</span><span class="cnt" style="font-size:12px">0</span></div>
  <div style="border-top:1px solid {HAIR};padding:9px 18px;display:flex;align-items:center;gap:8px;font-size:12px;color:{P2}">{ic("plus-c", 14, P2)}<span>New Album</span></div>
</div>'''

# ---- canvas pieces ------------------------------------------------------------------------
def slider(width, frac):
    return (f'<div style="position:relative;width:{width}px;height:14px">'
            f'<div style="position:absolute;left:0;right:0;top:5px;height:4px;border-radius:2px;background:rgba(255,255,255,.18)"></div>'
            f'<div style="position:absolute;left:0;width:{int(frac*100)}%;top:5px;height:4px;border-radius:2px;background:{ACCENT}"></div>'
            f'<div style="position:absolute;left:calc({int(frac*100)}% - 7px);top:0;width:14px;height:14px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.5)"></div></div>')

def capsule(busy=True):
    stop = (f'<div style="height:26px;padding:0 12px;border-radius:6px;background:rgba(255,255,255,.10);display:flex;align-items:center;font-size:12.5px">Stop</div>') if busy else ''
    return f'''
<div style="position:absolute;left:50%;bottom:18px;transform:translateX(-50%);width:680px;border-radius:16px;background:rgba(38,38,40,.80);backdrop-filter:blur(30px) saturate(140%);border:1px solid {HAIR};box-shadow:0 8px 22px rgba(0,0,0,.28);overflow:hidden;box-sizing:border-box">
  {segments(4, 3 if busy else 0) if busy else '<div style="height:3px"></div>'}
  <div style="padding:13px 16px 12px;display:flex;flex-direction:column;gap:12px">
    <div style="display:flex;gap:12px;align-items:flex-start">
      <div style="flex:1;min-height:76px;font-size:13px;line-height:1.35;color:{P1}">a red bicycle against a limestone wall</div>
      <div style="width:64px;height:64px;border-radius:10px;background:{Q_FILL};display:flex;align-items:center;justify-content:center">{ic("photo-plus", 24, P2, 1.3)}</div>
    </div>
    <div style="height:1px;background:{HAIR}"></div>
    <div style="display:flex;align-items:flex-end;gap:18px">
      <div><div class="lbl">Size</div><div class="acc tnum">1024 × 1024 {ic("chev-d", 11, P2)}</div></div>
      <div><div class="lbl">Steps</div><div class="acc" style="gap:10px;padding:0">{slider(100, 0.3)}<span class="tnum sec">4</span></div></div>
      <div><div class="lbl">Seed</div><div class="acc" style="padding:0;gap:4px"><span class="mono sec" style="padding:0 4px">2B7A·40E1</span>{ic("shuffle", 13, P1)}<span style="width:6px"></span>{ic("lock", 13, P1)}</div></div>
      <div style="flex:1"></div>
      <div class="acc tnum">{ic("stack", 13, P1)}<span>4</span></div>
      {stop}
      <div style="height:28px;padding:0 12px;border-radius:7px;background:{ACCENT};color:#fff;display:flex;align-items:center;gap:6px;font-size:13px;font-weight:500;opacity:{'1' if True else '.5'}">Generate <span style="opacity:.7">⌘⏎</span></div>
    </div>
  </div>
</div>'''

def lip():
    return f'''
<div style="position:absolute;left:50%;bottom:0;transform:translateX(-50%);width:680px;height:22px;border-radius:16px 16px 0 0;background:rgba(38,38,40,.80);backdrop-filter:blur(30px) saturate(140%);border:1px solid {HAIR};border-bottom:none;box-shadow:0 -4px 18px rgba(0,0,0,.28);overflow:hidden;box-sizing:border-box">
  {segments(4, 3)}
  <div style="display:flex;align-items:center;justify-content:center;height:18px">{ic("chev-u", 13, P2)}</div>
</div>'''

def canvas_pane(tucked=False):
    return f'''
<div style="flex:1;position:relative;background:{GROUND};overflow:hidden;min-width:0">
  <img src="hero.jpg" style="position:absolute;inset:0;margin:auto;max-width:100%;max-height:100%;opacity:{'1' if tucked else '.6'}">
  {lip() if tucked else capsule(busy=True)}
</div>'''

# ---- library pieces -----------------------------------------------------------------------
def library_pane():
    def cell(src, sel=False, star=False):
        return (f'<div style="width:168px;height:168px;border-radius:8px;overflow:hidden;position:relative;{"box-shadow:0 0 0 2px " + ACCENT + ";" if sel else ""}">'
                f'<img src="{src}" style="width:100%;height:100%;object-fit:cover;display:block">'
                + (f'<div style="position:absolute;right:6px;bottom:6px;filter:drop-shadow(0 1px 2px rgba(0,0,0,.5))">{ic("star", 12, "#fff")}</div>' if star else '')
                + '</div>')
    def day(title, count, cells):
        return (f'<div style="display:flex;align-items:baseline;gap:10px;padding:6px 0 2px"><span style="font-size:15px;font-weight:600">{title}</span><span class="tnum" style="font-size:11px;color:{P2}">{count} images</span></div>'
                f'<div style="display:grid;grid-template-columns:repeat(4, 168px);gap:12px">{"".join(cells)}</div>')
    grid = f'''
<div style="flex:1;background:{WINDOW};overflow:hidden;padding:18px 20px;display:flex;flex-direction:column;gap:18px;min-width:0">
  {day("Today", 35, [cell("t-a2.jpg", sel=True), cell("t-a3.jpg"), cell("t-a1.jpg"), cell("t-g10.jpg"), cell("t-g11.jpg"), cell("t-g12.jpg"), cell("t-g14.jpg", star=True), cell("t-a4.jpg")])}
  {day("Yesterday", 12, [cell("t-a1.jpg"), cell("t-g12.jpg"), cell("t-a4.jpg"), cell("t-g10.jpg")])}
</div>'''
    def fact(k, v, mono=False):
        return f'<div style="display:flex;justify-content:space-between;gap:10px;font-size:12.5px"><span class="sec">{k}</span><span class="{"mono" if mono else "tnum"}" style="text-align:right">{v}</span></div>'
    inspector = f'''
<div style="width:320px;flex:none;background:{WINDOW};border-left:1px solid {HAIR};padding:18px;display:flex;flex-direction:column;gap:16px;box-sizing:border-box;overflow:hidden">
  <div style="width:284px;height:284px;border-radius:8px;overflow:hidden;position:relative"><img src="insp.jpg" style="width:100%;height:100%;object-fit:cover;display:block">
    <div style="position:absolute;right:10px;top:10px;filter:drop-shadow(0 1px 3px rgba(0,0,0,.5))">{ic("star", 18, "#fff")}</div></div>
  <div style="font-family:'New York','Iowan Old Style',Georgia,serif;font-size:13px;line-height:1.4;color:{P1}">a red bicycle against a limestone wall</div>
  <div style="display:flex;flex-direction:column;gap:6px">
    {fact("Model", "FLUX.2 klein 4B · 4-bit")}{fact("Size", "1024 × 1024")}{fact("Seed", "2B7A·40E1", mono=True)}{fact("Steps", "4")}{fact("Made", "Today, 00:12")}{fact("Took", "27.6 s")}
  </div>
  <div style="display:flex;flex-wrap:wrap;gap:6px"><div class="chip">neon {ic("x-c", 12, P3)}</div><div class="acc" style="height:22px;font-size:12px;color:{P2}">{ic("plus-c", 13, P2)} Tag</div></div>
  <div style="display:flex;flex-wrap:wrap;gap:6px"><div class="chip">Bicycles {ic("x-c", 12, P3)}</div><div class="acc" style="height:22px;font-size:12px;color:{P2}">Add to Album {ic("chev-d", 11, P2)}</div></div>
  <div style="flex:1"></div>
  <div style="display:flex;flex-direction:column;gap:8px">
    <div style="height:28px;border-radius:7px;background:{ACCENT};color:#fff;display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:500">Open in Canvas</div>
    <div style="display:flex;gap:8px">
      <div style="flex:1;height:26px;border-radius:6px;background:rgba(255,255,255,.10);display:flex;align-items:center;justify-content:center;font-size:12.5px">Queue Variation</div>
      <div style="flex:1;height:26px;border-radius:6px;background:rgba(255,255,255,.10);display:flex;align-items:center;justify-content:center;font-size:12.5px">Reveal in Finder</div>
    </div>
    <div style="height:26px;border-radius:6px;background:rgba(255,255,255,.10);display:flex;align-items:center;justify-content:center;font-size:12.5px">Use as Reference</div>
  </div>
</div>'''
    return grid + inspector

# ---- artboards ----------------------------------------------------------------------------
def window(pane, subtitle, sidebar, body, library=False):
    return (f'<div style="width:1440px;height:900px;display:flex;flex-direction:column;background:{GROUND};overflow:hidden;border-radius:10px">'
            f'{toolbar(pane, subtitle, library=library)}'
            f'<div style="flex:1;display:flex;min-height:0">{sidebar}{body}</div></div>')

files = {
    "Main.dc.html": head() + window("canvas", "Denoising · step 3 of 4 · 8.2 s/step · 2 queued", sidebar_canvas(), canvas_pane()) + TAIL,
    "CanvasTucked.dc.html": head() + window("canvas", "Denoising · step 3 of 4 · 8.2 s/step · 2 queued", sidebar_canvas(), canvas_pane(tucked=True)) + TAIL,
    "Library.dc.html": head() + window("library", "Ready", sidebar_library(), library_pane(), library=True) + TAIL,
    "AlbumNaming.dc.html": head() + sidebar_library(editing=True, height=720) + TAIL,
    "AlbumDrop.dc.html": head() + sidebar_library(drop_on="Bicycles", ghost=True, height=720) + TAIL,
}
for name, html in files.items():
    with open(os.path.join(OUT, name), "w") as f:
        f.write(html)

canvas = {
    "artboards": [
        {"file": "Main.dc.html", "title": "Canvas · a run in progress", "x": 0, "y": 0, "w": 1440, "h": 900},
        {"file": "CanvasTucked.dc.html", "title": "Canvas · prompt tucked", "x": 1560, "y": 0, "w": 1440, "h": 900},
        {"file": "Library.dc.html", "title": "Library · filing", "x": 0, "y": 1080, "w": 1440, "h": 900},
        {"file": "AlbumNaming.dc.html", "title": "Sidebar · naming a new album", "x": 1560, "y": 1080, "w": 280, "h": 720},
        {"file": "AlbumDrop.dc.html", "title": "Sidebar · dropping onto an album", "x": 1960, "y": 1080, "w": 280, "h": 720},
    ],
    "annotations": [
        {"id": "note-canvas", "x": 0, "y": -150, "w": 560, "text": "Canvas context. The sidebar is the session: what is waiting (inset card, dashed slots), what is rendering (safelight amber, step segments), and what came out, newest run first. Each image lands in its own dashed slot, so nothing under the prompt ever moves. No scope chips or sources here; typing in search still jumps to the Library."},
        {"id": "note-tucked", "x": 1560, "y": -150, "w": 560, "text": "Click the picture: the capsule slides down until a 22 pt lip stays at the bottom edge, still carrying the step segments while a run is going. Click the picture or the lip, press Esc, use View > Hide Prompt (Option-Command-P), or just start typing to bring it back."},
        {"id": "note-library", "x": 0, "y": 930, "w": 560, "text": "Library context is for filing. The thumbnail size slider moves into the toolbar as a Photos-style zoom control, so the bar over the grid appears only when a chip narrows it or a selection needs counting. Albums get a pinned New Album action at the foot of the sidebar; Recently Deleted stays where it was."},
        {"id": "note-albums", "x": 1560, "y": 930, "w": 680, "text": "New Album adds a row in place with its name selected: Return names it, Escape leaves 'Untitled Album' as Finder does; Rename from the context menu edits the same way. Only Delete keeps a dialog. Dragging images from the grid onto an album row rings it in the accent colour and files them; a dragged image that is part of the selection brings the whole selection."},
    ],
    "launch": {"view": "canvas"},
}
with open(os.path.join(OUT, "canvas.json"), "w") as f:
    json.dump(canvas, f, indent=2)
print("wrote", ", ".join(files), "canvas.json")
