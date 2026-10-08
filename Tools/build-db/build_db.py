#!/usr/bin/env python3
"""Builds Data/characters.json for Typecase from the Unicode Character Database.

Sources (downloaded once into --cache):
  * unicodetools data   UnicodeData, NamesList, NameAliases, emoji-data, Blocks, Scripts, DerivedAge
  * security            confusables.txt
  * CLDR JSON           annotations (+ derived) for en, nl, de, fr, es
  * synonyms.txt        hand curated search terms (this directory)

Policy
  * No emoji: anything with Emoji_Presentation, emoji modifiers, regional indicators, tags, or a
    pictographic character in the supplementary pictograph planes (>= U+1F000) is dropped.
    Text-style symbols such as (c), TM, arrows and hearts (U+2665) stay.
  * Space/format characters, combining marks and variation selectors stay.
  * CJK ideographs, Hangul syllables and other algorithmically named ranges are not included
    (they have no names to search for).
  * Characters newer than --max-age are dropped; macOS fonts do not have them yet.

Usage:  python3 Tools/build-db/build_db.py --cache /tmp/ucd-cache --out Data/characters.json
"""
import argparse
import html.entities
import json
import os
import re
import sys
import urllib.request
from collections import defaultdict

UCD = "https://raw.githubusercontent.com/unicode-org/unicodetools/main/unicodetools/data"
FILES = {
    "UnicodeData.txt": UCD + "/ucd/dev/UnicodeData.txt",
    "NamesList.txt": UCD + "/ucd/dev/NamesList.txt",
    "NameAliases.txt": UCD + "/ucd/dev/NameAliases.txt",
    "emoji-data.txt": UCD + "/ucd/dev/emoji/emoji-data.txt",
    "Blocks.txt": UCD + "/ucd/dev/Blocks.txt",
    "Scripts.txt": UCD + "/ucd/dev/Scripts.txt",
    "DerivedAge.txt": UCD + "/ucd/dev/DerivedAge.txt",
    "confusables.txt": UCD + "/security/dev/confusables.txt",
}
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json"
LANGS = ["en", "nl", "de", "fr", "es"]
for _l in LANGS:
    FILES[f"ann_{_l}.json"] = f"{CLDR}/cldr-annotations-full/annotations/{_l}/annotations.json"
    FILES[f"annd_{_l}.json"] = f"{CLDR}/cldr-annotations-derived-full/annotationsDerived/{_l}/annotations.json"

HERE = os.path.dirname(os.path.abspath(__file__))


def fetch(cache):
    os.makedirs(cache, exist_ok=True)
    for name, url in FILES.items():
        path = os.path.join(cache, name)
        if not os.path.exists(path) or os.path.getsize(path) == 0:
            print("fetching", name, file=sys.stderr)
            with urllib.request.urlopen(url, timeout=120) as r, open(path, "wb") as f:
                f.write(r.read())


def read(cache, name):
    with open(os.path.join(cache, name), encoding="utf-8") as f:
        return f.read()


def parse_ranges(text, with_value=True):
    """Parse 'XXXX..YYYY ; value # comment' style files into (lo, hi, value)."""
    out = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(";")]
        rng = parts[0]
        if ".." in rng:
            lo, hi = rng.split("..")
        else:
            lo = hi = rng
        out.append((int(lo, 16), int(hi, 16), parts[1] if with_value and len(parts) > 1 else None))
    return out


def range_lookup(ranges):
    """Expand to a dict cp -> value (only used for modest sizes)."""
    d = {}
    for lo, hi, v in ranges:
        for cp in range(lo, hi + 1):
            d[cp] = v
    return d


def version_tuple(s):
    parts = s.split(".")
    return (int(parts[0]), int(parts[1]) if len(parts) > 1 else 0)


def norm_term(t):
    return re.sub(r"\s+", " ", t.strip().lower())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default="/tmp/ucd-cache")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "Data", "characters.json"))
    ap.add_argument("--max-age", default="16.0")
    args = ap.parse_args()
    max_age = version_tuple(args.max_age)
    fetch(args.cache)

    # ---------------- UnicodeData -------------------------------------------
    unidata = {}
    for line in read(args.cache, "UnicodeData.txt").splitlines():
        f = line.split(";")
        name = f[1]
        if name.endswith(", First>") or name.endswith(", Last>"):
            continue  # algorithmic ranges: CJK, Hangul, PUA, surrogates ...
        unidata[int(f[0], 16)] = {"name": name, "gc": f[2], "decomp": f[5]}

    # ---------------- blocks, scripts, ages ---------------------------------
    blocks_raw = parse_ranges(read(args.cache, "Blocks.txt"))
    block_names = [b[2] for b in blocks_raw]
    block_of = {}
    for i, (lo, hi, _) in enumerate(blocks_raw):
        for cp in range(lo, hi + 1):
            if cp in unidata:
                block_of[cp] = i
    scripts_raw = parse_ranges(read(args.cache, "Scripts.txt"))
    script_names = sorted({s[2].replace("_", " ") for s in scripts_raw})
    script_index = {n: i for i, n in enumerate(script_names)}
    script_of = {}
    for lo, hi, v in scripts_raw:
        for cp in range(lo, hi + 1):
            if cp in unidata:
                script_of[cp] = script_index[v.replace("_", " ")]
    ages = parse_ranges(read(args.cache, "DerivedAge.txt"))
    age_of = {}
    for lo, hi, v in ages:
        for cp in range(lo, hi + 1):
            if cp in unidata:
                age_of[cp] = v
    age_names = sorted({v for v in age_of.values()}, key=version_tuple)
    age_index = {n: i for i, n in enumerate(age_names)}

    # ---------------- emoji -------------------------------------------------
    emoji_props = defaultdict(set)
    for lo, hi, prop in parse_ranges(read(args.cache, "emoji-data.txt")):
        for cp in range(lo, hi + 1):
            emoji_props[cp].add(prop)

    def is_emoji_like(cp):
        p = emoji_props.get(cp, ())
        if "Emoji_Presentation" in p or "Emoji_Modifier" in p:
            return True
        if "Extended_Pictographic" in p and cp >= 0x1F000:
            return True
        if 0xE0000 <= cp <= 0xE007F:  # tag characters (flag sequences)
            return True
        return False

    # ---------------- NameAliases -------------------------------------------
    aliases = defaultdict(list)
    control_names = {}
    for line in read(args.cache, "NameAliases.txt").splitlines():
        if not line or line.startswith("#"):
            continue
        cp_s, alias, kind = line.split(";")[:3]
        cp = int(cp_s, 16)
        kind = kind.strip().split("#")[0].strip()
        if kind == "control" and cp not in control_names:
            control_names[cp] = alias
        aliases[cp].append(alias)

    # ---------------- NamesList ---------------------------------------------
    xrefs = defaultdict(list)
    decomp_single = {}  # cp -> target cp (compat/canonical singleton)
    decomp_seq = {}  # cp -> [cps]
    notes = defaultdict(list)
    cur = None
    for line in read(args.cache, "NamesList.txt").splitlines():
        if not line or line[0] in "@;":
            if line.startswith("@@") or line.startswith("@\t"):
                cur = None
            continue
        if line[0] != "\t":
            m = re.match(r"^([0-9A-F]{4,6})\t(.*)$", line)
            cur = int(m.group(1), 16) if m else None
            continue
        if cur is None:
            continue
        body = line[1:]
        if body.startswith("= "):
            aliases[cur].append(body[2:].strip())
        elif body.startswith("* "):
            note = body[2:].strip()
            if not note.startswith("("):
                notes[cur].append(note)
        elif body.startswith("x "):
            m = re.search(r"([0-9A-F]{4,6})\)?\s*$", body)
            if m:
                xrefs[cur].append(int(m.group(1), 16))
        elif body.startswith(": ") or body.startswith("# "):
            nums = re.findall(r"(?<![<A-Za-z])\b([0-9A-F]{4,6})\b", re.sub(r"<[^>]*>", "", body[2:]))
            seq = [int(n, 16) for n in nums]
            # '# 0020 space' style lines carry a trailing name; keep only the leading code points
            m = re.match(r"^[#:]\s*(?:<[^>]*>\s*)?((?:[0-9A-F]{4,6}\s*)+)", body)
            if m:
                seq = [int(n, 16) for n in m.group(1).split()]
            if seq:
                decomp_seq.setdefault(cur, seq)
                if len(seq) == 1:
                    decomp_single[cur] = seq[0]

    # ---------------- confusables -------------------------------------------
    conf_groups = defaultdict(list)
    for line in read(args.cache, "confusables.txt").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(";")]
        if len(parts) < 3:
            continue
        src = parts[0].replace("﻿", "")
        tgt = tuple(int(x, 16) for x in parts[1].split())
        conf_groups[tgt].append(int(src, 16))
    for tgt, members in conf_groups.items():
        if len(tgt) == 1:
            members.append(tgt[0])

    # ---------------- CLDR keywords -----------------------------------------
    cldr = defaultdict(list)
    for lang in LANGS:
        for fname, getter in ((f"ann_{lang}.json", lambda d: d["annotations"]["annotations"]),
                              (f"annd_{lang}.json", lambda d: d["annotationsDerived"]["annotations"])):
            data = getter(json.loads(read(args.cache, fname)))
            for key, val in data.items():
                scalars = [ord(c) for c in key if ord(c) not in (0xFE0F, 0xFE0E)]
                if len(scalars) != 1:
                    continue
                for w in val.get("default", []) + val.get("tts", []):
                    cldr[scalars[0]].append(w)

    # ---------------- synonyms ----------------------------------------------
    synonyms = defaultdict(list)
    syn_path = os.path.join(HERE, "synonyms.txt")
    with open(syn_path, encoding="utf-8") as f:
        for ln, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "|" not in line:
                sys.exit(f"synonyms.txt:{ln}: missing '|'")
            left, right = line.split("|", 1)
            terms = [t.strip() for t in right.split(";") if t.strip()]
            for tok in re.split(r"[\s,]+", left.strip()):
                if not tok:
                    continue
                tok = tok.upper().replace("U+", "")
                if "-" in tok:
                    lo, hi = tok.split("-")
                    cps = range(int(lo, 16), int(hi, 16) + 1)
                else:
                    cps = [int(tok, 16)]
                for cp in cps:
                    synonyms[cp].extend(terms)

    # ---------------- HTML entities + legacy encodings ----------------------
    entities = {}
    for name, val in html.entities.html5.items():
        if not name.endswith(";") or len(val) != 1:
            continue
        cp = ord(val)
        nm = name[:-1]
        cur_best = entities.get(cp)
        if cur_best is None or (len(nm), nm) < (len(cur_best), cur_best):
            entities[cp] = nm
    # prefer the classic lowercase spelling when both exist (e.g. 'amp' over 'AMP')
    for name, val in html.entities.html5.items():
        if name.endswith(";") and len(val) == 1 and name[:-1].islower() and name[:-1] in html.entities.name2codepoint:
            entities[ord(val)] = name[:-1]

    legacy = {"macRoman": {}, "windows1252": {}}
    for b in range(0x80, 0x100):
        for key, codec in (("macRoman", "mac_roman"), ("windows1252", "cp1252")):
            try:
                ch = bytes([b]).decode(codec)
            except UnicodeDecodeError:
                continue
            if len(ch) == 1:
                legacy[key][ord(ch)] = b

    # ---------------- which characters are included -------------------------
    ALGO_NAME = re.compile(r"-[0-9A-F]{4,6}$")  # CJK compatibility ideographs, Nushu, Khitan ...

    def include(cp):
        info = unidata[cp]
        gc = info["gc"]
        if gc in ("Cn", "Cs", "Co"):
            return False
        if ALGO_NAME.search(info["name"]):
            return False
        if is_emoji_like(cp):
            return False
        age = age_of.get(cp)
        if age is None or version_tuple(age) > max_age:
            return False
        return True

    included = sorted(cp for cp in unidata if include(cp))
    inc = set(included)

    # Apple logo: private use, but typed by Option-Shift-K on every Mac.
    APPLE = 0xF8FF
    extra = {APPLE: {"name": "APPLE LOGO", "gc": "So", "decomp": ""}}
    for cp, info in extra.items():
        unidata[cp] = info
        block_of[cp] = block_of.get(cp, next((i for i, b in enumerate(blocks_raw) if b[0] <= cp <= b[1]), 0))
        script_of[cp] = script_index["Common"]
        age_of[cp] = "6.0"
        included.append(cp)
        inc.add(cp)
    included.sort()
    synonyms[APPLE] += []  # make sure the synonym exists in the file

    # ---------------- priority class ----------------------------------------
    COMMON_BLOCKS = {
        "Basic Latin", "Latin-1 Supplement", "Latin Extended-A", "Latin Extended-B", "IPA Extensions",
        "Spacing Modifier Letters", "Combining Diacritical Marks", "Greek and Coptic", "Cyrillic",
        "General Punctuation", "Superscripts and Subscripts", "Currency Symbols",
        "Combining Diacritical Marks for Symbols", "Letterlike Symbols", "Number Forms", "Arrows",
        "Mathematical Operators", "Miscellaneous Technical", "Control Pictures",
        "Optical Character Recognition", "Box Drawing", "Block Elements", "Geometric Shapes",
        "Miscellaneous Symbols", "Dingbats", "Miscellaneous Mathematical Symbols-A",
        "Miscellaneous Mathematical Symbols-B", "Supplemental Arrows-A", "Supplemental Arrows-B",
        "Supplemental Mathematical Operators", "Supplemental Punctuation", "Latin Extended Additional",
        "CJK Symbols and Punctuation", "Halfwidth and Fullwidth Forms", "Specials",
        "Enclosed Alphanumerics", "Latin Extended-C", "Latin Extended-D", "Latin Extended-E",
        "Phonetic Extensions", "Miscellaneous Symbols and Arrows", "Alphabetic Presentation Forms",
        "Private Use Area", "General Punctuation", "Latin Extended-F", "Latin Extended-G",
        "Geometric Shapes Extended", "Supplemental Symbols and Pictographs",
    }
    LIVING = {
        "Latin", "Greek", "Cyrillic", "Arabic", "Hebrew", "Devanagari", "Bengali", "Gurmukhi", "Gujarati",
        "Tamil", "Telugu", "Kannada", "Malayalam", "Sinhala", "Thai", "Lao", "Tibetan", "Myanmar",
        "Georgian", "Armenian", "Hangul", "Hiragana", "Katakana", "Bopomofo", "Khmer", "Mongolian",
        "Ethiopic", "Thaana", "Syriac", "Han", "Common", "Inherited", "Oriya",
    }

    def priority(cp):
        b = block_names[block_of[cp]]
        if b in COMMON_BLOCKS or cp in synonyms:
            return 0
        s = script_names[script_of[cp]]
        if s in LIVING:
            return 1
        return 2

    # ---------------- display names -----------------------------------------
    def display_name(cp):
        n = unidata[cp]["name"]
        if n == "<control>":
            return control_names.get(cp, f"CONTROL-{cp:04X}")
        return n

    # ---------------- related -----------------------------------------------
    composed_by_base = defaultdict(list)
    for cp, seq in decomp_seq.items():
        if cp in inc and len(seq) >= 2 and seq[0] in inc:
            composed_by_base[seq[0]].append(cp)

    reverse_single = defaultdict(list)
    for cp, tgt in decomp_single.items():
        reverse_single[tgt].append(cp)

    conf_index = defaultdict(list)
    for tgt, members in conf_groups.items():
        for m in members:
            conf_index[m].append(members)

    def related(cp):
        out = []

        def add(x):
            if x != cp and x in inc and x not in out:
                out.append(x)

        for x in xrefs.get(cp, []):
            add(x)
        if cp in decomp_single:
            add(decomp_single[cp])
        for x in reverse_single.get(cp, []):
            add(x)
        n = 0
        for group in conf_index.get(cp, []):
            for x in group:
                if x != cp and x in inc and x not in out and n < 8 and priority(x) <= 1:
                    out.append(x)
                    n += 1
        seq = decomp_seq.get(cp)
        if seq and len(seq) >= 2:
            add(seq[0])
        for x in composed_by_base.get(cp, [])[:14]:
            add(x)
        return out[:30]

    # ---------------- collections -------------------------------------------
    def block_range(name):
        for lo, hi, n in blocks_raw:
            if n == name:
                return range(lo, hi + 1)
        sys.exit("unknown block " + name)

    def spans(cps):
        cps = sorted(cps)
        out = []
        for cp in cps:
            if out and cp == out[-1][1] + 1:
                out[-1][1] = cp
            else:
                out.append([cp, cp])
        return out

    def by_gc(*gcs):
        return {cp for cp in included if unidata[cp]["gc"] in gcs}

    def in_blocks(*names):
        s = set()
        for n in names:
            s |= {cp for cp in block_range(n) if cp in inc}
        return s

    def name_has(*words):
        return {cp for cp in included if any(w in unidata[cp]["name"] for w in words)}

    spaces = by_gc("Zs") | {0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD, 0x034F, 0x180E, 0x200E, 0x200F,
                            0x2028, 0x2029, 0x2800, 0x3164, 0x115F, 0x1160, 0xFFA0, 0x17B4, 0x17B5, 0x2423,
                            0x2420, 0x0009, 0x000A, 0x000D} | set(range(0x202A, 0x202F)) | set(range(0x2061, 0x2065)) \
        | set(range(0x2066, 0x206A))
    typography = {0x00A7, 0x00B6, 0x00A9, 0x00AE, 0x2122, 0x2020, 0x2021, 0x2022, 0x2023, 0x2030, 0x2031,
                  0x2032, 0x2033, 0x2034, 0x203B, 0x2042, 0x2116, 0x2117, 0x2120, 0x00B0, 0x00B1, 0x00D7,
                  0x00F7, 0x2026, 0x00B7, 0x00A1, 0x00BF, 0x203D, 0x2E18, 0x2013, 0x2014, 0x2018, 0x2019,
                  0x201C, 0x201D, 0x00AB, 0x00BB, 0x2039, 0x203A, 0x2044, 0x2052, 0x2051, 0x204B}
    keyboard = {0x2318, 0x2325, 0x21E7, 0x2303, 0x238B, 0x232B, 0x2326, 0x23CE, 0x21E5, 0x21E4, 0x21EA,
                0x2324, 0x2388, 0x23CF, 0x2387, APPLE, 0x21A9, 0x2190, 0x2191, 0x2192, 0x2193}
    scripts_super = {cp for cp in included if "SUPERSCRIPT" in unidata[cp]["name"] or
                     "SUBSCRIPT" in unidata[cp]["name"]} | {0x00B2, 0x00B3, 0x00B9} | in_blocks("Superscripts and Subscripts")
    fractions = name_has("VULGAR FRACTION") | in_blocks("Number Forms") | {0x2044, 0x215F}
    collections_def = [
        ("spaces", "space", spaces),
        ("dashes", "minus", by_gc("Pd") | {0x2212, 0x2043}),
        ("quotes", "quote.opening", name_has("QUOTATION MARK", "APOSTROPHE") | by_gc("Pi", "Pf") | {0x0022, 0x0027, 0x0060, 0x00B4}),
        ("punctuation", "textformat", by_gc("Po", "Ps", "Pe", "Pc") - {0x0022, 0x0027}),
        ("typography", "paragraphsign", typography),
        ("math", "plusminus", by_gc("Sm") | in_blocks("Mathematical Operators", "Supplemental Mathematical Operators",
                                                       "Miscellaneous Mathematical Symbols-A", "Miscellaneous Mathematical Symbols-B")),
        ("arrows", "arrow.right", name_has("ARROW") | in_blocks("Arrows", "Supplemental Arrows-A", "Supplemental Arrows-B")),
        ("currency", "eurosign", by_gc("Sc")),
        ("fractions", "divide", fractions | scripts_super),
        ("diacritics", "a.circle", in_blocks("Combining Diacritical Marks", "Combining Diacritical Marks Extended",
                                              "Combining Diacritical Marks Supplement", "Combining Diacritical Marks for Symbols",
                                              "Spacing Modifier Letters") | by_gc("Sk")),
        ("latin", "character", {cp for cp in in_blocks("Latin-1 Supplement", "Latin Extended-A", "Latin Extended-B",
                                                        "Latin Extended Additional", "IPA Extensions") if unidata[cp]["gc"].startswith("L")}),
        ("greek", "function", in_blocks("Greek and Coptic")),
        ("shapes", "square.on.circle", in_blocks("Geometric Shapes", "Geometric Shapes Extended", "Miscellaneous Symbols", "Dingbats",
                                                  "Block Elements", "Miscellaneous Symbols and Arrows")),
        ("boxdrawing", "rectangle.split.3x3", in_blocks("Box Drawing")),
        ("technical", "gearshape", in_blocks("Miscellaneous Technical", "Control Pictures", "Optical Character Recognition")),
        ("keyboard", "command", keyboard),
    ]
    collections = [{"id": cid, "symbol": sym, "ranges": spans(cps & inc)} for cid, sym, cps in collections_def]

    # ---------------- assemble ----------------------------------------------
    def uniq(seq):
        seen, out = set(), []
        for s in seq:
            k = norm_term(s)
            if k and k not in seen:
                seen.add(k)
                out.append(s.strip())
        return out

    rows = []
    for cp in included:
        info = unidata[cp]
        name = display_name(cp)
        alias_list = uniq([a for a in aliases.get(cp, []) if norm_term(a) != norm_term(name)])
        syn_list = uniq(synonyms.get(cp, []))
        taken = {norm_term(x) for x in alias_list + syn_list}
        kw = uniq([w for w in cldr.get(cp, []) if norm_term(w) not in taken and w != chr(cp) and len(w) > 1])
        note_list = notes.get(cp, [])
        rows.append([
            cp, name, info["gc"], block_of[cp], script_of[cp], age_index[age_of[cp]], priority(cp),
            alias_list, syn_list, kw, related(cp), " ".join(note_list)[:300],
        ])

    out = {
        "version": 1,
        "unicodeVersion": args.max_age,
        "fields": ["cp", "name", "gc", "block", "script", "age", "priority", "aliases", "synonyms", "keywords", "related", "notes"],
        "blocks": block_names,
        "scripts": script_names,
        "ages": age_names,
        "collections": collections,
        "entities": {str(cp): n for cp, n in entities.items() if cp in inc},
        "legacy": {k: {str(cp): b for cp, b in v.items() if cp in inc} for k, v in legacy.items()},
        "characters": rows,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(rows)} characters, {os.path.getsize(args.out) / 1e6:.2f} MB -> {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
