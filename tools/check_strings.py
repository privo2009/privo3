"""Strings 표 정적 검사 (지시서 #L1 단계 2 · 5). Studio 없이 돈다 — Python 3만 있으면 된다.

사용:  python3 -I tools/check_strings.py           실패가 있으면 exit 1
       python3 -I tools/check_strings.py --keys    키 목록도 찍는다
       python3 -I tools/check_strings.py --lengths 영어가 한국어보다 많이 긴 항목(글자 수 2배 이상 · 폭 추정 1.3배 이상)
       python3 -I tools/check_strings.py --long    유럽 4개 언어가 영어보다 많이 긴 항목(글자 수 1.4배 이상 — 지시서 #40)

검사 (같은 규칙의 Luau 판은 src/server/Tests/LocaleTests.server.lua — #L2가 Play에서 돌린다):
  1. Strings.lua의 항목 줄이 전부 읽힌다 · 키 중복 없음
  2. 모든 키에 en이 있다(비어 있지 않다)
  3. 언어마다 자리 표시 집합이 en과 같다
  4. 코드가 부르는 키(Locale.t("…") 등 · 키 꼴 문자열 리터럴)가 표에 있다. "접두." .. 값 꼴은 그 접두로 시작하는 키가 하나 이상 있어야 한다
  5. (알림만) 어디서도 안 부르는 키
  6. 유럽 4개 언어(Localization/Lang/<코드>.lua — 지시서 #40): 키마다 문장이 있다(누락 · 빈 문자열 = 실패) ·
     자리 표시 집합 = en(3번과 같은 검사) · 줄바꿈(\n) 개수 = en · 표에 없는 키(고아) 없음 · 키 중복 없음
"""
import os
import re
import sys

sys.dont_write_bytecode = True  # tools/__pycache__를 만들지 않는다
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luau_lex import tokens  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRINGS = os.path.join(ROOT, "src", "shared", "Localization", "Strings.lua")
LANG_DIR = os.path.join(ROOT, "src", "shared", "Localization", "Lang")
LANG_FILES = ["es", "pt", "fr", "de"]  # Strings.LANG_FILES와 같은 목록(지시서 #40)
LANG_ENTRY = re.compile(r'^\s*\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)",?\s*(--.*)?$')

ENTRY = re.compile(r'^\s*\["([^"]+)"\]\s*=\s*\{(.*)\},?\s*(--.*)?$')
FIELD = re.compile(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"')
PLACEHOLDER = re.compile(r"{([A-Za-z0-9_]+)}")
KEY_SHAPE = re.compile(r"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9_]+)+\.?$")


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def load_entries(path=STRINGS):
    """[(key, {lang: text}, line)] — 항목 줄만. 읽지 못한 항목 꼴 줄은 errors에."""
    entries, errors = [], []
    inside = False
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if line.strip().startswith("Strings.Entries = {"):
            inside = True
            continue
        if inside and line.startswith("}"):
            inside = False
            continue
        if not inside or line.strip().startswith("--") or not line.strip():
            continue
        m = ENTRY.match(line)
        if not m:
            errors.append(f"Strings.lua:{n}: 항목 줄을 읽지 못했다 — 한 줄에 한 항목 꼴인지: {line.strip()[:80]}")
            continue
        fields = {k: unescape(v) for k, v in FIELD.findall(m.group(2))}
        entries.append((m.group(1), fields, n))
    return entries, errors


def load_lang(code):
    """({key: text}, errors) — Lang/<코드>.lua의 항목 줄. 키 중복 · 읽지 못한 줄은 errors에."""
    path = os.path.join(LANG_DIR, code + ".lua")
    texts, errors, lines = {}, [], {}
    if not os.path.exists(path):
        return texts, [f"Lang/{code}.lua가 없다"]
    inside = False
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        st = line.strip()
        if st.startswith("return {"):
            inside = True
            continue
        if inside and line.startswith("}"):
            inside = False
            continue
        if not inside or st.startswith("--") or not st:
            continue
        m = LANG_ENTRY.match(line)
        if not m:
            errors.append(f"Lang/{code}.lua:{n}: 항목 줄을 읽지 못했다: {st[:80]}")
            continue
        key = m.group(1)
        if key in texts:
            errors.append(f"Lang/{code}.lua:{n}: 키 중복 {key} (처음 {lines[key]}줄)")
        texts[key], lines[key] = unescape(m.group(2)), n
    return texts, errors


def load_all():
    """(entries, errors, orphans) — Strings 항목에 Lang 파일 문장을 합친 것(게임의 Strings.lua 끝 합치기와 같은 규칙)."""
    entries, errors = load_entries()
    by_key = {key: fields for key, fields, _ in entries}
    orphans = []
    for code in LANG_FILES:
        texts, errs = load_lang(code)
        errors += errs
        for key, text in texts.items():
            if key in by_key:
                by_key[key][code] = text
            else:
                orphans.append(f"Lang/{code}.lua: 표에 없는 키 {key}")
    return entries, errors, orphans


def long_report(entries):
    """(언어, 키, en, 번역, 배율, 짧은 문구?) — 번역이 영어보다 글자 수 1.4배 이상인 것. 짧은 문구 = 영어 12자 이하(버튼 · 라벨)."""
    out = []
    for key, fields, _ in entries:
        en = fields.get("en", "")
        if not en:
            continue
        en_s = PLACEHOLDER.sub("0000", en)
        for code in LANG_FILES:
            tr = fields.get(code, "")
            if not tr:
                continue
            ratio = len(PLACEHOLDER.sub("0000", tr)) / max(1, len(en_s))
            if ratio >= 1.4:
                out.append((code, key, en, tr, ratio, len(en_s) <= 12))
    out.sort(key=lambda r: (LANG_FILES.index(r[0]), -r[4]))
    return out


def code_references():
    """(정확한 키 집합, 접두 집합, {키: 처음 본 자리}) — src 전체의 문자열 리터럴에서."""
    exact, prefixes, where = set(), set(), {}
    for base, _, files in os.walk(os.path.join(ROOT, "src")):
        for f in files:
            if not f.endswith(".lua"):
                continue
            path = os.path.join(base, f)
            rel = os.path.relpath(path, ROOT)
            if os.path.abspath(path) == os.path.abspath(STRINGS) or os.path.abspath(base) == os.path.abspath(LANG_DIR):
                continue  # 표 자체(Strings · Lang 번역 파일)는 "부르는 곳"이 아니다
            src = open(path, encoding="utf-8").read()
            for kind, text, line, start, end in tokens(src):
                if kind != "string" or not KEY_SHAPE.match(text):
                    continue
                after = src[end:end + 6].lstrip()
                if text.endswith(".") or after.startswith(".."):
                    prefixes.add(text)
                else:
                    exact.add(text)
                where.setdefault(text, f"{rel}:{line}")
    return exact, prefixes, where


def est_width(text):
    """대략의 글자 폭(한글 1칸 기준). 한글은 라틴보다 넓다 — 글자 수만 보면 영어 넘침을 놓친다."""
    w = 0.0
    for ch in PLACEHOLDER.sub("0000", text):
        if "\uac00" <= ch <= "\ud7a3":
            w += 1.0
        elif ch.isupper() or ch.isdigit():
            w += 0.62
        elif ch == " ":
            w += 0.28
        elif ch.isalpha():
            w += 0.52
        else:
            w += 0.45
    return w


def length_report(entries):
    """(키, en, ko, 글자 수 배율, 폭 배율) — 영어가 많이 긴 것만, 폭 배율 큰 순."""
    out = []
    for key, fields, _ in entries:
        en, ko = fields.get("en", ""), fields.get("ko", "")
        if not en or not ko:
            continue
        en_s, ko_s = PLACEHOLDER.sub("0000", en), PLACEHOLDER.sub("0000", ko)
        char_ratio = len(en_s) / max(1, len(ko_s))
        width_ratio = est_width(en) / max(0.1, est_width(ko))
        if char_ratio >= 2.0 or width_ratio >= 1.3:
            out.append((key, en, ko, char_ratio, width_ratio))
    out.sort(key=lambda r: -r[4])
    return out


def main():
    entries, errors, orphans = load_all()
    errors += orphans
    keys = {}
    for key, fields, n in entries:
        if key in keys:
            errors.append(f"Strings.lua:{n}: 키 중복 {key} (처음 {keys[key]}줄)")
        keys[key] = n
        en = fields.get("en", "")
        if not en:
            errors.append(f"Strings.lua:{n}: {key} — en이 없다")
            continue
        want = set(PLACEHOLDER.findall(en))
        for lang, text in fields.items():
            if lang == "en" or text == "":
                continue
            got = set(PLACEHOLDER.findall(text))
            if got != want:
                errors.append(f"Strings.lua:{n}: {key} — {lang} 자리 표시 {sorted(got)} ≠ en {sorted(want)}")
            if text.count("\n") != en.count("\n"):
                errors.append(f"Strings.lua:{n}: {key} — {lang} 줄바꿈 {text.count(chr(10))}개 ≠ en {en.count(chr(10))}개")
        for lang in LANG_FILES:
            if lang not in fields:
                errors.append(f"Lang/{lang}.lua: {key} — 번역 없음(en이 보인다)")
            elif fields[lang] == "":
                errors.append(f"Lang/{lang}.lua: {key} — 빈 문자열")

    namespaces = {k.split(".")[0] for k in keys}
    exact, prefixes, where = code_references()
    used = set()
    for ref in sorted(exact):
        if ref.split(".")[0] not in namespaces:
            continue  # 키 꼴이지만 Strings 이름공간이 아니다(인스턴스 경로 등)
        if ref in keys:
            used.add(ref)
        elif any(k.startswith(ref + ".") for k in keys):
            used.update(k for k in keys if k.startswith(ref + "."))  # 키 앞부분(뒤에 ".name" 등을 붙여 쓴다)
        else:
            errors.append(f"{where[ref]}: 표에 없는 키 {ref}")
    for p in sorted(prefixes):
        if p.split(".")[0] not in namespaces:
            continue
        hit = [k for k in keys if k.startswith(p)]
        if not hit:
            errors.append(f"{where[p]}: 접두 {p}로 시작하는 키가 표에 없다")
        used.update(hit)

    unused = sorted(set(keys) - used)
    print(f"Strings 항목 {len(keys)} · 코드가 부르는 키 {len(used)} · 안 부르는 키 {len(unused)}")
    for k in unused:
        print(f"  (알림) 안 부르는 키 {k}")
    if "--lengths" in sys.argv:
        rows = length_report(entries)
        print(f"--- 영어가 많이 긴 항목 {len(rows)} (글자 수 ≥ 2배 또는 폭 추정 ≥ 1.3배) ---")
        for key, en, ko, cr, wr in rows:
            print(f"  {key}  글자 ×{cr:.1f} · 폭 ×{wr:.1f}  en={en!r}  ko={ko!r}")
    if "--long" in sys.argv:
        rows = long_report(entries)
        print(f"--- 영어보다 많이 긴 번역 {len(rows)} (글자 수 ≥ 1.4배 · [짧은] = 영어 12자 이하 버튼 · 라벨) ---")
        for code, key, en, tr, ratio, short in rows:
            print(f"  {code} {key}  ×{ratio:.2f}{' [짧은]' if short else ''}  en={en!r}  {code}={tr!r}")
    counts = {code: sum(1 for _, f, _ in entries if f.get(code)) for code in ["ko"] + LANG_FILES}
    print("언어별 키 수: en " + str(len(keys)) + " · " + " · ".join(f"{c} {counts[c]}" for c in counts))
    if "--keys" in sys.argv:
        for k in sorted(keys):
            print(k)
    for e in errors:
        print("FAIL " + e)
    print(f"{len(errors)} failed")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
