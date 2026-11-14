#!/usr/bin/env python3
"""Static route index for the Laravel API (read-only, stdlib only, never boots the app).

Parses apps/xorder-cloud/apps/api/routes/{api,web}.php: nested Route::prefix/middleware groups, route verbs,
apiResource/resource, controller aliases. Prints a markdown table (method, full path, middleware stack,
controller@method, routes file:line). Middleware is the literal strings found in the chain; computed
expressions such as 'role:'.implode(...) appear as their literal parts only.
Usage: python3 -I scripts/harness/route-index.py [--check-count]
"""
import re, sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
api_dir = root / "apps/xorder-cloud/apps/api"
VERBS = ("get", "post", "put", "patch", "delete", "options", "any", "match", "apiResource", "resource")


def strip_comments(src):
    out, i, n, q = [], 0, len(src), None
    while i < n:
        c = src[i]
        if q:
            out.append(c)
            if c == "\\":
                out.append(src[i + 1]); i += 2; continue
            if c == q:
                q = None
            i += 1; continue
        if c in "'\"":
            q = c; out.append(c); i += 1; continue
        if src.startswith("//", i) or c == "#":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            seg = src[i: (j + 2 if j != -1 else n)]
            out.append("\n" * seg.count("\n"))
            i = (j + 2) if j != -1 else n
            continue
        out.append(c); i += 1
    return "".join(out)


def split_statements(src):
    """Yield (text, start_line, kind) where kind is 'stmt' (ends with ;), 'open' (group closure) or 'close'."""
    buf, start, line, i, n, q, depth_paren = [], None, 1, 0, len(src), None, 0
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
        if q:
            buf.append(c)
            if c == "\\":
                buf.append(src[i + 1]); i += 2; continue
            if c == q:
                q = None
            i += 1; continue
        if c in "'\"":
            q = c
            if start is None: start = line
            buf.append(c); i += 1; continue
        if c == "{":
            text = "".join(buf)
            if re.search(r"function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?$", text.rstrip()):
                yield text.strip(), start or line, "open"
                buf, start = [], None
                i += 1; continue
        if c == "}":
            if not "".join(buf).strip() or "".join(buf).strip().startswith(")"):
                yield "}", line, "close"
                buf, start = [], None
                # swallow trailing ');'
                j = i + 1
                while j < n and src[j] in " \t\r\n)":
                    if src[j] == "\n": line += 1
                    j += 1
                if j < n and src[j] == ";":
                    j += 1
                i = j; continue
        if c == ";":
            text = "".join(buf)
            if text.strip():
                yield text.strip(), start or line, "stmt"
            buf, start = [], None
            i += 1; continue
        if not c.isspace() and start is None:
            start = line
        buf.append(c); i += 1


def balanced(text, open_idx):
    depth, q, i = 0, None, open_idx
    while i < len(text):
        c = text[i]
        if q:
            if c == "\\": i += 2; continue
            if c == q: q = None
        elif c in "'\"": q = c
        elif c == "(": depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[open_idx + 1:i], i
        i += 1
    return text[open_idx + 1:], len(text)


def calls(text):
    """Return list of (name, args) for ->name(args) / Route::name(args) calls in a chain."""
    out = []
    for m in re.finditer(r"(?:Route::|->)\s*([A-Za-z_]+)\s*\(", text):
        args, _ = balanced(text, m.end() - 1)
        out.append((m.group(1), args, m.start()))
    return out


def strings(args):
    return re.findall(r"'([^']*)'|\"([^\"]*)\"", args)


def lits(args):
    return [a or b for a, b in strings(args)]


def parse(path, aliases):
    src = strip_comments(path.read_text())
    stack = [{"prefix": "", "mw": []}]
    rows = []
    for text, ln, kind in split_statements(src):
        if kind == "close":
            if len(stack) > 1:
                stack.pop()
            continue
        if not text.startswith("Route::") and "Route::" not in text:
            continue
        cs = calls(text)
        ctx = {"prefix": stack[-1]["prefix"], "mw": list(stack[-1]["mw"])}
        controller_default = None
        terminal = None
        for name, args, _ in cs:
            if name == "prefix":
                v = (lits(args) or [""])[0].strip("/")
                if v:
                    ctx["prefix"] = (ctx["prefix"] + "/" + v).strip("/")
            elif name in ("middleware", "withoutMiddleware"):
                if name == "middleware":
                    ctx["mw"] += lits(re.sub(r"'role:'\s*\.\s*implode\([^()]*\([^()]*\)\)", "'role:<computed>'", args))
            elif name == "controller":
                controller_default = re.findall(r"([A-Za-z_\\]+)::class", args)
            elif name in VERBS or name == "group":
                terminal = (name, args)
        if kind == "open":
            stack.append(ctx)
            continue
        if not terminal or terminal[0] == "group":
            continue
        verb, args = terminal
        ls = lits(args)
        if verb == "match":
            methods = [m.upper() for m in re.findall(r"'([a-z]+)'", args.split("]")[0])]
            uri = ls[len(methods)] if len(ls) > len(methods) else ""
        else:
            methods = [verb.upper()]
            uri = ls[0] if ls else ""
        ctrl = re.findall(r"([A-Za-z_\\]+)::class", args)
        method_name = re.findall(r"::class\s*,\s*'([A-Za-z_]+)'", args)
        target = ""
        c0 = ctrl[0] if ctrl else (controller_default[0] if controller_default else "")
        if c0:
            full = aliases.get(c0, c0)
            target = full.replace("App\\Http\\Controllers\\", "") + ("@" + method_name[0] if method_name else "")
        full_path = ("/" + (ctx["prefix"] + "/" + uri.strip("/")).strip("/")) if path.name == "web.php" else "/api/" + (ctx["prefix"] + "/" + uri.strip("/")).strip("/")
        full_path = full_path.rstrip("/") or "/"
        if verb in ("apiResource", "resource"):
            only = re.findall(r"->only\(\[([^\]]*)\]\)", text)
            only = re.findall(r"'([a-z]+)'", only[0]) if only else None
            for act, mth, suffix in (("index", "GET", ""), ("store", "POST", ""), ("show", "GET", "/{id}"), ("update", "PUT|PATCH", "/{id}"), ("destroy", "DELETE", "/{id}")):
                if only is None or act in only:
                    rows.append((mth, full_path + suffix, ctx["mw"], target.split("@")[0] + "@" + act, f"{path.name}:{ln}"))
        else:
            for m in methods:
                rows.append((m, full_path, ctx["mw"], target, f"{path.name}:{ln}"))
    return rows


def main():
    aliases = {}
    for fn in ("api.php", "web.php"):
        for m in re.finditer(r"^use\s+([A-Za-z0-9_\\]+?)(?:\s+as\s+([A-Za-z0-9_]+))?;", (api_dir / "routes" / fn).read_text(), re.M):
            full, alias = m.group(1), m.group(2)
            aliases[alias or full.split("\\")[-1]] = full
    rows = parse(api_dir / "routes/api.php", aliases) + parse(api_dir / "routes/web.php", aliases)
    if "--check-count" in sys.argv:
        src = strip_comments((api_dir / "routes/api.php").read_text() + (api_dir / "routes/web.php").read_text())
        stmts = len(re.findall(r"Route::[A-Za-z]+\(|->(?:get|post|put|patch|delete|apiResource|resource)\(", src))
        print(f"parsed rows: {len(rows)}; route-verb call sites in source (rough): {stmts}")
        return
    print("| Method | Path | Middleware | Controller@method | Source |")
    print("| --- | --- | --- | --- | --- |")
    for mth, p, mw, tgt, src in rows:
        print(f"| {mth} | `{p}` | {', '.join('`' + x.replace('|', chr(92) + '|') + '`' for x in mw) or '-'} | `{tgt or '-'}` | `{src}` |")


main()
