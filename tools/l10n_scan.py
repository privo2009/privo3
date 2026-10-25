"""단계 0 / 단계 5 — 화면에 보일 수 있는 한글 문자열 리터럴 조사 (지시서 #L1).

사용:
  python3 -I tools/l10n_scan.py            요약 (분류별 개수)
  python3 -I tools/l10n_scan.py --list     전부 나열
  python3 -I tools/l10n_scan.py --check    화면 대상 0이 아니면 exit 1

제외: 주석 · Strings 데이터 파일 · 개발 로그(print · warn · error · assert 인자) ·
테스트 파일(*Tests.*.lua — 따로 센다) · 서버 리포트/도구(Server/Tools · *Report* · Config/TestPresets — Studio 로그 전용).
server_internal(서버 내부 사유 문장 — 검증 오류 등, 로그로만 간다)은 화면 대상이 아니다(K5 — 단계 0에서 경로를 따라가 확인).
"""
import os
import re
import sys

sys.dont_write_bytecode = True  # tools/__pycache__를 만들지 않는다
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luau_lex import tokens  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HANGUL = re.compile(r"[가-힣ㄱ-ㆎ]")
LOG_CALLS = {"print", "warn", "error", "assert", "log", "logf", "verify", "dprint", "debugLog"}
STRINGS_DATA = "src/shared/Localization/Strings.lua"
LOCALIZATION_DIR = "src/shared/Localization/"  # Strings(데이터) · Locale(로그 문장만) — 조사 대상이 아니다


def enclosing_call(src, pos):
    """pos 를 감싸는 가장 가까운 열린 괄호 앞의 이름. 없으면 None."""
    depth = 0
    i = pos - 1
    while i >= 0:
        ch = src[i]
        if ch == ")":
            depth += 1
        elif ch == "(":
            if depth == 0:
                m = re.search(r"([A-Za-z_][A-Za-z0-9_.:]*)\s*$", src[:i])
                return m.group(1) if m else ""
            depth -= 1
        elif ch == "\n" and src[max(0, i - 400):i].count("\n") > 30:
            return None
        i -= 1
    return None


def is_log(src, start):
    # 같은 호출 묶음 안에서 바깥쪽으로 올라가며 로그 함수를 찾는다 (string.format 안 등)
    pos = start
    for _ in range(4):
        name = enclosing_call(src, pos)
        if name is None:
            return False
        base = name.split(".")[-1].split(":")[-1]
        if base in LOG_CALLS or name.endswith("Log") or base.lower().endswith("log"):
            return True
        idx = src.rfind(name, 0, pos)
        if idx < 0:
            return False
        pos = idx
    return False


def classify(rel):
    p = rel.replace("\\", "/")
    if re.search(r"Tests?\.(server|client)\.lua$", p) or p.endswith("TestHelpers.lua"):
        return "test"
    if "/server/Tools/" in p or "/client/Tools/" in p or "Report" in os.path.basename(p) or p.endswith("Config/TestPresets.lua"):
        return "devtool"
    if "/shared/Config/" in p:
        return "config"
    if "/World/" in p or "View.lua" in p or "Billboard" in p:
        return "world3d"
    if "/Screens/Overlay/" in p or "Toast" in p or "Feedback" in p or "Notice" in p:
        return "overlay"
    if "/Screens/Hud/" in p:
        return "hud"
    if "/Screens/Window/" in p or "/UI/Logic/" in p:
        return "window"
    if p.startswith("src/server/"):
        return "server"
    if p.startswith("src/client/"):
        return "client_other"
    return "shared_other"


# server_internal 은 화면에 안 나가는 서버 내부 사유 문장(검증 오류 등 — 로그로만 간다).
# 단계 0에서 경로를 따라가 확인했고 K5 대상이 아니다. 개수만 따로 보인다.
SCREEN_KINDS = ["hud", "world3d", "overlay", "window", "config", "client_other",
                "shared_other", "server_kick"]


def masked(src):
    """주석 · 문자열 안의 괄호가 호출 추적을 흐리지 않게 내용을 공백으로 지운다."""
    out = list(src)
    for _, _, _, start, end in tokens(src):
        for i in range(start + 1, min(end - 1, len(out))):
            if out[i] != "\n":
                out[i] = " "
    return "".join(out)


def scan():
    found = []
    for base, _, files in os.walk(os.path.join(ROOT, "src")):
        for f in sorted(files):
            if not f.endswith(".lua"):
                continue
            path = os.path.join(base, f)
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            if rel == STRINGS_DATA or rel.startswith(LOCALIZATION_DIR):
                continue
            src = open(path, encoding="utf-8").read()
            kind = classify(rel)
            msrc = masked(src)
            for tk, text, line, start, _ in tokens(src):
                if tk == "comment" or not HANGUL.search(text):
                    continue
                k = "log" if is_log(msrc, start) else kind
                if k == "server":
                    k = "server_kick" if enclosing_call(msrc, start) == "player:Kick" else "server_internal"
                found.append((k, rel, line, text))
    return found


def main():
    found = scan()
    counts = {}
    for k, *_ in found:
        counts[k] = counts.get(k, 0) + 1
    if "--list" in sys.argv:
        for k, rel, line, text in found:
            if k in SCREEN_KINDS or "--all" in sys.argv:
                print(f"{k:12} {rel}:{line}: {text[:80]!r}")
    screen = sum(counts.get(k, 0) for k in SCREEN_KINDS)
    print("--- 분류별 한글 리터럴 수 ---")
    for k in SCREEN_KINDS + ["server_internal", "test", "devtool", "log"]:
        print(f"{k:12} {counts.get(k, 0)}")
    print(f"화면 대상 합계 {screen} (server_internal · test · devtool · log 제외)")
    if "--check" in sys.argv and screen:
        sys.exit(1)


if __name__ == "__main__":
    main()
