"""화면 글꼴 소스 검사 (지시서 #17 F1).

src/ 아래 .lua에서 Enum.Font를 직접 쓰는 곳을 찾는다. 허용: src/shared/Config/UiTheme.lua(UiTheme.FONT 한 곳).
게임 스크립트는 다른 스크립트의 Source를 읽을 수 없어 Play 테스트(LocaleClientTests)는 화면 쪽만 잰다 — 소스 쪽은 이 도구.
쓰는 법: python -I tools/check_fonts.py  (찾으면 종료 코드 1)
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ALLOWED = {ROOT / "src" / "shared" / "Config" / "UiTheme.lua"}
PATTERN = re.compile(r"Enum\.Font\.")

found = []
for path in sorted((ROOT / "src").rglob("*.lua")):
    if path in ALLOWED:
        continue
    for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("--", 1)[0]
        if PATTERN.search(code):
            found.append(f"{path.relative_to(ROOT)}:{no}: {line.strip()}")

if found:
    print("Enum.Font 직접 사용 — UiTheme.FONT를 쓸 것:")
    print("\n".join(found))
    sys.exit(1)
print("check_fonts: 0건 (Enum.Font는 UiTheme.FONT 한 곳)")
