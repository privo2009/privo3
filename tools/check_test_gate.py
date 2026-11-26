"""테스트 · 리포트 Studio 게이트 검사 (지시서 #27 T2).

src/ 아래에서
  1. 스크립트 *Tests.server.lua · *Tests.client.lua · *Report.server.lua · *Report.client.lua · TestRunDone.*.lua
     → 머리 주석 · 빈 줄 · --!strict 다음 **첫 실행 문장**이 게이트 한 줄인가
  2. 도구 모듈(src/server/Tools · src/client/Tools)과 Shared/TestRunLogic의 `function X.run(` → 함수 **첫 줄**이 게이트인가
를 본다(#37: 새 경제 플래그 검사는 플래그와 함께 지웠다).
  3. (#39) Studio 전용 플래그 커밋 값 — `local TEST_* = nil` · `local *_ENABLED = false`(테스트 파일 밖 전부) · TestGate.STUDIO_FLAGS 이름은 선언이 있어야 한다 게이트 = `if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end`
(뒤에 주석은 붙어도 된다). 게시된 서버 · 클라에서 테스트 · 리포트가 돌지 않게 하는 줄이다(Shared/TestGate 상단).

새 테스트 · 리포트 파일을 만들면 이 도구를 돌린다(CLAUDE.md "작업 방식").
쓰는 법: python -I tools/check_test_gate.py  (위반이 있으면 종료 코드 1)
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")  # Windows 콘솔(cp949)에서도 — · 한글이 깨지지 않게

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
GATE = 'if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end'
SCRIPT_PATTERNS = ("*Tests.server.lua", "*Tests.client.lua", "*Report.server.lua", "*Report.client.lua", "TestRunDone.*.lua")
RUN_DIRS = (SRC / "server" / "Tools", SRC / "client" / "Tools")
RUN_EXTRA = (SRC / "shared" / "TestRunLogic.lua",)
RUN_DEF = re.compile(r"^function \w+\.run\(")


def is_gate(line: str) -> bool:
    code = line.strip()
    if not code.startswith(GATE):
        return False
    rest = code[len(GATE):].strip()
    return rest == "" or rest.startswith("--")


def first_statement(lines):
    for no, line in enumerate(lines, 1):
        s = line.strip()
        if s == "" or s.startswith("--"):
            continue
        return no, line
    return None, None


violations = []
scripts = sorted({p for pat in SCRIPT_PATTERNS for p in SRC.rglob(pat)})
for path in scripts:
    lines = path.read_text(encoding="utf-8").splitlines()
    no, line = first_statement(lines)
    if line is None or not is_gate(line):
        violations.append(f"{path.relative_to(ROOT)}:{no}: 첫 실행 문장이 게이트가 아니다 — {(line or '').strip()[:80]}")

runs = 0
modules = sorted({p for d in RUN_DIRS for p in d.glob("*.lua")} | set(RUN_EXTRA))
for path in modules:
    lines = path.read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lines):
        if RUN_DEF.match(line):
            runs += 1
            _, body = first_statement(lines[i + 1:])
            if body is None or not is_gate(body):
                violations.append(f"{path.relative_to(ROOT)}:{i + 1}: run()의 첫 줄이 게이트가 아니다 — {(body or '').strip()[:80]}")

# 3. Studio 전용 플래그 커밋 값(지시서 #39): `local TEST_*` = nil · `local *_ENABLED` = false. TestGate.STUDIO_FLAGS의 이름은 꼭 있어야 한다
FLAG_TEST = re.compile(r"^local (TEST_[A-Z0-9_]+)\s*(?::[^=]+)?=\s*(.+?)\s*(--.*)?$")
FLAG_ENABLED = re.compile(r"^local ([A-Z0-9_]+_ENABLED)\s*(?::[^=]+)?=\s*(.+?)\s*(--.*)?$")
REQUIRED_FLAGS = set(re.findall(r'"([A-Z0-9_]+)"', re.search(r"TestGate\.STUDIO_FLAGS = \{([^}]*)\}",
                                                            (SRC / "shared" / "TestGate.lua").read_text(encoding="utf-8")).group(1)))
flags = {}
for path in sorted(SRC.rglob("*.lua")):
    if path.name.endswith(("Tests.server.lua", "Tests.client.lua")):
        continue
    for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for pat, want in ((FLAG_TEST, "nil"), (FLAG_ENABLED, "false")):
            m = pat.match(line)
            if m:
                flags[m.group(1)] = flags.get(m.group(1), 0) + 1
                if m.group(2) != want:
                    violations.append(f"{path.relative_to(ROOT)}:{no}: 플래그 {m.group(1)} 커밋 값이 {want}가 아니다 — {m.group(2)}")
for name in sorted(REQUIRED_FLAGS - set(flags)):
    violations.append(f"TestGate.STUDIO_FLAGS의 {name} 선언(local {name} = nil)을 찾지 못했다")

if violations:
    print(f"check_test_gate: 위반 {len(violations)}건")
    print("\n".join(violations))
    sys.exit(1)
print(f"check_test_gate: 위반 0건 (스크립트 {len(scripts)}개 · 도구 run() {runs}개 — 전부 첫 줄이 TestGate · 플래그 {len(flags)}개 전부 꺼짐)")
