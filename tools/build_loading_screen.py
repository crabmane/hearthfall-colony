#!/usr/bin/env python3
"""Replace the inherited loading shell with Hearthfall's own presentation."""
from __future__ import annotations

import base64
import io
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "web/loading.html"
TITLE_ART = ROOT / "assets/game/art/title_hearthfall.png"
SORA = ROOT / "assets/template/fonts/display/Sora-VF.subset.woff2"


def data_uri(path: Path, mime: str) -> str:
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def make_background() -> str:
    image = Image.open(TITLE_ART).convert("RGB")
    # Keep the illustrated settlement and people, excluding the large title on the left.
    image = image.crop((900, 80, 2560, 1440))
    image.thumbnail((1280, 1080), Image.Resampling.LANCZOS)
    output = io.BytesIO()
    image.save(output, "WEBP", quality=80, method=6)
    return "data:image/webp;base64," + base64.b64encode(output.getvalue()).decode("ascii")


def main() -> None:
    html = HTML.read_text()
    first_close = html.find("</style>")
    style_start = html.find("<style>", first_close)
    style_end = html.find("</style>", style_start)
    if first_close < 0 or style_start < 0 or style_end < 0:
        raise SystemExit("Could not locate the loader style block")

    bg = make_background()
    sora = data_uri(SORA, "font/woff2")
    css = f"""
    @font-face {{
      font-family: "Hearthfall Sora";
      src: url({sora}) format("woff2");
      font-weight: 100 900;
      font-style: normal;
      font-display: swap;
    }}
    :root {{
      color-scheme: dark;
      --ink: #0b120e;
      --ink-soft: #111b14;
      --parchment: #f1e4c8;
      --muted: #a9b5a1;
      --amber: #efb35a;
      --amber-light: #ffd48a;
      --moss: #a8c56f;
      --border: #52664f;
    }}
    html, body {{
      margin: 0; width: 100%; height: 100%; overflow: hidden;
      background: var(--ink); color: var(--parchment);
      font-family: "Noto Sans SC", "Figtree", system-ui, sans-serif;
    }}
    #canvas {{ display: block; width: 100%; height: 100%; outline: none; }}
    #loading {{
      position: fixed; inset: 0; z-index: 20; overflow: hidden;
      display: flex; align-items: center; justify-content: flex-start;
      padding: clamp(28px, 6vw, 92px);
      background:
        linear-gradient(90deg, rgba(7,12,9,.98) 0%, rgba(7,12,9,.93) 32%, rgba(7,12,9,.35) 68%, rgba(7,12,9,.62) 100%),
        linear-gradient(0deg, rgba(7,12,9,.92) 0%, rgba(7,12,9,.1) 48%, rgba(7,12,9,.25) 100%),
        url({bg}) right center / cover no-repeat;
    }}
    #loading[hidden] {{ display: none !important; }}
    #loading-progress[hidden], #loading-notice[hidden], #loading-retry[hidden] {{ display: none !important; }}
    #loading::before {{
      content: ""; position: absolute; inset: 0; pointer-events: none;
      background:
        radial-gradient(circle at 82% 58%, rgba(239,179,90,.14), transparent 30%),
        radial-gradient(circle at 18% 20%, rgba(168,197,111,.07), transparent 32%);
      mix-blend-mode: screen;
    }}
    #loading::after {{
      content: ""; position: absolute; inset: 0; pointer-events: none; opacity: .13;
      background-image: linear-gradient(rgba(255,255,255,.14) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,.1) 1px, transparent 1px);
      background-size: 5px 5px;
      mask-image: linear-gradient(90deg, black, transparent 65%);
    }}
    .loader-frame {{ position: relative; z-index: 2; width: min(570px, 88vw); }}
    .loader-mark {{
      position: relative; width: 52px; height: 58px; margin-bottom: 24px;
      filter: drop-shadow(0 0 18px rgba(239,179,90,.38));
    }}
    .loader-mark::before {{
      content: ""; position: absolute; left: 8px; right: 8px; bottom: 0; height: 13px;
      border: 2px solid #7d5d3a; border-radius: 50%;
      background: linear-gradient(180deg, #49301c, #1c1710);
      box-shadow: 0 5px 0 #10130f;
    }}
    .loader-ember {{
      position: absolute; left: 17px; bottom: 11px; width: 20px; height: 34px;
      background: linear-gradient(180deg, var(--amber-light), var(--amber) 55%, #b85f33);
      border-radius: 52% 48% 54% 46% / 68% 70% 30% 32%;
      transform: rotate(3deg);
      animation: ember-breathe 1.8s ease-in-out infinite;
    }}
    .loader-ember::after {{
      content: ""; position: absolute; left: 6px; top: 9px; width: 8px; height: 17px;
      background: #fff0c2; border-radius: 50% 50% 45% 45%; opacity: .9;
    }}
    .loader-spark {{
      position: absolute; width: 3px; height: 3px; background: var(--amber-light);
      box-shadow: 0 0 8px var(--amber); animation: spark-rise 2.4s ease-out infinite;
    }}
    .loader-spark.one {{ left: 9px; bottom: 32px; animation-delay: .3s; }}
    .loader-spark.two {{ right: 7px; bottom: 26px; animation-delay: 1.1s; }}
    @keyframes ember-breathe {{ 0%,100% {{ transform: scale(.92) rotate(3deg); opacity: .9; }} 50% {{ transform: scale(1.05) rotate(-2deg); opacity: 1; }} }}
    @keyframes spark-rise {{ 0% {{ transform: translateY(0); opacity: 0; }} 25% {{ opacity: 1; }} 100% {{ transform: translateY(-30px); opacity: 0; }} }}
    .loader-eyebrow {{
      margin: 0 0 18px; color: var(--amber); font-size: 11px; font-weight: 700;
      letter-spacing: .24em; text-transform: uppercase;
    }}
    .loader-title {{
      font-family: "Hearthfall Sora", "Noto Sans SC", sans-serif;
      font-weight: 800; font-size: clamp(52px, 8.8vw, 102px); line-height: .88;
      letter-spacing: -.055em; color: var(--parchment);
      text-shadow: 0 4px 0 rgba(0,0,0,.35), 0 0 32px rgba(0,0,0,.35);
    }}
    .loader-title .colony {{
      display: block; margin-top: 12px; padding-left: 3px; color: var(--amber);
      font-size: .43em; letter-spacing: .16em; text-shadow: 0 0 18px rgba(239,179,90,.2);
    }}
    .loader-copy {{
      max-width: 480px; margin: 26px 0 0; color: var(--muted);
      font-size: clamp(13px, 1.4vw, 15px); line-height: 1.7; letter-spacing: .01em;
    }}
    .loader-progress {{
      width: min(430px, 100%); height: 8px; margin-top: 30px;
      border: 1px solid #586b53; background: #1a261d;
      box-shadow: 0 2px 0 rgba(0,0,0,.3);
    }}
    #loading-progress {{
      appearance: none; -webkit-appearance: none; display: block;
      width: 100%; height: 100%; border: 0; background: transparent;
    }}
    #loading-progress::-webkit-progress-bar {{ background: transparent; }}
    #loading-progress::-webkit-progress-value {{
      background: linear-gradient(90deg, var(--moss), var(--amber));
      box-shadow: 0 0 16px rgba(239,179,90,.45);
    }}
    #loading-progress::-moz-progress-bar {{
      background: linear-gradient(90deg, var(--moss), var(--amber));
      box-shadow: 0 0 16px rgba(239,179,90,.45);
    }}
    .loader-row {{
      display: flex; align-items: baseline; justify-content: space-between; gap: 16px;
      width: min(430px, 100%); margin-top: 10px;
      color: var(--muted); font-size: 10px; font-weight: 700;
      letter-spacing: .15em; text-transform: uppercase;
    }}
    #loading-status {{ color: var(--amber-light); }}
    .loader-note {{ color: #748372; font-weight: 600; text-align: right; }}
    #loading-notice {{
      max-width: 430px; margin: 20px 0 0; color: var(--amber);
      font-size: 12px; line-height: 1.5;
    }}
    #loading-retry {{
      margin-top: 18px; padding: 11px 22px; border: 1px solid var(--amber);
      background: #2a2114; color: var(--amber-light); font: inherit; font-size: 12px;
      font-weight: 700; letter-spacing: .16em; text-transform: uppercase; cursor: pointer;
    }}
    #loading-retry:hover {{ background: #3a2d19; }}
    .loader-footer {{
      position: absolute; z-index: 2; left: clamp(28px, 6vw, 92px); right: clamp(28px, 6vw, 92px);
      bottom: clamp(22px, 4vw, 42px); display: flex; justify-content: space-between; gap: 24px;
      color: #748372; font-size: 10px; font-weight: 700; letter-spacing: .17em; text-transform: uppercase;
    }}
    .loader-steps {{ color: #52664f; }}
    .sr-only {{
      position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
      overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; border: 0;
    }}
    @media (max-width: 760px) {{
      #loading {{
        align-items: flex-end; padding-bottom: max(74px, env(safe-area-inset-bottom));
        background:
          linear-gradient(0deg, rgba(7,12,9,.98) 0%, rgba(7,12,9,.92) 38%, rgba(7,12,9,.35) 100%),
          url({bg}) 66% center / cover no-repeat;
      }}
      .loader-frame {{ width: 100%; }}
      .loader-title {{ font-size: clamp(48px, 14vw, 76px); }}
      .loader-footer {{ left: 24px; right: 24px; bottom: 22px; }}
      .loader-steps {{ display: none; }}
      .loader-copy {{ margin-top: 20px; }}
    }}
    @media (max-height: 560px) and (min-aspect-ratio: 1/1) {{
      #loading {{ align-items: center; padding: 24px 36px; }}
      .loader-mark {{ margin-bottom: 12px; transform: scale(.82); transform-origin: left bottom; }}
      .loader-title {{ font-size: clamp(40px, 7vw, 64px); }}
      .loader-copy {{ margin-top: 14px; max-width: 440px; }}
      .loader-progress {{ margin-top: 18px; }}
      .loader-footer {{ display: none; }}
    }}
    """

    new_markup = """
  <section id="loading" role="status">
    <div class="loader-frame">
      <div class="loader-mark" aria-hidden="true">
        <span class="loader-ember"></span>
        <span class="loader-spark one"></span>
        <span class="loader-spark two"></span>
      </div>
      <p class="loader-eyebrow">A living colony simulation</p>
      <h1 id="game-title" class="sr-only"></h1>
      <div class="loader-title">HEARTHFALL<span class="colony">COLONY</span></div>
      <p class="loader-copy">Lead a handful of survivors into an untamed clearing. Every need, meal, storm, and relationship is simulated.</p>
      <div class="loader-progress"><progress id="loading-progress" aria-label="Download progress"></progress></div>
      <div class="loader-row"><span id="loading-status">Kindling the hearth…</span><span class="loader-note">Auto-saves at dawn</span></div>
      <p id="loading-notice" hidden></p>
      <button id="loading-retry" type="button" hidden>Retry</button>
    </div>
    <div class="loader-footer"><span>Build. Forage. Keep the fire alive.</span><span class="loader-steps">Shelter · Fields · Firelight</span></div>
    <noscript>JavaScript is required to play this game.</noscript>
  </section>
"""

    html = html[:style_start] + "<style>" + css + "  </style>" + html[style_end + len("</style>"):]
    section_start = html.find('<section id="loading" role="status">')
    section_end = html.find("</section>", section_start) + len("</section>")
    if section_start < 0 or section_end < len("</section>"):
        raise SystemExit("Could not locate the loading markup")
    html = html[:section_start] + new_markup.strip() + html[section_end:]
    html = html.replace("status.textContent = zh ? '正在加载…' : 'Loading…';", "status.textContent = zh ? '正在点燃炉火…' : 'Kindling the hearth…';")
    html = html.replace("status.textContent = zh ? '正在加载…' : 'Loading…';", "status.textContent = zh ? '正在点燃炉火…' : 'Kindling the hearth…';")
    html = html.replace("progress.hidden = true;", "progress.hidden = true;")
    HTML.write_text(html)
    print("loading screen written:", HTML, "chars", len(html))


if __name__ == "__main__":
    main()
