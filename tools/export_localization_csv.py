"""Strings → 로블록스 클라우드 현지화 표 CSV (지시서 #L1 단계 4 · K4).

사용:  python3 -I tools/export_localization_csv.py [-o 출력.csv]
       기본 출력은 지금 폴더의 localization_table.csv (저장소에 커밋하지 않는다 — 원본은 Strings.lua)

열 (공식 문서 manual-translations "Cloud localization table" · add-source-content CSV 예시 — 2026-10-25 확인):
  Key      Strings 키. FormatByKey(키)로 찾는다(나중 방식 — docs/LOCALIZATION.md 5절). 키 중복 금지
  Context  보통 비운다. 같은 영어(Source)가 두 키 이상이면 둘째부터 키를 넣는다 — "Source + Context 중복 금지" 규칙 때문
  Example  번역자 메모. 자리 표시가 있으면 이름을 적는다(값은 게임이 숫자 문자열로 채운다)
  Source   영어(en). 게임의 원본 언어(Source Language)는 English로 둔다
  ko       한국어(직접 번역 — 올리면 수동 번역으로 잠긴다. 자동 번역이 덮지 않는다)
한계(공식 문서 add-translations): 파일 2MB · 항목 1만 · 한 번에 추가 · 수정 1,000개 — 넘으면 이 스크립트가 알린다.
"""
import csv
import io
import os
import re
import sys

sys.dont_write_bytecode = True  # tools/__pycache__를 만들지 않는다
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_strings import load_entries, PLACEHOLDER  # noqa: E402

LANGS = ["ko"]  # Source(en) 밖의 열. 새 언어를 Strings에 직접 넣으면 여기에 코드를 더한다
MAX_ROWS_PER_UPLOAD = 1000
MAX_BYTES = 2 * 1024 * 1024


def rows():
    entries, errors = load_entries()
    if errors:
        raise SystemExit("Strings.lua를 읽지 못했다:\n" + "\n".join(errors))
    seen_source = {}
    out = []
    for key, fields, _ in sorted(entries, key=lambda e: e[2]):
        source = fields.get("en", "")
        if not source:
            raise SystemExit(f"{key}: en이 없다 — Source는 필수(공식 문서)")
        context = ""
        if source in seen_source:
            context = key  # Source + Context가 겹치면 안 된다
        seen_source.setdefault(source, key)
        params = sorted(set(PLACEHOLDER.findall(source)))
        example = ("params: " + ", ".join(params)) if params else ""
        out.append([key, context, example, source] + [fields.get(lang, "") for lang in LANGS])
    return out


def main():
    path = "localization_table.csv"
    if "-o" in sys.argv:
        path = sys.argv[sys.argv.index("-o") + 1]
    data = rows()
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(["Key", "Context", "Example", "Source"] + LANGS)
    w.writerows(data)
    text = buf.getvalue()
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    size = len(text.encode("utf-8"))
    dup = sum(1 for r in data if r[1])
    print(f"{path}: 항목 {len(data)} · {size} 바이트 · Context를 채운 중복 영어 {dup}")
    if len(data) > MAX_ROWS_PER_UPLOAD:
        print(f"⚠️ 한 번에 올릴 수 있는 추가 · 수정은 {MAX_ROWS_PER_UPLOAD}개다 — 나눠 올린다")
    if size > MAX_BYTES:
        print("⚠️ 파일이 2MB를 넘는다")
    bad = [r[0] for r in data if any(set(PLACEHOLDER.findall(t)) != set(PLACEHOLDER.findall(r[3])) for t in r[4:] if t)]
    if bad:
        raise SystemExit("자리 표시가 영어와 다른 항목: " + ", ".join(bad))
    keys = [r[0] for r in data]
    if len(keys) != len(set(keys)):
        raise SystemExit("키 중복")
    pairs = [(r[3], r[1]) for r in data]
    if len(pairs) != len(set(pairs)):
        raise SystemExit("Source + Context 중복")
    if re.search(r"[\r]", text):
        raise SystemExit("줄바꿈 문자가 섞였다")


if __name__ == "__main__":
    main()
