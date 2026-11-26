--!strict
-- 지금 쓰는 UI 스킨 — UiTheme.Skin을 덮는 표 하나(2026-11-26 지시서 #39 · docs/UI.md "UI 키트 > 스킨 갈아 끼우기").
-- 빈 표 = 기본 모양(#39 이전 임시 모양 그대로). 1월 템플릿은 이 파일만 바꾼다 — 화면 코드는 손대지 않는다.
--
-- 적는 법(적은 칸만 바뀐다 · 모양은 UiTheme.Skin과 같다):
--   return {
--       font = Enum.Font.FredokaOne,
--       colors = { power = { base = Color3.fromHex("FF8C1A") } },
--       line = { modal = 6 },
--       corner = { cell = UDim.new(0.2, 0) },
--       panel = { frameInset = 0.012 },             -- 틀 그림 두께(화면 높이 대비) — 창 본문이 그만큼 안으로 들어간다
--       images = { card = { id = 1234567890, slice = Rect.new(24, 24, 104, 104) } },
--   }
-- ⚠️ 색을 바꾸면 docs/UI.md "3. 색" 표도 같이 바꾼다(UiTheme 머리 주석). 글꼴은 이 파일 · UiTheme 두 곳만 Enum.Font를 쓸 수 있다(tools/check_fonts.py).

return {}
