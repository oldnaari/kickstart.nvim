#!/usr/bin/env python3
"""Which Vale rules fire most across the Claude prompt archive.

Runs the repo's Vale config over ~/.claude/prompt-archive/*.md (written by the
BufWritePost autocmd in init.lua) at suggestion level, so passive voice counts
too, and prints per rule: alerts, alerts per 1,000 prose words, and the three
worst examples. "Worst" means "sitting in the longest sentence", for every rule.

Everything stays local: the archive holds private prompts, so nothing is sent
to any model or service. --no-examples prints numbers only, no archive text.

    python3 vale/archive-stats.py [--no-examples]
"""

import argparse
import collections
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORD = re.compile(r"[\w'’-]+")  # same token as Prompt.LongSentence
DATE_HEADING = re.compile(
    r"^## \d{4}-\d{2}-\d{2} \d{2}:\d{2}$"
)  # archive's own entry headings
SENTENCE_END = re.compile(r"(?<=[.!?])\s+")


def find_vale():
    mason = os.path.expanduser("~/.local/share/nvim/mason/bin/vale")
    return shutil.which("vale") or (mason if os.path.exists(mason) else None)


def prose_lines(lines):
    """Yield (index, line) for lines Vale treats as prose: not fenced code, not
    the archive's date headings or `---` entry separators."""
    fenced = False
    for i, line in enumerate(lines):
        if line.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
            continue
        if fenced or DATE_HEADING.match(line) or line.strip() == "---":
            continue
        yield i, line


def sentence_at(lines, line_no, col):
    """The sentence containing (1-based line, 1-based column), from its paragraph."""
    i = line_no - 1
    start = i
    while start > 0 and lines[start - 1].strip():
        start -= 1
    end = i
    while end + 1 < len(lines) and lines[end + 1].strip():
        end += 1
    para = " ".join(lines[start : end + 1])
    offset = sum(len(lines[k]) + 1 for k in range(start, i)) + col - 1
    pos = 0
    for sent in SENTENCE_END.split(para):
        found = para.find(sent, pos)
        if found <= offset < found + len(sent) + 1:
            return sent
        pos = found + len(sent)
    return lines[i]


def truncate(s, n=60):
    s = " ".join(s.split())
    return s if len(s) <= n else s[: n - 1] + "…"


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--archive", default=os.path.expanduser("~/.claude/prompt-archive"))
    ap.add_argument("--config", default=os.path.join(HERE, ".vale.ini"))
    ap.add_argument(
        "--no-examples", action="store_true", help="print numbers only, no archive text"
    )
    args = ap.parse_args()

    vale = find_vale()
    if not vale:
        sys.exit("vale not found (install it with :MasonInstall vale)")
    files = sorted(
        os.path.join(args.archive, f)
        for f in os.listdir(args.archive)
        if f.endswith(".md")
    )
    if not files:
        sys.exit(f"no .md files in {args.archive}")

    words = entries = 0
    by_rule = collections.defaultdict(list)
    levels = {}
    for path in files:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        # Each entry starts "\n\n---\n\n## date", so every file opens with `---`,
        # which Vale parses as YAML front matter and rejects. Blank that first
        # separator (line numbers stay put) and lint through stdin.
        text = re.sub(r"\A(\s*)---[ \t]*(?=\n)", r"\1", text)
        lines = text.split("\n")
        entries += sum(1 for line in lines if DATE_HEADING.match(line))
        words += sum(len(WORD.findall(line)) for _, line in prose_lines(lines))

        out = subprocess.run(
            [
                vale,
                "--config",
                args.config,
                "--minAlertLevel=suggestion",
                "--output=JSON",
                "--ext=.md",
            ],
            input=text,
            capture_output=True,
            text=True,
        )
        if out.returncode not in (0, 1):  # 1 = alerts were found
            sys.exit(
                f"vale failed on {os.path.basename(path)}: {out.stderr.strip()[:300]}"
            )
        for items in json.loads(out.stdout or "{}").values():
            for a in items:
                sent = sentence_at(lines, a["Line"], a["Span"][0])
                by_rule[a["Check"]].append((len(WORD.findall(sent)), sent, a["Match"]))
                levels[a["Check"]] = a["Severity"]

    print(
        f"Prompt archive: {len(files)} files, {entries} entries, {words:,} prose words\n"
    )
    print(f"{'Rule':<22}{'Level':<12}{'Alerts':>7}{'per 1k words':>14}")
    ranked = sorted(by_rule.items(), key=lambda kv: -len(kv[1]))
    for rule, hits in ranked:
        print(
            f"{rule:<22}{levels[rule]:<12}{len(hits):>7}{1000 * len(hits) / max(words, 1):>14.1f}"
        )

    # Numbers only, so they print even with --no-examples.
    long = [n for n, _, _ in by_rule.get("Prompt.LongSentence", [])]
    if long:
        buckets = collections.Counter(
            "26-30"
            if n <= 30
            else "31-40"
            if n <= 40
            else "41-60"
            if n <= 60
            else "61+"
            for n in long
        )
        print(
            "\nLongSentence lengths (words): "
            + ", ".join(
                f"{b}: {buckets[b]}" for b in ("26-30", "31-40", "41-60", "61+")
            )
        )
    openers = collections.Counter(
        " ".join(m.split()) for _, _, m in by_rule.get("Prompt.VagueOpener", [])
    )
    if openers:
        print(
            "VagueOpener by opener: "
            + ", ".join(f"'{k}': {v}" for k, v in openers.most_common(6))
        )

    if args.no_examples:
        return
    for rule, hits in ranked:
        print(f"\n{rule}: worst three (by sentence length)")
        for n, sent, match in sorted(hits, key=lambda h: -h[0])[:3]:
            print(f"  {n:>3} words  [{truncate(match, 20)}]  {truncate(sent)}")


if __name__ == "__main__":
    main()
