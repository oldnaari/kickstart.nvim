"""Bad-pattern detectors: the checks behind prose.nvim's pattern flags.

bin/roles parses each paragraph with Stanza, then hands every parsed run of one
language here. detect() looks at the words, their parts of speech, morphology
and dependency tree, and returns:

    flags     [(start, end, code, message)] character ranges in the run's text
    lead      (start, end, form) how the paragraph's first word reads, such as
              "imperative" or "gerund"; Lua compares the items of a list
    acronyms  [(start, end, word, defined)] all-caps words; Lua flags the ones
              used before they are defined, which needs the whole document

The flags are advice, not errors: each says what it noticed and why it can
matter, never what to write instead. The checks and how far to trust each one
are in README.md ("Patterns") and in the Prose Pattern Atlas report.

Word lists live in lexicon/<lang>.txt, one entry per line under a [section]
header. Entries match on the word as written or on its dictionary form, so
"являться" also finds "является" and "являлись". Edits are picked up on the
next paragraph, without restarting the parser.

Two optional data sources, both local once fetched:

  WordNet (`brew install wordnet`) confirms English nominalizations: it knows
  that "decision" comes from "decide" but "nation" comes from no verb.
  Without it, a suffix list does the job less well.

  The concreteness ratings of Brysbaert, Warriner & Kuperman (2014), 40,000
  English words rated 1 (abstract) to 5 (concrete), for the Abstract check.
  Downloaded once from the publisher into the cache directory; without them
  that check is skipped.
"""

import os
import re
import shutil
import ssl
import threading
import urllib.request
import zipfile
import xml.etree.ElementTree as ET
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
LEXICON_DIR = os.path.join(HERE, "lexicon")

# --- thresholds ---------------------------------------------------------------

SUBJECT_GAP = 8  # words between a subject and its verb
OBJECT_GAP = 6  # words between a verb and its object
LONG_OPENER = 13  # words before the main clause starts
NEST_CENTRE = 2  # clauses embedded in the middle of another clause
NEST_DEPTH = 4  # clauses inside clauses, even at the end
MONOTONY_RUN = 4  # sentences in a row ...
MONOTONY_SPREAD = 4  # ... whose lengths differ by at most this ...
MONOTONY_MIN = 8  # ... and are at least this long
REPEATED_OPENINGS = 3  # sentences in a row opening with the same word
# Words between two uses of the same noun, adjective or adverb. At 15 words and
# with verbs counted, it flagged half the paragraphs of the prompt archive.
REPETITION_WINDOW = 10
PARAGRAPH_SENTENCES = 6
PARAGRAPH_WORDS = 150
READING_EASE = 30  # Flesch reading ease below this is "very hard"
READING_MIN_WORDS = 40
READING_MIN_SENTENCES = 3
ABSTRACT_MIN_WORDS = 20  # rated content words in the paragraph
ABSTRACT_RATING = 2.5  # on the 1-5 scale, below this is abstract
# Flag a paragraph when this share is abstract. Measured: this plugin's README
# runs 6-32% abstract, a deliberately abstract paragraph 58%.
ABSTRACT_SHARE = 0.45

# --- small helpers ------------------------------------------------------------

TOKEN = re.compile(r"\w+(?:['’]\w+)*")
OPAQUE = re.compile(r"x+")  # Neovim masks inline code and links as runs of x


def norm(s):
    return (s or "").lower().replace("ё", "е")


def base(rel):
    return (rel or "").split(":")[0]


def feats(word):
    out = {}
    for item in (word.feats or "").split("|"):
        k, _, v = item.partition("=")
        if v:
            out[k] = v
    return out


def word_range(word):
    """Character range of a word; a word inside a multi-word token ("don't")
    takes the token's."""
    if word.start_char is not None:
        return word.start_char, word.end_char
    return word.parent.start_char, word.parent.end_char


def plural(n, one, many=None):
    return f"{n} {one if n == 1 else (many or one + 's')}"


class Sent:
    """One parsed sentence with the lookups the detectors share."""

    def __init__(self, sent, text):
        self.text = text
        self.words = sent.words
        self.by_id = {w.id: w for w in self.words}
        self.kids = defaultdict(list)
        for w in self.words:
            if w.head:
                self.kids[w.head].append(w)
        self.f = {w.id: feats(w) for w in self.words}
        self.root = next((w for w in self.words if w.head == 0), None)
        self.content = [w for w in self.words if not self.punct(w)]

    @staticmethod
    def punct(w):
        return w.upos in ("PUNCT", "SYM")

    @staticmethod
    def opaque(w):
        return bool(OPAQUE.fullmatch(w.text))

    def feat(self, w, key):
        return self.f[w.id].get(key)

    def children(self, w, *rels):
        """Children of w whose relation, or its base ("nsubj" for "nsubj:pass"),
        is one of rels; all children when none are given."""
        return [c for c in self.kids[w.id] if not rels or c.deprel in rels or base(c.deprel) in rels]

    def subtree(self, w):
        out, stack = {w.id}, [w.id]
        while stack:
            for c in self.kids[stack.pop()]:
                out.add(c.id)
                stack.append(c.id)
        return out

    def core(self, w):
        """w with its articles, adjectives, numbers, compounds and possessors."""
        keep = {"det", "det:poss", "amod", "nummod", "compound", "flat", "flat:name", "nmod:poss", "case"}
        ids, stack = {w.id}, [w.id]
        while stack:
            for c in self.kids[stack.pop()]:
                if c.deprel in keep and not (c.deprel == "case" and c.id > w.id):
                    ids.add(c.id)
                    stack.append(c.id)
        lo, hi = min(ids), max(ids)
        inside = self.subtree(w)
        if not all(i in inside for i in range(lo, hi + 1)):
            return {w.id}
        return ids

    def span(self, ids):
        ids = [i for i in ids if not self.punct(self.by_id[i])] or list(ids)
        s, _ = word_range(self.by_id[min(ids)])
        _, e = word_range(self.by_id[max(ids)])
        return s, e

    def say(self, ids):
        s, e = self.span(ids)
        return " ".join(self.text[s:e].split())

    def count(self, ids):
        return sum(1 for i in ids if not self.punct(self.by_id[i]))

    def last(self, ids):
        """The last word of ids that is not punctuation."""
        return max((i for i in ids if not self.punct(self.by_id[i])), default=max(ids))

    def verb_group(self, h):
        """The verb h with its auxiliaries, copula and negation."""
        return {h.id} | {c.id for c in self.children(h, "aux", "cop") } | {
            c.id for c in self.children(h, "advmod") if self.feat(c, "Polarity") == "Neg"
        }

    def first(self):
        return self.content[0] if self.content else None

    def has_clause(self):
        return any(w.upos in ("VERB", "AUX") or base(w.deprel) == "cop" for w in self.words)


def flag(sent, ids, code, message):
    s, e = sent.span(ids)
    return (s, e, code, message)


# --- word lists ---------------------------------------------------------------


class Lexicon:
    """lexicon/<lang>.txt: [section] headers, one entry per line, # comments.
    A token may carry a part of speech, "շատ/ADV", to match only that."""

    def __init__(self, lang):
        self.lang = lang
        self.path = os.path.join(LEXICON_DIR, f"{lang}.txt")
        self.mtime = None
        self.sections = {}

    def get(self):
        try:
            mtime = os.stat(self.path).st_mtime
        except OSError:
            self.sections = {}
            return self
        if mtime != self.mtime:
            self.mtime = mtime
            self.sections = self.load()
        return self

    def load(self):
        sections = defaultdict(list)
        current = None
        with open(self.path, encoding="utf-8") as f:
            for raw in f:
                line = raw.split("#", 1)[0].strip()
                if not line:
                    continue
                m = re.fullmatch(r"\[([\w-]+)\]", line)
                if m:
                    current = m.group(1)
                    continue
                if current:
                    entry = []
                    for piece in line.split():
                        piece, _, upos = piece.partition("/")
                        entry.extend((t, upos or None) for t in TOKEN.findall(norm(piece)))
                    if entry:
                        sections[current].append(tuple(entry))
        out = {}
        for name, entries in sections.items():
            index = defaultdict(list)
            for entry in entries:
                index[entry[0][0]].append(entry)
            for lst in index.values():
                lst.sort(key=len, reverse=True)
            out[name] = (entries, index)
        return out

    def words(self, section):
        """The section's one-word entries, as a set of normalised words."""
        entries, _ = self.sections.get(section, ([], {}))
        return {e[0][0] for e in entries if len(e) == 1}

    def entries(self, section):
        return self.sections.get(section, ([], {}))[0]

    def find(self, sent, section, at_start=False):
        """[(word ids)] for each match of the section's entries in sent."""
        _, index = self.sections.get(section, ([], {}))
        if not index:
            return []
        stream = []  # (subtoken, word, word has one subtoken)
        for w in sent.content:
            subs = TOKEN.findall(norm(w.text))
            stream.extend((s, w, len(subs) == 1) for s in subs)
        found, i = [], 0
        while i < len(stream):
            tok, w, single = stream[i]
            keys = {tok, norm(w.lemma)} if single else {tok}
            best = None
            for key in keys:
                for entry in index.get(key, ()):
                    if self.matches(stream, i, entry) and (best is None or len(entry) > len(best)):
                        best = entry
            if best:
                found.append(sorted({stream[i + j][1].id for j in range(len(best))}))
                i += len(best)
            else:
                i += 1
            if at_start:
                break
        return found

    @staticmethod
    def matches(stream, i, entry):
        if i + len(entry) > len(stream):
            return False
        for j, (etok, upos) in enumerate(entry):
            tok, w, single = stream[i + j]
            if etok != tok and not (single and etok == norm(w.lemma)):
                return False
            if upos and w.upos != upos:
                return False
        return True


LEXICONS = {}


def lexicon(lang):
    if lang not in LEXICONS:
        LEXICONS[lang] = Lexicon(lang)
    return LEXICONS[lang].get()


# --- WordNet, for English nominalizations ------------------------------------


class WordNet:
    """Noun -> the verbs it derives from, and the set of adjectives, read from
    WordNet's own data files the first time they are needed (about 2 s)."""

    def __init__(self):
        self.lock = threading.Lock()
        self.loaded = False
        self.verbs_of = {}
        self.adjectives = set()

    @staticmethod
    def directory():
        candidates = [os.environ.get("WNSEARCHDIR"), os.environ.get("WNHOME") and os.path.join(os.environ["WNHOME"], "dict")]
        wn = shutil.which("wn")
        if wn:
            candidates.append(os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(wn))), "dict"))
        candidates += ["/usr/share/wordnet", "/usr/local/share/wordnet", "/opt/homebrew/share/wordnet"]
        for d in candidates:
            if d and os.path.isfile(os.path.join(d, "data.noun")):
                return d
        return None

    @staticmethod
    def synsets(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("  "):
                    continue  # the licence at the top
                parts = line.split(" ")
                n = int(parts[3], 16)
                words = [re.sub(r"\(.*\)$", "", parts[4 + 2 * k]).lower() for k in range(n)]
                i = 4 + 2 * n
                ptrs = [parts[i + 1 + 4 * k : i + 5 + 4 * k] for k in range(int(parts[i]))]
                yield parts[0], words, ptrs

    def ensure(self):
        with self.lock:
            if self.loaded:
                return self.ok
            self.loaded = True
            d = self.directory()
            self.ok = d is not None
            if not d:
                return False
            verbs = {off: words for off, words, _ in self.synsets(os.path.join(d, "data.verb"))}
            for _, words, ptrs in self.synsets(os.path.join(d, "data.noun")):
                for sym, off, pos, st in ptrs:
                    if sym == "+" and pos == "v" and off in verbs:
                        src, tgt = int(st[:2], 16), int(st[2:], 16)
                        nouns = [words[src - 1]] if src else words
                        targets = [verbs[off][tgt - 1]] if tgt else verbs[off]
                        for noun in nouns:
                            self.verbs_of.setdefault(noun, set()).update(targets)
            with open(os.path.join(d, "index.adj"), encoding="utf-8", errors="replace") as f:
                self.adjectives = {line.split(" ", 1)[0] for line in f if not line.startswith("  ")}
            return True


WORDNET = WordNet()


# --- concreteness ratings, for the Abstract check -----------------------------

RATINGS_URL = (
    "https://static-content.springer.com/esm/art%3A10.3758%2Fs13428-013-0403-5/"
    "MediaObjects/13428_2013_403_MOESM1_ESM.xlsx"
)


def cache_dir():
    if os.uname().sysname == "Darwin":
        root = os.path.expanduser("~/Library/Caches")
    else:
        root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(root, "prose.nvim")


class Ratings:
    def __init__(self):
        self.lock = threading.Lock()
        self.loaded = False
        self.rating = {}

    def ensure(self, log):
        with self.lock:
            if self.loaded:
                return bool(self.rating)
            self.loaded = True
            path = os.path.join(cache_dir(), "concreteness.tsv")
            if not os.path.isfile(path):
                try:
                    self.fetch(path, log)
                except Exception as e:  # offline, or the file moved: skip the check
                    log(f"patterns: concreteness ratings unavailable, Abstract check off: {type(e).__name__}: {e}")
                    return False
            with open(path, encoding="utf-8") as f:
                for line in f:
                    word, _, value = line.rstrip("\n").partition("\t")
                    try:
                        self.rating[word] = float(value)
                    except ValueError:
                        pass
            return bool(self.rating)

    @staticmethod
    def fetch(path, log):
        log("patterns: downloading the concreteness ratings (one time, 2 MB)...")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".xlsx"
        # uv's Python does not see the macOS certificate store; certifi (which
        # Stanza already pulls in) has the same roots.
        try:
            import certifi

            context = ssl.create_default_context(cafile=certifi.where())
        except ImportError:
            context = ssl.create_default_context()
        with urllib.request.urlopen(RATINGS_URL, timeout=60, context=context) as r, open(tmp, "wb") as out:
            out.write(r.read())
        ns = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
        rows = []
        with zipfile.ZipFile(tmp) as z:
            strings = ["".join(t.text or "" for t in si.iter(ns + "t")) for si in ET.fromstring(z.read("xl/sharedStrings.xml"))]
            for _, el in ET.iterparse(z.open("xl/worksheets/sheet1.xml")):
                if el.tag == ns + "row":
                    vals = []
                    for c in el.findall(ns + "c"):
                        v = c.find(ns + "v")
                        x = v.text if v is not None else ""
                        vals.append(strings[int(x)] if c.get("t") == "s" and x else x)
                    rows.append(vals)
                    el.clear()
        os.unlink(tmp)
        header = rows[0]
        word, conc, bigram = header.index("Word"), header.index("Conc.M"), header.index("Bigram")
        with open(path + ".part", "w", encoding="utf-8") as out:
            for r in rows[1:]:
                if len(r) > conc and r[bigram] == "0":
                    out.write(f"{r[word].lower()}\t{r[conc]}\n")
        os.replace(path + ".part", path)


RATINGS = Ratings()


# --- language data ------------------------------------------------------------

# Nominalizations: an action or quality turned into a noun.
EN_NOMINAL = ("tion", "sion", "ment", "ance", "ence", "ancy", "ency", "ity", "ness", "sis", "al", "ure", "ing")
EN_NOMINAL_STRONG = ("tion", "sion", "ment", "ance", "ence", "ity", "ness", "sis")
EN_NOMINAL_NOT = {"nation", "station", "ration", "portion", "potion", "lotion", "notion", "mention", "question",
                  "moment", "comment", "element", "segment", "fragment", "document", "instrument", "apartment",
                  "department", "experiment", "environment", "government", "sentence", "evidence", "audience",
                  "science", "experience", "difference", "conference", "reference", "instance", "distance",
                  "balance", "finance", "university", "city", "entity", "identity", "quality", "quantity",
                  "community", "opportunity", "activity", "authority", "business", "animal", "signal", "capital",
                  "interval", "journal", "manual", "material", "general", "nature", "feature", "picture", "future",
                  "culture", "structure", "temperature", "thing", "string", "spring", "evening", "morning",
                  "ceiling", "king", "wing", "building", "meeting", "setting", "heading", "string", "ring"}
RU_NOMINAL = ("ние", "тие", "ция")
RU_NOMINAL_KA = {"проверка", "обработка", "подготовка", "разработка", "настройка", "установка", "оценка",
                 "поддержка", "доставка", "загрузка", "отправка", "сборка", "переработка", "доработка",
                 "отработка", "наладка", "замена", "отмена", "смена", "поставка", "закупка", "переписка"}
RU_NOMINAL_NOT = {"здание", "задание", "мнение", "внимание", "значение", "отношение", "положение", "предложение",
                  "сообщение", "приложение", "изображение", "выражение", "уравнение", "образование", "окружение",
                  "расписание", "название", "состояние", "расстояние", "содержание", "объявление", "издание",
                  "растение", "явление", "понятие", "занятие", "событие", "предприятие", "станция", "позиция",
                  "функция", "секция", "лекция", "традиция", "конституция", "полиция", "информация",
                  "организация", "ситуация", "редакция", "коллекция", "нация", "революция", "поколение",
                  "направление", "настроение", "отделение", "учреждение", "сочинение", "произведение"}
HY_NOMINAL = ("ություն", "ում")
HY_NOMINAL_NOT = {"ընկերություն", "գիտություն", "պատմություն", "հանրապետություն", "կառավարություն",
                  "ազգություն", "մարդկություն", "համայնք", "քաղաքականություն", "ժողովրդավարություն",
                  "կրթություն", "լեզու"}

# Nouns that name an action, for light-verb constructions ("make a decision").
EVENTIVE = {
    "en": {"decision", "choice", "attempt", "change", "use", "assessment", "analysis", "evaluation", "review",
           "comparison", "improvement", "contribution", "recommendation", "suggestion", "statement",
           "investigation", "measurement", "examination", "observation", "adjustment", "discussion",
           "explanation", "description", "presentation", "look", "action", "effort", "reference", "mention",
           "conclusion", "estimate", "prediction", "payment", "purchase", "request", "response", "reply",
           "answer", "check", "test", "search", "study", "survey", "plan", "start", "move", "step", "note"},
    "ru": {"помощь", "решение", "участие", "контроль", "анализ", "оценка", "проверка", "обработка", "подготовка",
           "разработка", "настройка", "установка", "поиск", "выбор", "ремонт", "работа", "мера", "борьба",
           "влияние", "воздействие", "поддержка", "сбор", "учет", "расчет", "обзор", "опрос", "ответ",
           "согласие", "место", "возможность", "наблюдение", "исследование", "сравнение"},
    "hy": {"որոշում", "օգնություն", "աջակցություն", "հնարավորություն", "քայլ", "փորձ"},
}

# English: nouns that are usually people, for dangling modifiers.
EN_PEOPLE = {"people", "person", "user", "team", "researcher", "developer", "author", "reader", "writer",
             "engineer", "student", "teacher", "customer", "client", "manager", "member", "participant",
             "group", "committee", "company", "staff", "man", "woman", "child", "parent", "doctor", "patient",
             "scientist", "programmer", "maintainer", "reviewer", "contributor", "editor", "colleague"}
# Converbs that work like prepositions, and are fine at the start.
FIXED_CONVERBS = {"учитывать", "благодарить", "исходить", "судить", "несмотря", "начинать", "включать",
                  "спустя", "кончать", "considering", "consider", "given", "give", "assume", "assuming",
                  "regard", "regarding", "concern", "concerning", "accord", "according", "include",
                  "including", "exclude", "excluding", "provide", "provided", "grant", "granted", "speak",
                  "generally", "base", "based", "judge", "judging", "compare", "compared", "suppose"}

# Adverbs of time, frequency, focus or stance: not manner adverbs.
EN_NOT_MANNER = {"only", "early", "daily", "weekly", "monthly", "yearly", "likely", "finally", "currently",
                 "recently", "usually", "generally", "typically", "normally", "eventually", "initially",
                 "previously", "originally", "ultimately", "frequently", "rarely", "occasionally",
                 "increasingly", "mostly", "nearly", "partly", "largely", "mainly", "merely", "exactly",
                 "especially", "particularly", "specifically", "respectively", "accordingly", "consequently",
                 "additionally", "alternatively", "similarly", "unfortunately", "fortunately", "hopefully",
                 "ideally", "early", "lately", "shortly", "immediately", "instantly", "simultaneously",
                 "automatically", "manually", "locally", "globally", "explicitly", "implicitly", "directly",
                 "fully", "entirely", "slightly", "barely", "hardly", "nearly", "roughly", "approximately",
                 "newly", "separately", "together", "already", "apply", "reply", "supply", "family", "only"}
RU_NOT_MANNER = {"очень", "много", "мало", "немного", "давно", "недавно", "рано", "поздно", "долго", "часто",
                 "редко", "обычно", "сразу", "просто", "только", "возможно", "можно", "нужно", "надо",
                 "вероятно", "необходимо", "далеко", "близко", "отдельно", "вместе", "тоже", "также", "легко",
                 "трудно", "сложно", "давно", "заранее", "снова", "опять", "заново", "позже", "раньше",
                 "дальше", "больше", "меньше", "лучше", "хуже", "ещё", "еще", "уже", "всегда", "никогда",
                 "иногда", "сейчас", "теперь", "тогда", "потом", "здесь", "там", "туда", "сюда", "поэтому",
                 "почему", "зачем", "как", "так", "достаточно", "слишком", "совсем", "вообще", "автоматически",
                 "вручную", "локально", "отдельно", "одновременно", "постоянно", "полностью", "частично"}

NEGATORS_EN = {"not", "n't", "never", "no", "nobody", "nothing", "none", "nowhere", "neither", "nor"}
NEG_PREFIX_EN = ("un", "non", "in", "im", "ir", "il", "dis")
NEG_PREFIXED_EN = {"impossible", "insignificant", "inconsiderable", "irrelevant", "illegal", "incorrect",
                   "invalid", "inaccurate", "incomplete", "inadequate", "inconsistent", "infrequent",
                   "infrequently", "insufficient", "unimportant", "dissimilar", "disagree", "dislike",
                   "inconceivable", "indifferent", "immaterial", "impractical", "improbable", "imperfect"}

CLAUSAL = {"acl", "advcl", "ccomp", "csubj"}
OPENER_SKIP = {"obj", "iobj", "compound:lvc", "xcomp", "ccomp", "csubj"}


# --- sentence checks ----------------------------------------------------------


def subject_gap(S, lang):
    out = []
    for w in S.words:
        if base(w.deprel) not in ("nsubj", "csubj") or S.opaque(w):
            continue
        h = S.by_id.get(w.head)
        if not h or h.id < w.id:
            continue
        core = S.core(w) if base(w.deprel) == "nsubj" else S.subtree(w)
        group = S.verb_group(h)
        verb_start = min(i for i in group if i > max(core)) if any(i > max(core) for i in group) else h.id
        # Not an interruption: the verb's own objects (Armenian puts them before
        # the verb), and the subject's "of" phrases, which NounStack covers.
        skip = set()
        for c in S.children(h, "obj", "iobj", "compound:lvc") + S.children(w, "nmod"):
            skip |= S.subtree(c)
        gap = [i for i in range(max(core) + 1, verb_start) if i not in skip and not S.punct(S.by_id[i])]
        if len(gap) >= SUBJECT_GAP:
            verb = S.say(sorted(i for i in group if i >= verb_start))
            out.append(flag(S, gap, "SubjectGap",
                            f"{len(gap)} words between the subject '{S.say(core)}' and its verb '{verb}': "
                            "the reader holds the subject until the verb arrives. (Gopen & Swan)"))
    return out


def object_gap(S, lang):
    out = []
    for o in S.words:
        if o.deprel != "obj" or S.opaque(o):
            continue
        h = S.by_id.get(o.head)
        if not h or h.upos != "VERB":
            continue
        core = S.core(o)
        group = S.verb_group(h) | {c.id for c in S.children(h, "compound:prt")}
        if o.id > h.id:
            lo, hi = max(i for i in group if i < min(core)) if any(i < min(core) for i in group) else h.id, min(core)
        else:
            lo, hi = max(core), min(i for i in group if i > max(core)) if any(i > max(core) for i in group) else h.id
        skip = set()
        for c in S.children(h, "nsubj"):
            skip |= S.subtree(c)
        gap = [i for i in range(lo + 1, hi) if i not in skip and not S.punct(S.by_id[i])]
        if len(gap) >= OBJECT_GAP:
            out.append(flag(S, gap, "ObjectGap",
                            f"{len(gap)} words between '{h.text}' and its object '{S.say(core)}'. "
                            "(Strunk & White: keep related words together)"))
    return out


def long_opener(S, lang):
    r = S.root
    if not r:
        return []
    main = set(S.verb_group(r))
    for c in S.children(r, "nsubj", "csubj", "expl"):
        main |= S.core(c) if base(c.deprel) == "nsubj" else {c.id}
    start = min(main)
    skip = set()
    for c in S.kids[r.id]:
        if c.deprel in OPENER_SKIP or base(c.deprel) in OPENER_SKIP:
            skip |= S.subtree(c)
    opener = [w.id for w in S.content if w.id < start and w.id not in skip and w.deprel != "cc"]
    if len(opener) >= LONG_OPENER:
        return [flag(S, opener, "LongOpener",
                     f"{len(opener)} words before the main clause starts: the reader stores them "
                     "before knowing what they modify. (Pinker; Williams)")]
    return []


def nesting(S, lang):
    """Clauses embedded in the middle of others ("The rule [that the script
    [that the daemon runs] applies] is wrong"), or nested very deep."""
    best = None
    if not S.root:
        return []
    for w in S.words:
        chain, cur = [], w
        while cur and cur.head:
            if base(cur.deprel) in CLAUSAL:
                chain.append(cur)
            cur = S.by_id.get(cur.head)
        if len(chain) < 2:
            continue
        chain.reverse()  # outermost first
        # A clause is embedded in the middle when the clause around it has
        # words on both sides of it. At the end ("I think that he said
        # that...") or at the start ("Because ..., we") it is not.
        centre, enclosing = 0, S.root
        for c in chain:
            sub = S.subtree(c)
            around = [i for i in S.subtree(enclosing) - sub if not S.punct(S.by_id[i])]
            if any(i < min(sub) for i in around) and any(i > max(sub) for i in around):
                centre += 1
            enclosing = c
        if centre >= NEST_CENTRE or len(chain) >= NEST_DEPTH:
            score = (centre, len(chain))
            if best is None or score > best[0]:
                best = (score, chain[0])
    if not best:
        return []
    (centre, depth), outer = best
    what = f"{centre} clauses embedded in the middle of others" if centre >= NEST_CENTRE else f"clauses nested {depth} deep"
    return [flag(S, S.subtree(outer), "Nesting", f"{what.capitalize()}: the reader keeps each one open. (Pinker)")]


def passive(S, lang):
    out = []
    for w in S.words:
        if w.upos != "VERB" or S.feat(w, "Voice") != "Pass" or w.deprel in ("amod", "compound"):
            continue
        aux = S.children(w, "aux:pass")
        subj = [c for c in S.kids[w.id] if c.deprel in ("nsubj:pass", "csubj:pass")]
        if lang == "en" and not (aux or subj):
            continue  # a reduced relative, "the model trained on X"
        ids = {w.id} | {a.id for a in aux} | {c.id for c in S.children(w, "aux") if c.id < w.id}
        agent = [c for c in S.kids[w.id] if c.deprel == "obl:agent"]
        if agent:
            msg = (f"'{S.say(ids)}' is passive and names its actor, '{S.say(S.core(agent[0]))}'. "
                   "(Williams: characters as subjects)")
        else:
            msg = f"'{S.say(ids)}' is passive. It matters when the actor does. (Williams; Pullum: often fine)"
        out.append(flag(S, ids, "Passive", msg))
    return out


def is_nominal(w, lang):
    lemma = norm(w.lemma)
    if w.upos != "NOUN" or len(lemma) < 6:
        return False
    if lang == "en":
        if not lemma.endswith(EN_NOMINAL) or lemma in EN_NOMINAL_NOT:
            return False
        if WORDNET.ensure():
            if lemma in WORDNET.verbs_of:
                return True
            if lemma.endswith(("ity", "ness")):
                stem = lemma[:-3] if lemma.endswith("ity") else lemma[:-4]
                options = {stem, stem + "e", stem[:-1] + "y" if stem.endswith("i") else stem,
                           re.sub(r"bil$", "ble", stem)}
                return bool(options & WORDNET.adjectives)
            return False
        return lemma.endswith(EN_NOMINAL_STRONG)
    if lang == "ru":
        return (lemma.endswith(RU_NOMINAL) and lemma not in RU_NOMINAL_NOT) or lemma in RU_NOMINAL_KA
    if lang == "hy":
        return lemma.endswith(HY_NOMINAL) and lemma not in HY_NOMINAL_NOT
    return False


def light_verb(S, lang, lex):
    singles, pairs = set(), set()
    for entry in lex.entries("light-verb"):
        if len(entry) == 1:
            singles.add(entry[0][0])
        else:
            pairs.add((entry[0][0], entry[1][0]))
    out, objects = [], set()
    for w in S.words:
        if w.upos != "VERB":
            continue
        lemma = norm(w.lemma)
        particles = {norm(c.text) for c in S.children(w, "compound:prt")}
        if lemma not in singles and not any((lemma, p) in pairs for p in particles):
            continue
        for o in S.kids[w.id]:
            if o.deprel in ("obj", "compound:lvc") and o.upos == "NOUN" and not S.opaque(o):
                if is_nominal(o, lang) or norm(o.lemma) in EVENTIVE.get(lang, ()):
                    ids = set(range(min(w.id, o.id), max(w.id, o.id) + 1))
                    source = "Нора Галь: расщепление сказуемого" if lang == "ru" else "Williams: actions as verbs"
                    out.append(flag(S, ids, "LightVerb",
                                    f"'{S.say(ids)}' spreads one action over a verb and a noun. ({source})"))
                    objects.add(o.id)
    return out, objects


def nominalization(S, lang, skip):
    if not S.has_clause():
        return []
    out = []
    for w in S.words:
        if w.id in skip or w.head == 0 or S.opaque(w) or not is_nominal(w, lang):
            continue
        if base(w.deprel) not in ("nsubj", "obj", "obl", "iobj"):
            continue
        args = []
        for c in S.kids[w.id]:
            if c.upos not in ("NOUN", "PROPN", "PRON"):
                continue
            if lang == "en":
                ok = c.deprel == "nmod:poss" or (base(c.deprel) == "nmod" and any(
                    norm(k.lemma) == "of" for k in S.children(c, "case")))
            elif lang == "ru":
                ok = base(c.deprel) == "nmod" and S.feat(c, "Case") == "Gen" and not S.children(c, "case")
            else:
                ok = c.deprel == "nmod:poss" or (base(c.deprel) == "nmod" and not S.children(c, "case"))
            if ok:
                args.append(c)
        if not args:
            continue
        ids = {w.id} | S.core(w)
        for a in args:
            ids |= S.subtree(a)
        ids = set(range(min(ids), max(ids) + 1))
        source = "Нора Галь; Williams" if lang == "ru" else "Williams: actions as verbs"
        out.append(flag(S, ids, "Nominalization",
                        f"'{S.say(ids)}': the action is a noun, '{w.text}', with its object attached. ({source})"))
    return out


def expletive(S, lang):
    if lang != "en":
        return []
    out = []
    for w in S.words:
        if w.deprel != "expl" or norm(w.lemma) not in ("there", "it"):
            continue
        h = S.by_id.get(w.head)
        if not h or h.id < w.id:
            continue
        ids = set(range(w.id, h.id + 1))
        if norm(w.lemma) == "there":
            subj = S.children(h, "nsubj")
            what = f"the real subject, '{S.say(S.core(subj[0]))}'" if subj else "the real subject"
        elif S.children(h, "csubj", "ccomp"):
            what = "the point of the sentence"
        else:
            continue
        out.append(flag(S, ids, "EmptyOpener", f"'{S.say(ids)}' delays {what}. (Williams)"))
    return out


LEXICON_CODES = [
    ("opener", "EmptyOpener", "'{}' is an empty opener: the point comes later than it needs to. (Williams)"),
    ("wordy", "Wordy", "'{}' is wordy: fewer words say the same. (Strunk & White: omit needless words)"),
    ("cliche", "Cliche", "'{}' is a stock phrase. (Orwell, rule 1)"),
    ("filler", "Filler", "'{}' is filler: it usually adds nothing. (Orwell, rule 3)"),
    ("hedge", "Hedge", "'{}' hedges. It belongs where the uncertainty is real. (Pinker)"),
    ("intensifier", "Intensifier", "'{}' intensifies without giving a reason. (Zinsser)"),
]


def lexicon_flags(S, lang, lex):
    out = []
    for section, code, template in LEXICON_CODES:
        for ids in lex.find(S, section, at_start=section == "opener"):
            if section == "intensifier" and len(ids) == 1:
                w = S.by_id[ids[0]]
                h = S.by_id.get(w.head)
                if w.upos == "ADV" and h and h.upos == "VERB" and w.id > h.id:
                    continue  # "explain clearly": manner, not a booster
            out.append(flag(S, ids, code, template.format(S.say(ids))))
    return out


def noun_stack(S, lang):
    out = []
    if lang == "en":
        run = []
        for w in S.words + [None]:
            if w is not None and w.upos in ("NOUN", "PROPN") and not S.opaque(w) and (not run or w.id == run[-1].id + 1):
                run.append(w)
                continue
            if len(run) >= 3 and sum(1 for x in run if x.upos == "NOUN") >= 2 and all(
                    x.deprel in ("compound", "flat", "flat:name") for x in run[:-1]):
                ids = [x.id for x in run]
                out.append(flag(S, ids, "NounStack",
                                f"'{S.say(ids)}' stacks {len(run)} nouns: the relations between them are left "
                                "to the reader. (plain-language guidelines)"))
            run = [w] if w is not None and w.upos in ("NOUN", "PROPN") and not S.opaque(w) else []

    def link(c):
        if c.upos not in ("NOUN", "PROPN") or S.opaque(c):
            return False
        if lang == "en":
            return base(c.deprel) == "nmod" and any(norm(k.lemma) == "of" for k in S.children(c, "case"))
        if lang == "ru":
            return base(c.deprel) == "nmod" and S.feat(c, "Case") == "Gen" and not S.children(c, "case")
        return c.deprel == "nmod:poss" or (base(c.deprel) == "nmod" and not S.children(c, "case"))

    def longest(w):
        best = [w]
        for c in S.kids[w.id]:
            if link(c):
                path = [w] + longest(c)
                if len(path) > len(best):
                    best = path
        return best

    for w in S.words:
        if w.upos not in ("NOUN", "PROPN") or link(w):
            continue  # start only at the top of a chain
        chain = longest(w)
        if len(chain) >= 3:
            ids = {chain[0].id} | {k.id for k in S.children(chain[0], "det")}  # not its own preposition
            for x in chain[1:]:
                ids |= {x.id} | {k.id for k in S.children(x, "case", "det")}
            ids = set(range(min(ids), max(ids) + 1))
            if lang == "en":
                msg = f"'{S.say(ids)}' chains {len(chain) - 1} 'of' phrases. (plain-language guidelines)"
            else:
                source = "Нора Галь: нанизывание падежей" if lang == "ru" else "plain-language guidelines"
                msg = f"'{S.say(ids)}' chains {len(chain)} nouns, each depending on the next. ({source})"
            out.append(flag(S, ids, "NounStack", msg))
    return out


def negation(S, lang):
    out = []
    for w in S.words:
        h = S.by_id.get(w.head)
        if not h:
            continue
        t, hl = norm(w.text), norm(h.lemma)
        hit = False
        if lang == "en" and t in ("not", "n't", "never") and h.upos in ("ADJ", "ADV", "VERB"):
            hit = hl in NEG_PREFIXED_EN or (hl.startswith(("un", "non")) and len(hl) > 5)
        elif lang == "ru" and t == "не" and h.upos in ("ADJ", "ADV", "VERB"):
            hit = hl.startswith(("не", "без")) and len(hl) > 5
        elif lang == "hy" and t == "ոչ" and h.upos in ("ADJ", "ADV"):
            hit = hl.startswith("ան") and len(hl) > 4
        if hit:
            ids = set(range(min(w.id, h.id), max(w.id, h.id) + 1))
            out.append(flag(S, ids, "Negation",
                            f"'{S.say(ids)}' is a double negative: the reader undoes both. "
                            "(Strunk & White: positive form)"))
    if lang == "en":  # "don't have no time"
        by_clause = defaultdict(list)
        for w in S.words:
            if w.upos != "INTJ" and (norm(w.text) in NEGATORS_EN or S.feat(w, "Polarity") == "Neg"):
                cur = w
                while cur.head and cur.upos not in ("VERB", "AUX") and base(cur.deprel) not in ("root",):
                    cur = S.by_id[cur.head]
                by_clause[cur.id].append(w)
        for ws in by_clause.values():
            if len(ws) >= 2:
                ids = {x.id for x in ws}
                ids = set(range(min(ids), max(ids) + 1))
                out.append(flag(S, ids, "Negation", f"'{S.say(ids)}' negates twice in one clause. (Williams)"))
    return out


def adverbs(S, lang, lex):
    known = set()
    for section in ("intensifier", "hedge", "filler"):
        known |= lex.words(section)
    out = []
    for w in S.words:
        if w.upos != "ADV" or base(w.deprel) != "advmod" or S.opaque(w):
            continue
        h = S.by_id.get(w.head)
        if not h or h.upos != "VERB":
            continue
        lemma = norm(w.lemma)
        if lemma in known:
            continue
        if lang == "en":
            ok = lemma.endswith("ly") and len(lemma) >= 5 and lemma not in EN_NOT_MANNER
        elif lang == "ru":
            ok = lemma.endswith("о") and len(lemma) >= 5 and lemma not in RU_NOT_MANNER and S.feat(w, "Degree") in (None, "Pos")
        else:
            ok = lemma.endswith(("որեն", "աբար"))
        if ok:
            out.append(flag(S, [w.id], "Adverb", f"'{w.text}' is a manner adverb on '{h.text}'. (King; Strunk & White)"))
    return out


def form(S, w, lang):
    """How a verb or the first word reads: imperative, gerund, infinitive, past,
    finite, noun, or other."""
    if w.upos in ("VERB", "AUX"):
        if S.feat(w, "Mood") == "Imp":
            return "imperative"
        vf = S.feat(w, "VerbForm")
        if vf == "Ger" or vf == "Conv" or (vf == "Part" and S.feat(w, "Tense") == "Pres" and lang == "en"):
            return "gerund"
        if vf == "Inf":
            return "gerund" if lang == "hy" and S.feat(w, "Case") == "Ins" else "infinitive"
        if vf == "Part" or S.feat(w, "Tense") == "Past":
            return "past"
        return "finite"
    if w.upos in ("NOUN", "PROPN", "ADJ", "DET", "NUM", "PRON"):
        return "noun"
    return "other"


def parallel(S, lang):
    out = []
    for h in S.words:
        if h.upos != "VERB":
            continue
        def gerund_noun(c):  # "reading, writing": Stanza may tag the second a noun
            return lang == "en" and c.upos == "NOUN" and norm(c.text).endswith("ing")

        group = [h] + [c for c in S.children(h, "conj")
                       if (c.upos == "VERB" or gerund_noun(c)) and not S.children(c, "nsubj")]
        if len(group) < 2:
            continue
        forms = {w.id: "gerund" if gerund_noun(w) else form(S, w, lang) for w in group}
        nonfinite = {f for f in forms.values() if f in ("gerund", "infinitive")}
        if len(nonfinite) < 2:
            continue
        # The most common form; on a tie, the first item's sets the pattern.
        order = [forms[w.id] for w in group]
        majority = max(nonfinite, key=lambda f: (order.count(f), -order.index(f)))
        for w in group:
            if forms[w.id] in nonfinite and forms[w.id] != majority:
                out.append(flag(S, [w.id] + [m.id for m in S.children(w, "mark")], "Parallel",
                                f"'{w.text}' is a {forms[w.id]}, but the items it is joined with are "
                                f"{majority}s. (Strunk & White: parallel form)"))
    return out


def dangling(S, lang):
    r = S.root
    first = S.first()
    if not r or not first or first.id == r.id:
        return []
    out = []
    for a in S.children(r, "advcl"):
        sub = S.subtree(a)
        if first.id not in sub or a.upos != "VERB" or S.children(a, "nsubj"):
            continue
        vf, case = S.feat(a, "VerbForm"), S.feat(a, "Case")
        nonfinite = vf in ("Ger", "Conv") or (vf == "Part" and lang == "en") or (lang == "hy" and vf == "Inf" and case == "Ins")
        if not nonfinite or norm(a.lemma) in FIXED_CONVERBS or norm(a.text) in FIXED_CONVERBS:
            continue
        opener = S.say(sub)
        subj = S.children(r, "nsubj")
        passive = bool(S.children(r, "aux:pass") or [c for c in S.kids[r.id] if c.deprel == "nsubj:pass"])
        why = None
        if passive:
            why = "and the main clause is passive, so its subject does not do it"
        elif S.children(r, "expl"):
            why = "and the main clause opens with an empty subject"
        elif not subj:
            if S.feat(r, "Mood") != "Imp" and S.feat(r, "Person") not in ("1", "2") and r.upos in ("VERB", "ADJ", "ADV"):
                why = "and the main clause has no subject to attach it to"
        else:
            s = subj[0]
            if s.upos == "NOUN":
                anim = S.feat(s, "Animacy")
                if (lang == "ru" and anim == "Inan") or (lang == "hy" and anim == "Nhum") or (
                        lang == "en" and norm(s.lemma) not in EN_PEOPLE):
                    why = f"so it attaches to the main subject, '{S.say(S.core(s))}'"
        if why:
            out.append(flag(S, sub, "Dangling",
                            f"'{opener}' has no subject of its own, {why}. Who does it? "
                            "(Strunk & White: dangling modifier)"))
    return out


def counts(S):
    return len(S.content)


# --- checks across the sentences of a paragraph -------------------------------


def lead_of(sents, lang):
    if not sents:
        return None
    S = sents[0]
    words = [w for w in S.content if not S.opaque(w)]
    if not words:
        return None
    w = words[0]
    if w.upos == "PART" and norm(w.text) == "to" and len(words) > 1:  # "To install..."
        s, _ = word_range(w)
        _, e = word_range(words[1])
        return s, e, "infinitive"
    s, e = word_range(w)
    return s, e, form(S, w, lang)


def monotony(sents):
    out = []
    lengths = [counts(S) for S in sents]
    i = 0
    while i < len(sents):
        j = i
        lo = hi = lengths[i]
        while j + 1 < len(sents) and lengths[j + 1] >= MONOTONY_MIN:
            nlo, nhi = min(lo, lengths[j + 1]), max(hi, lengths[j + 1])
            if nhi - nlo > MONOTONY_SPREAD:
                break
            lo, hi, j = nlo, nhi, j + 1
        n = j - i + 1
        if n >= MONOTONY_RUN and lengths[i] >= MONOTONY_MIN:
            S = sents[i]
            size = f"{lo}" if lo == hi else f"{lo}–{hi}"
            out.append(flag(S, [S.first().id], "Monotony",
                            f"This and the next {n - 1} sentences are all {size} words long: the rhythm "
                            "drones. (Provost)"))
            i = j + 1
        else:
            i += 1
    return out


def repeated_openings(sents):
    out = []
    firsts = []
    for S in sents:
        w = S.first()
        firsts.append(norm(w.lemma or w.text) if w and not S.opaque(w) else None)
    i = 0
    while i < len(sents):
        j = i
        while j + 1 < len(sents) and firsts[i] and firsts[j + 1] == firsts[i]:
            j += 1
        n = j - i + 1
        if n >= REPEATED_OPENINGS:
            for k in range(i, j + 1):
                S = sents[k]
                out.append(flag(S, [S.first().id], "RepeatedOpening",
                                f"{n} sentences in a row open with '{S.first().text}'."))
        i = j + 1
    return out


STOP_LEMMAS = {"be", "have", "do", "get", "make", "go", "say", "can", "will", "быть", "мочь", "это", "такой",
               "который", "свой", "весь", "один", "եմ", "լինել", "ունենալ", "անել", "այդ", "այս"}


def repetition(sents):
    out = []
    last = {}  # lemma -> position
    pos = 0
    for S in sents:
        for w in S.content:
            pos += 1
            if w.upos not in ("NOUN", "ADJ", "ADV") or S.opaque(w):
                continue
            lemma = norm(w.lemma)
            if len(lemma) < 4 or lemma in STOP_LEMMAS:
                continue
            if lemma in last and pos - last[lemma] <= REPETITION_WINDOW:
                d = pos - last[lemma] - 1
                out.append(flag(S, [w.id], "Repetition",
                                f"'{w.text}' again, {plural(d, 'word')} after the last one. "
                                "(Fine for a term used on purpose.)"))
            last[lemma] = pos
    return out


def cohesion(sents):
    out = []
    seen = []  # content lemmas of each sentence
    for k, S in enumerate(sents):
        lemmas = {norm(w.lemma) for w in S.content if w.upos in ("NOUN", "PROPN", "ADJ", "VERB")}
        r = S.root
        if k > 0 and r:
            for s in S.children(r, "nsubj"):
                if s.upos not in ("NOUN", "PROPN") or s.id > r.id or S.opaque(s):
                    continue
                if any(S.feat(c, "PronType") == "Dem" for c in S.children(s, "det")):
                    continue  # "this change" points back by itself
                core = S.core(s)
                words = {norm(S.by_id[i].lemma) for i in core if S.by_id[i].upos in ("NOUN", "PROPN", "ADJ")}
                before = set().union(*seen[-2:]) if seen else set()
                if words and not words & before:
                    out.append(flag(S, core, "Cohesion",
                                    f"'{S.say(core)}' opens the sentence but is new: the two before it do not "
                                    "mention it, and readers look for old information first. (Gopen & Swan)"))
        seen.append(lemmas)
    return out


def syllables(word, lang):
    w = norm(word)
    if lang == "ru":
        return max(1, len(re.findall(r"[аеиоуыэюя]", w)))
    groups = re.findall(r"[aeiouy]+", w)
    n = len(groups)
    if w.endswith("e") and not w.endswith(("le", "ee")) and n > 1:
        n -= 1
    return max(1, n)


def paragraph_checks(sents, lang):
    out = []
    if not sents or not sents[0].first():
        return out
    S0 = sents[0]
    anchor = [S0.first().id]
    words = sum(counts(S) for S in sents)
    if len(sents) > PARAGRAPH_SENTENCES or words > PARAGRAPH_WORDS:
        out.append(flag(S0, anchor, "ParagraphLength",
                        f"This paragraph has {plural(len(sents), 'sentence')} and {words} words: likely more "
                        "than one topic. (Strunk & White: the paragraph as the unit of composition)"))
    if lang in ("en", "ru") and len(sents) >= READING_MIN_SENTENCES and words >= READING_MIN_WORDS:
        tokens = [w.text for S in sents for w in S.content if any(ch.isalpha() for ch in w.text) and not S.opaque(w)]
        if tokens:
            asl = len(tokens) / len(sents)
            asw = sum(syllables(t, lang) for t in tokens) / len(tokens)
            if lang == "en":
                score, name = 206.835 - 1.015 * asl - 84.6 * asw, "Flesch"
            else:
                score, name = 206.836 - 1.52 * asl - 65.14 * asw, "Flesch–Oborneva"
            if score < READING_EASE:
                out.append(flag(S0, anchor, "Readability",
                                f"Reading ease {score:.0f} ({name}): very hard. Sentences average {asl:.0f} words, "
                                f"words {asw:.1f} syllables. (A rough guide, not a verdict.)"))
    return out


def abstract(sents, lang, log):
    if lang != "en" or not sents or not RATINGS.ensure(log):
        return []
    rated = []
    for S in sents:
        for w in S.content:
            if w.upos in ("NOUN", "VERB", "ADJ") and not S.opaque(w):
                r = RATINGS.rating.get(norm(w.lemma))
                if r is not None:
                    rated.append((r, w.text))
    if len(rated) < ABSTRACT_MIN_WORDS:
        return []
    low = sorted(x for x in rated if x[0] < ABSTRACT_RATING)
    share = len(low) / len(rated)
    if share < ABSTRACT_SHARE:
        return []
    examples = []
    for _, t in low:
        if t.lower() not in examples:
            examples.append(t.lower())
        if len(examples) == 3:
            break
    S0 = sents[0]
    return [flag(S0, [S0.first().id], "Abstract",
                 f"{share:.0%} of this paragraph's content words are abstract (such as "
                 f"{', '.join(repr(e) for e in examples)}). (Strunk & White: definite, specific, concrete)")]


ACRONYM = re.compile(r"(?<!\w)([^\W\d_]{2,6}\d{0,2})(?!\w)")


def acronyms(sents, lang, lex):
    # Several to a line in the lists, and shared by all languages.
    allowed = {t.upper() for other in ("en", "ru", "hy") for e in lexicon(other).entries("acronym-ok") for t, _ in e}
    out = []
    for S in sents:
        for w in S.content:
            if w.upos not in ("PROPN", "NOUN", "X") or S.opaque(w):
                continue
            m = ACRONYM.fullmatch(w.text)
            if not m or not all(ch.isupper() for ch in w.text if ch.isalpha()) or w.text.upper() in allowed:
                continue
            s, e = word_range(w)
            before, after = S.text[max(0, s - 1):s], S.text[e:e + 2]
            defined = before == "(" or after.lstrip().startswith("(")
            out.append((s, e, w.text, defined))
    return out


def dedupe(flags):
    """Overlapping flags with the same code: keep the longest."""
    flags = sorted(flags, key=lambda f: (f[2], f[0], -(f[1] - f[0])))
    out = []
    for f in flags:
        if out and out[-1][2] == f[2] and f[0] < out[-1][1]:
            if f[1] - f[0] > out[-1][1] - out[-1][0]:
                out[-1] = f
            continue
        out.append(f)
    return sorted(out, key=lambda f: (f[0], f[1]))


def detect(doc, text, lang, log=lambda msg: None):
    """{"flags", "lead", "acronyms"} for one parsed run of text (see the top)."""
    lex = lexicon(lang)
    sents = [Sent(s, text) for s in doc.sentences]
    sents = [S for S in sents if S.content]
    flags = []
    for S in sents:
        lv, objects = light_verb(S, lang, lex)
        flags += lv
        flags += nominalization(S, lang, objects)
        for check in (subject_gap, object_gap, long_opener, nesting, passive, expletive, noun_stack, negation,
                      parallel, dangling):
            flags += check(S, lang)
        flags += lexicon_flags(S, lang, lex)
        flags += adverbs(S, lang, lex)
    flags += monotony(sents)
    flags += repeated_openings(sents)
    flags += repetition(sents)
    flags += cohesion(sents)
    flags += paragraph_checks(sents, lang)
    flags += abstract(sents, lang, log)
    return {"flags": dedupe(flags), "lead": lead_of(sents, lang), "acronyms": acronyms(sents, lang, lex)}
