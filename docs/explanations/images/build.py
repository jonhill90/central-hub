#!/usr/bin/env python3
"""Draws the explanation pages' figures as connected blocks.

Run from anywhere:  python3 -I docs/explanations/images/build.py
It writes one SVG per figure next to this file. Every colour is a CSS variable with a light and a
dark value (prefers-color-scheme), and every figure sits on its own opaque plate, so it reads on a
light or a dark page. Blocks carry our own drawn symbols, not vendor logos (see the README here).
Names are roles only: no hostnames, addresses or zone names.
"""
import html
import os

OUT = os.path.dirname(os.path.abspath(__file__))
e = html.escape
FONT = "system-ui,-apple-system,'Segoe UI',Roboto,sans-serif"

CSS = """
:root{--plate:#f5f7fb;--tray:#e8eef7;--tray-s:#a3b3cc;--body:#ffffff;--body-s:#9fb0c8;--ink:#14213a;--sub:#475772;
--glyph-bg:#e6edf8;--glyph:#1d3050;--casing:#f5f7fb;--pill:#ffffff;--shadow:#14213a;--risk:#b3261e;
--net:#0b6fb3;--ctl:#b35f00;--git:#6d3fc7;--data:#0a7a54;--id:#b81b55;--gap:#5d6b82}
@media (prefers-color-scheme: dark){:root{--plate:#0f1b2d;--tray:#16263d;--tray-s:#2c4263;--body:#1d3050;--body-s:#35507a;
--ink:#f1f5fb;--sub:#a9bbd4;--glyph-bg:#eef3fa;--glyph:#16263d;--casing:#050b14;--pill:#050b14;--shadow:#050b14;--risk:#ff6b6b;
--net:#4cc3ff;--ctl:#ffb347;--git:#b48cff;--data:#5be3b0;--id:#ff7a9c;--gap:#8fa3c2}}
"""
KINDS = {"net": "network", "ctl": "control", "git": "git", "data": "data and backup", "id": "sign-in", "gap": "no link"}


def glyph(name):
    s = 'fill="none" stroke="var(--glyph)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"'
    g = {
        "cloud": '<path d="M14 34h22a8 8 0 0 0 1-16 11 11 0 0 0-21-2 9 9 0 0 0-2 18z"/>',
        "wall": '<path d="M8 12h32v24H8zM8 20h32M8 28h32M20 12v8M32 20v8M20 28v8"/>',
        "wheel": '<path d="M24 7l14 7 4 15-9 12H15L6 29l4-15z"/><circle cx="24" cy="25" r="5"/>',
        "key": '<circle cx="17" cy="24" r="8"/><path d="M25 24h17M36 24v7M42 24v5"/>',
        "branch": '<circle cx="14" cy="12" r="4"/><circle cx="14" cy="36" r="4"/><circle cx="34" cy="18" r="4"/><path d="M14 16v16M34 22c0 8-20 4-20 10"/>',
        "stack": '<rect x="8" y="9" width="32" height="9" rx="2"/><rect x="8" y="21" width="32" height="9" rx="2"/><rect x="8" y="33" width="32" height="9" rx="2"/>',
        "term": '<rect x="6" y="10" width="36" height="28" rx="4"/><path d="M13 20l7 5-7 5M24 31h10"/>',
        "db": '<ellipse cx="24" cy="13" rx="14" ry="5"/><path d="M10 13v22c0 3 6 5 14 5s14-2 14-5V13"/>',
        "user": '<circle cx="24" cy="16" r="7"/><path d="M9 41c1-9 8-13 15-13s14 4 15 13"/>',
        "sync": '<path d="M38 20a14 14 0 0 0-26-4M10 28a14 14 0 0 0 26 4M10 12v6h6M38 36v-6h-6"/>',
        "badge": '<rect x="7" y="11" width="34" height="26" rx="4"/><circle cx="18" cy="24" r="4"/><path d="M26 21h9M26 27h7"/>',
        "gear": '<circle cx="24" cy="24" r="6"/><path d="M24 6v6M24 36v6M6 24h6M36 24h6M11 11l4 4M33 33l4 4M37 11l-4 4M15 33l-4 4"/>',
        "lock": '<rect x="10" y="22" width="28" height="18" rx="3"/><path d="M16 22v-6a8 8 0 0 1 16 0v6"/>',
        "bell": '<path d="M12 34V22a12 12 0 0 1 24 0v12l3 3H9zM20 41h8"/>',
        "home": '<path d="M7 24L24 9l17 15M12 21v18h24V21"/>',
        "bowl": '<path d="M7 22h34a17 17 0 0 1-34 0zM16 14c-2-3 2-4 0-7M24 14c-2-3 2-4 0-7M32 14c-2-3 2-4 0-7"/>',
        "film": '<rect x="8" y="9" width="32" height="30" rx="3"/><path d="M8 17h32M8 31h32M16 9v30M32 9v30"/>',
        "chart": '<path d="M8 8v32h32M14 32l7-10 7 6 9-14"/>',
        "disk": '<rect x="7" y="14" width="34" height="20" rx="4"/><circle cx="33" cy="24" r="3"/><path d="M13 24h10"/>',
        "folder": '<path d="M6 14h13l4 5h19v19H6z"/>',
        "box": '<path d="M24 6l16 8v20l-16 8-16-8V14zM8 14l16 8 16-8M24 22v20"/>',
        "doc": '<path d="M12 6h18l8 8v28H12zM30 6v8h8M18 24h14M18 31h14"/>',
        "link": '<path d="M20 28l8-8M17 22l-5 5a7 7 0 0 0 10 10l5-5M31 26l5-5a7 7 0 0 0-10-10l-5 5"/>',
    }
    return f'<svg width="48" height="48" viewBox="0 0 48 48"><g {s}>{g[name]}</g></svg>'


def inner_glyph(name):
    return glyph(name).split(">", 1)[1].rsplit("</svg>", 1)[0]


def port(n, side, off=0):
    x, y, w, h = n["x"], n["y"], n["w"], n["h"]
    return {"L": (x, y + h / 2 + off), "R": (x + w, y + h / 2 + off), "T": (x + w / 2 + off, y), "B": (x + w / 2 + off, y + h)}[side]


def route(p, sa, q, sb, via=None):
    hz = lambda s: s in "LR"
    if via is not None:
        if hz(sa) and hz(sb):
            return [p, (via, p[1]), (via, q[1]), q]
        return [p, (p[0], via), (q[0], via), q]
    if hz(sa) and hz(sb):
        if abs(p[1] - q[1]) < 1:
            return [p, q]
        m = (p[0] + q[0]) / 2
        return [p, (m, p[1]), (m, q[1]), q]
    if not hz(sa) and not hz(sb):
        if abs(p[0] - q[0]) < 1:
            return [p, q]
        m = (p[1] + q[1]) / 2
        return [p, (p[0], m), (q[0], m), q]
    if hz(sa):
        return [p, (q[0], p[1]), q]
    return [p, (p[0], q[1]), q]


def rounded(pts, r=12):
    d = f"M{pts[0][0]:.1f} {pts[0][1]:.1f}"
    for i in range(1, len(pts) - 1):
        (x0, y0), (x1, y1), (x2, y2) = pts[i - 1], pts[i], pts[i + 1]
        l1 = max(abs(x1 - x0) + abs(y1 - y0), 1e-6)
        l2 = max(abs(x2 - x1) + abs(y2 - y1), 1e-6)
        rr = min(r, l1 / 2, l2 / 2)
        d += f" L{x1 - (x1 - x0) / l1 * rr:.1f} {y1 - (y1 - y0) / l1 * rr:.1f} Q{x1:.1f} {y1:.1f} {x1 + (x2 - x1) / l2 * rr:.1f} {y1 + (y2 - y1) / l2 * rr:.1f}"
    return d + f" L{pts[-1][0]:.1f} {pts[-1][1]:.1f}"


def label_at(pts):
    """Midpoint of the longest segment, so a label sits on a straight stretch."""
    best = max(range(len(pts) - 1), key=lambda i: abs(pts[i + 1][0] - pts[i][0]) + abs(pts[i + 1][1] - pts[i][1]))
    return ((pts[best][0] + pts[best + 1][0]) / 2, (pts[best][1] + pts[best + 1][1]) / 2)


def draw(spec):
    W, H = spec["size"]
    nodes = {k: dict(v, w=v.get("w", 190), h=v.get("h", 72)) for k, v in spec["nodes"].items()}
    groups = spec.get("groups", {})
    # trays can be cable ends too
    for k, g in groups.items():
        nodes[k] = dict(x=g["x"], y=g["y"], w=g["w"], h=g["h"])
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="{FONT}" role="img" aria-labelledby="t d">',
         f"<title id=\"t\">{e(spec['title'])}</title><desc id=\"d\">{e(spec['desc'])}</desc>",
         f"<style>{CSS}</style>",
         f'<rect width="{W}" height="{H}" rx="18" style="fill:var(--plate)"/>',
         f'<text x="28" y="40" font-size="20" font-weight="700" style="fill:var(--ink)">{e(spec["title"])}</text>',
         f'<text x="28" y="62" font-size="13" style="fill:var(--sub)">{e(spec["sub"])}</text>']
    for k, g in groups.items():
        risk = g.get("risk")
        stroke = "var(--risk)" if risk else "var(--tray-s)"
        dash = "8 5" if risk else "2 7"
        o.append(f'<rect x="{g["x"]}" y="{g["y"]}" width="{g["w"]}" height="{g["h"]}" rx="16" style="fill:var(--tray);stroke:{stroke}" stroke-width="2" stroke-dasharray="{dash}" stroke-linecap="round"/>'
                 f'<text x="{g["x"] + 16}" y="{g["y"] + 24}" font-size="12" font-weight="700" letter-spacing=".05em" style="fill:var(--sub)">{e(g["label"].upper())}</text>')
        if g.get("badge"):
            o.append(badge(g["x"] + g["w"] - 22, g["y"] + 22, g["badge"]))
    labels = []
    for ed in spec["edges"]:
        a, sa, b, sb, kind, lab = ed[:6]
        opt = ed[6] if len(ed) > 6 else {}
        p = port(nodes[a], sa, opt.get("oa", 0))
        q = port(nodes[b], sb, opt.get("ob", 0))
        pts = route(p, sa, q, sb, opt.get("via"))
        d = rounded(pts)
        col = f"var(--{kind})"
        if kind == "gap":
            o.append(f'<path d="{d}" fill="none" style="stroke:{col}" stroke-width="3" stroke-dasharray="3 8" stroke-linecap="round"/>')
        else:
            o.append(f'<path d="{d}" fill="none" style="stroke:var(--casing)" stroke-width="9" stroke-linecap="round"/>')
            dash = ' stroke-dasharray="10 7"' if kind == "data" else ""
            o.append(f'<path d="{d}" fill="none" style="stroke:{col}" stroke-width="4" stroke-linecap="round"{dash}/>')
            for pt in (pts[0], pts[-1]):
                o.append(f'<circle cx="{pt[0]:.1f}" cy="{pt[1]:.1f}" r="7" style="fill:var(--casing)"/><circle cx="{pt[0]:.1f}" cy="{pt[1]:.1f}" r="4" style="fill:{col}"/>')
        if lab:
            mx, my = opt.get("at", label_at(pts))
            w = 12 + 6.3 * len(lab)
            labels.append(f'<rect x="{mx - w / 2:.1f}" y="{my - 10:.1f}" width="{w:.1f}" height="20" rx="10" style="fill:var(--pill);stroke:{col}" stroke-width="1"/>'
                          f'<text x="{mx:.1f}" y="{my + 4:.1f}" text-anchor="middle" font-size="11.5" font-weight="600" style="fill:{col}">{e(lab)}</text>')
    for k, n in spec["nodes"].items():
        n = nodes[k]
        x, y, w, h = n["x"], n["y"], n["w"], n["h"]
        acc = f"var(--{n.get('kind', 'net')})"
        risk = n.get("risk")
        stroke = "var(--risk)" if risk else "var(--body-s)"
        sw = 3 if risk else 1.5
        dash = ' stroke-dasharray="7 5"' if n.get("planned") else ""
        o.append(f'<g><rect x="{x}" y="{y + 4}" width="{w}" height="{h}" rx="12" style="fill:var(--shadow)" opacity=".22"/>'
                 f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" style="fill:var(--body);stroke:{stroke}" stroke-width="{sw}"{dash}/>'
                 f'<path d="M{x} {y + 12}a12 12 0 0 1 12-12h{w - 24}a12 12 0 0 1 12 12v2H{x}z" style="fill:{acc}"/>')
        ps = min(h - 30, 44)
        py = y + 14 + (h - 14 - ps) / 2
        o.append(f'<rect x="{x + 10}" y="{py:.1f}" width="{ps}" height="{ps}" rx="9" style="fill:var(--glyph-bg)"/>'
                 f'<g transform="translate({x + 10 + ps * 0.12:.1f} {py + ps * 0.12:.1f}) scale({ps * 0.76 / 48:.3f})">{inner_glyph(n["glyph"])}</g>')
        tx = x + 10 + ps + 10
        sub = n.get("s", "").split("|") if n.get("s") else []
        block = 15 + 13.5 * len(sub)
        y0 = y + 14 + (h - 14 - block) / 2 + 12
        title = n["t"]
        avail = w - (tx - x) - 8
        if 7.4 * len(title) > avail * 1.02 or any(6.3 * len(s) > avail * 1.02 for s in sub):
            print(f"  warn: text may overflow in {spec['file']} node {k}")
        o.append(f'<text x="{tx}" y="{y0:.1f}" font-size="13.5" font-weight="700" style="fill:var(--ink)">{e(title)}</text>')
        for i, line in enumerate(sub):
            o.append(f'<text x="{tx}" y="{y0 + 14 + i * 13.5:.1f}" font-size="11.5" style="fill:var(--sub)">{e(line)}</text>')
        if n.get("badge"):
            o.append(badge(x + w - 4, y + 2, n["badge"]))
        o.append("</g>")
    o += labels
    used = sorted({ed[4] for ed in spec["edges"]}, key=list(KINDS).index)
    lx = 28
    for kd in used:
        col = f"var(--{kd})"
        dash = ' stroke-dasharray="10 7"' if kd == "data" else (' stroke-dasharray="3 8"' if kd == "gap" else "")
        o.append(f'<path d="M{lx} {H - 24}h28" style="stroke:{col}" stroke-width="4" stroke-linecap="round"{dash}/><text x="{lx + 36}" y="{H - 20}" font-size="12" style="fill:var(--sub)">{KINDS[kd]}</text>')
        lx += 64 + 6.5 * len(KINDS[kd])
    if spec.get("legend_risk"):
        o.append(f'<circle cx="{lx + 8}" cy="{H - 24}" r="9" style="fill:var(--risk)"/><text x="{lx + 8}" y="{H - 20}" text-anchor="middle" font-size="11" font-weight="700" fill="#fff">1</text>'
                 f'<text x="{lx + 24}" y="{H - 20}" font-size="12" style="fill:var(--sub)">{e(spec["legend_risk"])}</text>')
    if spec.get("legend_planned"):
        lx2 = W - 28 - 6.5 * len(spec["legend_planned"]) - 40
        o.append(f'<rect x="{lx2}" y="{H - 33}" width="26" height="18" rx="5" fill="none" style="stroke:var(--sub)" stroke-width="1.5" stroke-dasharray="5 4"/>'
                 f'<text x="{lx2 + 34}" y="{H - 20}" font-size="12" style="fill:var(--sub)">{e(spec["legend_planned"])}</text>')
    o.append("</svg>")
    return "\n".join(o)


def badge(cx, cy, n):
    return (f'<circle cx="{cx}" cy="{cy}" r="11" style="fill:var(--risk)"/>'
            f'<text x="{cx}" y="{cy + 4.5}" text-anchor="middle" font-size="13" font-weight="700" fill="#fff">{n}</text>')


# ---------------------------------------------------------------- 1. what runs where
OVERVIEW = dict(
    file="lab-overview.svg", title="What runs where", size=(1300, 900), legend_planned="not built yet",
    sub="One Proxmox host at home, the c1 cluster and its apps, the agent box, and a rented server outside.",
    desc="Blocks: the owner's devices reach a remote-access container, then the firewall VM, then the c1 cluster. GitHub feeds the agent box and Argo CD. The agent box builds the dev cluster and c1. c1 runs Argo CD, Keycloak, OpenBao, Grafana, Jellyfin, Mealie, Home Assistant, ntfy and the Central Hub app, and backs up to the host's backup disk. The VPS app host sits outside the home.",
    groups={
        "host": dict(x=290, y=104, w=990, h=760, label="Proxmox host: one machine, at home"),
        "c1": dict(x=316, y=134, w=150, h=710, label="c1: prod Kubernetes, prod VLAN"),
        "wk": dict(x=590, y=290, w=650, h=490, label="worker node: runs every app"),
    },
    nodes={
        "gh": dict(x=40, y=140, t="GitHub", s="central-hub main|the one record", glyph="branch", kind="git"),
        "owner": dict(x=40, y=380, t="Owner's devices", s="browser, phone", glyph="user"),
        "vps": dict(x=40, y=640, t="VPS app host", s="rented, outside|one user per app", glyph="cloud", kind="ctl", planned=True),
        "box": dict(x=320, y=140, t="Agent box", s="VM|one wrapper per job", glyph="term", kind="ctl"),
        "dev": dict(x=320, y=260, t="Dev cluster", s="dev VLAN|built, then torn down", glyph="wheel"),
        "ct": dict(x=320, y=380, t="Remote access", s="container|subnet router", glyph="lock"),
        "fw": dict(x=320, y=500, t="Firewall", s="OPNsense VM|routes, lab DNS", glyph="wall"),
        "hdd": dict(x=320, y=700, t="Backup disk", s="nightly VM backups|restic snapshots", glyph="disk", kind="data"),
        "cp": dict(x=600, y=170, w=240, t="Control plane", s="VM: API server, etcd", glyph="gear"),
        "argo": dict(x=610, y=330, w=180, h=76, t="Argo CD", s="installs every app", glyph="sync", kind="git"),
        "kc": dict(x=810, y=330, w=180, h=76, t="Keycloak", s="signs people in", glyph="key", kind="id"),
        "bao": dict(x=1010, y=330, w=210, h=76, t="OpenBao", s="secrets store", glyph="lock", kind="id"),
        "gf": dict(x=610, y=430, w=180, h=76, t="Grafana", s="dashboards", glyph="chart"),
        "jf": dict(x=810, y=430, w=180, h=76, t="Jellyfin", s="media", glyph="film"),
        "ml": dict(x=1010, y=430, w=210, h=76, t="Mealie", s="recipes", glyph="bowl"),
        "ha": dict(x=610, y=530, w=180, h=76, t="Home Assistant", s="home", glyph="home"),
        "nt": dict(x=810, y=530, w=180, h=76, t="ntfy", s="alerts to phone", glyph="bell"),
        "hub": dict(x=1010, y=530, w=210, h=76, t="Central Hub app", s="the web app", glyph="doc"),
        "disk": dict(x=610, y=680, w=250, h=76, t="Worker data disk", s="every app's volume", glyph="disk", kind="data"),
    },
    edges=[
        ("gh", "R", "box", "L", "git", "main", {}),
        ("owner", "R", "ct", "L", "net", "private network", {}),
        ("ct", "B", "fw", "T", "net", "", {}),
        ("fw", "R", "wk", "L", "net", "apps", {"via": 550}),
        ("box", "R", "cp", "L", "ctl", "deploys", {"via": 550}),
        ("box", "B", "dev", "T", "ctl", "", {}),
        ("gh", "T", "c1", "T", "git", "Argo CD reads main", {"via": 88}),
        ("box", "L", "vps", "R", "ctl", "", {"oa": 22, "via": 262}),
        ("disk", "L", "hdd", "R", "data", "nightly", {"via": 540}),
    ],
)

# ---------------------------------------------------------------- 2. the whole lab, and where one failure stops a lot
WHOLE = dict(
    file="whole-lab.svg", title="Where one failure stops a lot", size=(1240, 800),
    sub="The lab's connections, with the four parts that have no second copy marked in red and numbered as on the page.",
    desc="The same lab as connected blocks. Four parts are marked as having no second copy: 1 the one Proxmox host, 2 the worker's data disk, 3 the backup HDD in the same machine, 4 c1's single control plane.",
    legend_risk="no second copy today",
    legend_planned="not built yet",
    groups={
        "host": dict(x=290, y=104, w=940, h=660, label="Proxmox host", risk=True, badge=1),
        "prod": dict(x=860, y=134, w=340, h=330, label="c1, prod VLAN"),
        "devv": dict(x=860, y=494, w=340, h=250, label="dev VLAN"),
    },
    nodes={
        "owner": dict(x=40, y=240, t="Owner's devices", s="from anywhere", glyph="user"),
        "gh": dict(x=40, y=520, t="GitHub", s="central-hub main", glyph="branch", kind="git"),
        "vps": dict(x=40, y=660, t="VPS app host", s="outside the home", glyph="cloud", kind="ctl", planned=True),
        "ct": dict(x=320, y=240, t="Remote access", s="container", glyph="lock"),
        "fw": dict(x=580, y=240, t="Firewall", s="OPNsense VM", glyph="wall"),
        "box": dict(x=320, y=520, t="Agent box", s="applies every change", glyph="term", kind="ctl"),
        "hdd": dict(x=580, y=660, t="Backup HDD", s="same machine as the data", glyph="disk", kind="data", risk=True, badge=3),
        "cp": dict(x=880, y=170, w=300, t="c1 control plane", s="one VM: API server, etcd", glyph="gear", risk=True, badge=4),
        "wk": dict(x=880, y=270, w=300, t="c1 worker", s="runs the apps", glyph="wheel"),
        "disk": dict(x=880, y=370, w=300, h=70, t="Worker data disk", s="every app volume", glyph="disk", kind="data", risk=True, badge=2),
        "dev": dict(x=880, y=530, w=300, t="Dev cluster", s="built, filled from backup, torn down", glyph="wheel"),
        "ci": dict(x=880, y=630, w=300, h=90, t="CI runner and desktop", s="two VMs, no lab keys", glyph="term"),
    },
    edges=[
        ("owner", "R", "ct", "L", "net", "tailnet", {}),
        ("ct", "R", "fw", "L", "net", "", {}),
        ("fw", "R", "prod", "L", "net", "to prod", {}),
        ("gh", "R", "box", "L", "git", "", {}),
        ("box", "R", "dev", "L", "ctl", "Proxmox API, Ansible, OpenTofu", {"via": 555, "at": (700, 585)}),
        ("box", "T", "prod", "L", "ctl", "", {"oa": 0, "ob": 130, "via": 480}),
        ("disk", "L", "hdd", "T", "data", "nightly", {"at": (770, 405)}),
        ("box", "B", "vps", "R", "ctl", "", {}),
    ],
)

# ---------------------------------------------------------------- 3. what c1 is made of
C1PARTS = dict(
    file="c1-parts.svg", title="What c1 is made of", size=(1200, 760),
    sub="Two VMs on the Proxmox host. The control plane runs the cluster, the worker runs the apps in pods, grouped by namespace.",
    desc="A person or agent reaches the control plane's API server. The control plane VM holds the API server, etcd, the scheduler, the controller-manager and a kubelet. The worker VM has a kubelet that starts pods in the media, logging and monitoring namespaces, all using the worker's data disk.",
    groups={
        "cpv": dict(x=290, y=104, w=340, h=600, label="Control-plane VM"),
        "wkv": dict(x=690, y=104, w=480, h=600, label="Worker VM"),
        "nsm": dict(x=710, y=290, w=140, h=190, label="media"),
        "nsl": dict(x=860, y=290, w=140, h=190, label="logging"),
        "nso": dict(x=1010, y=290, w=140, h=190, label="monitoring"),
    },
    nodes={
        "you": dict(x=40, y=150, w=200, t="You or an agent", s="kubectl, Argo CD", glyph="user"),
        "api": dict(x=310, y=150, t="API server", s="the front door", glyph="gear"),
        "etcd": dict(x=310, y=250, t="etcd", s="the cluster's memory", glyph="db", kind="data"),
        "sch": dict(x=310, y=350, t="Scheduler", s="picks a node per pod", glyph="stack"),
        "cm": dict(x=310, y=450, t="Controller-manager", s="matches what was asked", glyph="sync"),
        "kcp": dict(x=310, y=550, t="kubelet + containerd", s="control plane's own pods", glyph="box"),
        "kw": dict(x=710, y=150, w=440, t="kubelet + containerd", s="start and watch the pods", glyph="box"),
        "j": dict(x=718, y=330, w=124, h=130, t="Jellyfin", s="pod", glyph="film"),
        "l": dict(x=868, y=330, w=124, h=130, t="Loki", s="pod", glyph="doc"),
        "g": dict(x=1018, y=330, w=124, h=130, t="Grafana", s="pod", glyph="chart"),
        "disk": dict(x=710, y=540, w=440, t="Data disk", s="a plain folder per volume", glyph="disk", kind="data"),
    },
    edges=[
        ("you", "R", "api", "L", "ctl", "", {}),
        ("etcd", "T", "api", "B", "net", "", {}),
        ("sch", "L", "api", "L", "ctl", "", {"via": 298}),
        ("cm", "L", "api", "L", "ctl", "", {"via": 298}),
        ("kcp", "L", "api", "L", "ctl", "", {"via": 298}),
        ("kw", "L", "api", "R", "net", "watches", {}),
        ("kw", "B", "j", "T", "net", "", {"ob": 0, "via": 270}),
        ("kw", "B", "l", "T", "net", "", {"via": 270}),
        ("kw", "B", "g", "T", "net", "", {"via": 270}),
        ("j", "B", "disk", "T", "data", "", {"ob": -150, "via": 500}),
        ("l", "B", "disk", "T", "data", "", {"ob": 0, "via": 500}),
        ("g", "B", "disk", "T", "data", "", {"ob": 150, "via": 500}),
    ],
)

# ---------------------------------------------------------------- 4. how c1 keeps its data
DATA = dict(
    file="c1-data.svg", title="How c1 keeps its data", size=(1220, 720),
    sub="An app asks for a volume. The volume is a plain folder on the worker's data disk. Copies are the backups.",
    desc="The Proxmox VM disk is formatted ext4 and mounted on the worker VM, where each volume is a folder. In Kubernetes a pod mounts a claim; the default StorageClass local-path and the Local Path Provisioner make the folder and bind a volume to the claim. Backups of the VM and restic snapshots protect the folders.",
    groups={
        "px": dict(x=30, y=104, w=250, h=270, label="Proxmox host"),
        "wkv": dict(x=310, y=104, w=380, h=370, label="Worker VM"),
        "k8s": dict(x=720, y=104, w=470, h=370, label="Kubernetes objects"),
    },
    nodes={
        "vd": dict(x=50, y=180, w=210, t="VM disk", s="the worker's data disk", glyph="disk", kind="data"),
        "fs": dict(x=330, y=150, w=340, t="ext4 filesystem", s="mounted as the c1 data folder", glyph="folder", kind="data"),
        "f1": dict(x=330, y=300, w=176, t="Folder", s="monitoring/grafana", glyph="folder", kind="data"),
        "f2": dict(x=520, y=300, w=150, t="Folder", s="media/config", glyph="folder", kind="data"),
        "pod": dict(x=740, y=150, w=200, t="Pod", s="mounts the claim", glyph="box"),
        "pvc": dict(x=740, y=260, w=200, t="Claim (PVC)", s="'I need 10 GiB'", glyph="doc"),
        "pv": dict(x=740, y=370, w=200, t="Volume (PV)", s="bound to the claim", glyph="disk", kind="data"),
        "sc": dict(x=960, y=260, w=210, t="StorageClass", s="local-path, the default|keeps the folder (Retain)", glyph="stack"),
        "prov": dict(x=960, y=370, w=210, t="Provisioner", s="Local Path: a folder|for each new claim", glyph="gear"),
        "bk": dict(x=330, y=570, w=520, t="Backups", s="nightly Proxmox backup of the VM|restic snapshots of every folder, weekly restore test", glyph="db", kind="data"),
    },
    edges=[
        ("vd", "R", "fs", "L", "data", "", {}),
        ("fs", "B", "f1", "T", "data", "", {}),
        ("fs", "B", "f2", "T", "data", "", {}),
        ("pod", "B", "pvc", "T", "net", "mounts", {}),
        ("pvc", "B", "pv", "T", "net", "bound", {}),
        ("pvc", "R", "sc", "L", "net", "", {}),
        ("sc", "B", "prov", "T", "net", "", {}),
        ("prov", "L", "pv", "R", "net", "makes", {}),
        ("pv", "L", "f2", "R", "data", "is a folder", {"via": 705, "at": (705, 366)}),
        ("f1", "B", "bk", "T", "data", "", {"ob": -120}),
        ("f2", "B", "bk", "T", "data", "", {"ob": 20}),
    ],
)

# ---------------------------------------------------------------- 5. Argo CD and Ansible
ARGO = dict(
    file="argo-ansible.svg", title="When Argo CD takes over from Ansible", size=(1240, 880),
    sub="A c1 build runs in three parts: Ansible builds what Argo CD stands on, Argo CD installs every app, Ansible finishes from outside.",
    desc="Part 1, Ansible and OpenTofu: vms, cluster, storage, gitops. Part 2, Argo CD: the root Application, one child Application per app, auto-sync. Part 3, Ansible: gateway, certs, identity, ui, checks. Below, an app moves from an Ansible role to Argo CD in five steps.",
    groups={
        "p1": dict(x=30, y=104, w=360, h=420, label="1. Ansible and OpenTofu build the base"),
        "p2": dict(x=440, y=104, w=360, h=420, label="2. Argo CD installs and keeps every app"),
        "p3": dict(x=850, y=104, w=360, h=520, label="3. Ansible finishes from outside"),
        "mv": dict(x=30, y=664, w=1180, h=150, label="How one app moves from Ansible to Argo CD"),
    },
    nodes={
        "vms": dict(x=50, y=140, w=320, h=68, t="vms", s="OpenTofu makes the node VMs", glyph="stack", kind="ctl"),
        "cl": dict(x=50, y=236, w=320, h=68, t="cluster", s="kubeadm, Cilium, nodes join", glyph="wheel", kind="ctl"),
        "st": dict(x=50, y=332, w=320, h=68, t="storage", s="format and mount the data disk", glyph="disk", kind="ctl"),
        "go": dict(x=50, y=428, w=320, h=68, t="gitops", s="install Argo CD, make root app c1", glyph="sync", kind="ctl"),
        "root": dict(x=460, y=140, w=320, h=76, t="Root Application c1", s="reads the c1 folder on main", glyph="branch", kind="git"),
        "kids": dict(x=460, y=250, w=320, h=96, t="One child per app", s="local-path, cert-manager, gateway,|monitoring, logging, alerts, Jellyfin...", glyph="box", kind="git"),
        "sync": dict(x=460, y=380, w=320, h=76, t="Auto-sync", s="each app is put back to what git says", glyph="sync", kind="git"),
        "gw": dict(x=870, y=140, w=320, h=68, t="gateway", s="checks the Gateway answers", glyph="wall", kind="ctl"),
        "ce": dict(x=870, y=236, w=320, h=68, t="certs", s="the lab certificates", glyph="badge", kind="ctl"),
        "id": dict(x=870, y=332, w=320, h=68, t="identity", s="Keycloak", glyph="key", kind="ctl"),
        "ui": dict(x=870, y=428, w=320, h=68, t="ui", s="Argo CD's web page and sign-in", glyph="term", kind="ctl"),
        "ck": dict(x=870, y=524, w=320, h=68, t="checks", s="the run's final checks", glyph="gear", kind="ctl"),
        "m1": dict(x=50, y=704, w=200, h=84, t="Ansible role", s="applies the app", glyph="term", kind="ctl"),
        "m2": dict(x=290, y=704, w=220, h=84, t="Written in git", s="hosts/kubernetes/home/c1/apps", glyph="doc", kind="git"),
        "m3": dict(x=550, y=704, w=220, h=84, t="Synced once by hand", s="diff shows only labels", glyph="sync", kind="git"),
        "m4": dict(x=810, y=704, w=170, h=84, t="Auto-sync on", s="", glyph="sync", kind="git"),
        "m5": dict(x=1020, y=704, w=170, h=84, t="Role switch on", s="*_by_argocd = true", glyph="lock", kind="ctl"),
    },
    edges=[
        ("vms", "B", "cl", "T", "ctl", "", {}), ("cl", "B", "st", "T", "ctl", "", {}), ("st", "B", "go", "T", "ctl", "", {}),
        ("root", "B", "kids", "T", "git", "", {}), ("kids", "B", "sync", "T", "git", "", {}),
        ("gw", "B", "ce", "T", "ctl", "", {}), ("ce", "B", "id", "T", "ctl", "", {}), ("id", "B", "ui", "T", "ctl", "", {}), ("ui", "B", "ck", "T", "ctl", "", {}),
        ("go", "R", "root", "L", "ctl", "Argo CD is up", {"via": 415}),
        ("sync", "R", "gw", "L", "git", "apps are in", {"via": 825}),
        ("m1", "R", "m2", "L", "ctl", "", {}), ("m2", "R", "m3", "L", "git", "", {}), ("m3", "R", "m4", "L", "git", "", {}), ("m4", "R", "m5", "L", "git", "", {}),
    ],
)

# ---------------------------------------------------------------- 6. Keycloak realms
KC = dict(
    file="keycloak-realms.svg", title="How Keycloak's realms are laid out", size=(1200, 640),
    sub="Each environment has its own Keycloak. Each has one realm for people and apps, with a client for every app.",
    desc="Prod's Keycloak has a master realm for break-glass admin and the lab realm with users, the groups lab-admins and lab-viewers, and clients for Grafana, Argo CD, Jellyfin, Proxmox, OPNsense, OpenBao, the Central Hub app, Mealie and Home Assistant. Dev's Keycloak has its own master and lab realm. Nothing is shared between them.",
    groups={
        "prod": dict(x=30, y=104, w=780, h=490, label="prod: c1 and its Keycloak"),
        "rl": dict(x=300, y=134, w=490, h=440, label="realm lab (becomes home): one sign-in for every app"),
        "dev": dict(x=850, y=104, w=320, h=490, label="dev: its own cluster and Keycloak"),
        "rd": dict(x=870, y=270, w=280, h=300, label="realm lab (becomes home)"),
    },
    nodes={
        "pm": dict(x=50, y=160, w=220, h=84, t="master realm", s="Keycloak's own admin|break-glass only", glyph="lock", kind="id"),
        "pu": dict(x=320, y=170, w=450, h=76, t="Users and groups", s="lab-admins, lab-viewers|one-time-code seed for each admin", glyph="user", kind="id"),
        "c1": dict(x=316, y=276, w=150, h=64, t="Grafana", s="", glyph="chart", kind="id"),
        "c2": dict(x=474, y=276, w=150, h=64, t="Argo CD", s="and its CLI", glyph="sync", kind="id"),
        "c3": dict(x=632, y=276, w=150, h=64, t="Jellyfin", s="", glyph="film", kind="id"),
        "c4": dict(x=316, y=366, w=150, h=64, t="Proxmox", s="", glyph="stack", kind="id"),
        "c5": dict(x=474, y=366, w=150, h=64, t="OPNsense", s="", glyph="wall", kind="id"),
        "c6": dict(x=632, y=366, w=150, h=64, t="OpenBao", s="", glyph="lock", kind="id"),
        "c7": dict(x=316, y=456, w=150, h=64, t="Central Hub", s="the web app", glyph="doc", kind="id"),
        "c8": dict(x=474, y=456, w=150, h=64, t="Mealie", s="", glyph="bowl", kind="id"),
        "c9": dict(x=632, y=456, w=150, h=64, t="Home Assistant", s="", glyph="home", kind="id"),
        "dm": dict(x=870, y=150, w=280, h=84, t="master realm", s="break-glass only", glyph="lock", kind="id"),
        "du": dict(x=890, y=310, w=240, h=100, t="Dev users", s="its own identity.env|and its own secrets", glyph="user", kind="id"),
    },
    edges=[
        ("prod", "R", "dev", "L", "gap", "none shared", {}),
    ],
)

FIGURES = [OVERVIEW, WHOLE, C1PARTS, DATA, ARGO, KC]

if __name__ == "__main__":
    for spec in FIGURES:
        with open(os.path.join(OUT, spec["file"]), "w") as f:
            f.write(draw(spec))
        print("wrote", spec["file"])
