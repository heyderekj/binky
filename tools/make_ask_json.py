#!/usr/bin/env python3
"""Builds site/ask.json: what the site's Spotlight answers are grounded in (functions/api/ask.js).

Reads the homepage FAQ (.faq-item > .faq-q + .faq-a), gives each item a stable id (and writes that id onto the
item in site/index.html, so answers can link to it), and adds the app's English Help.md as extra context.
Run it again whenever the FAQ or Help changes:  python3 tools/make_ask_json.py
"""
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPS = {
    'dinky': dict(app='Dinky', line='Dinky makes files smaller.', help='Dinky/Resources/en.lproj/Help.md',
                  voice='Friendly, plain and a little cheeky about making files small. Keep it light; never oversell.'),
    'binky': dict(app='Binky', line='Binky sorts your files.', help='Binky/Resources/en.lproj/Help.md',
                  voice='Warm, plain and a bit playful about mess and calm. Keep it light; never oversell.'),
}
cfg = APPS[ROOT.name]
page_path = ROOT / 'site' / 'index.html'
page = page_path.read_text()


def text(fragment: str) -> str:
    fragment = re.sub(r'<button[^>]*>.*?</button>', '', fragment, flags=re.S)
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', fragment))).strip()


def slug(q: str) -> str:
    return 'faq-' + re.sub(r'[^a-z0-9]+', '-', q.lower()).strip('-')[:60].rstrip('-')


faq = []
def tag(m: re.Match) -> str:
    open_tag, body = m.group(1), m.group(2)
    q = text(re.search(r'<h3 class="faq-q"[^>]*>(.*?)</h3>', body, re.S).group(1))
    a = text(re.search(r'<p class="faq-a"[^>]*>(.*?)</p>', body, re.S).group(1))
    fid = slug(q)
    faq.append({'id': fid, 'q': q, 'a': a})
    open_tag = re.sub(r'\s+id="faq-[^"]*"', '', open_tag)
    return open_tag.replace('class="faq-item"', f'class="faq-item" id="{fid}"', 1) + body


page = re.sub(r'(<div class="faq-item"[^>]*>)(.*?</p>\s*)(?=</div>)', tag, page, flags=re.S)
page_path.write_text(page)

version = (re.search(r'\bv(\d+\.\d+\.\d+)\b', page) or [None, ''])[1]
help_md = (ROOT / cfg['help']).read_text() if (ROOT / cfg['help']).exists() else ''
data = {
    'app': cfg['app'], 'line': cfg['line'], 'version': version, 'email': 'derek@testamentmade.com',
    'voice': cfg['voice'], 'faq': faq, 'more': help_md,
}
(ROOT / 'site' / 'ask.json').write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n')
print(f"{cfg['app']}: {len(faq)} FAQ items, help {len(help_md)} chars, v{version}", file=sys.stderr)
