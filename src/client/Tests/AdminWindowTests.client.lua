--!strict
-- 관리 창 검증(지시서 #48 4부 — 화면 쪽). 입력 → payload(빠진 필드 없이) · 편의 검사(잘못된 값은 보내지 않음) · 종류 돌리기 · 결과 글 ·
-- Scale만. 관리자 판정 · 서버 검사는 AdminServiceTests(서버).

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local AdminWindowLogic = require(script.Parent.Parent.UI.Logic.AdminWindowLogic)
local AdminWindow = require(script.Parent.Parent.UI.Screens.Window.AdminWindow)

local passed = 0
local failed = 0

local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		warn(string.format("[FAIL] %s%s", name, detail and (" - " .. detail) or ""))
	end
end

local function full(p: any): boolean
	return type(p) == "table" and type(p.action) == "string" and type(p.target) == "number" and type(p.kind) == "string" and type(p.id) == "string"
		and type(p.amount) == "number" and type(p.text) == "string"
end

do
	local g = AdminWindowLogic.build("grant", { target = " 7 ", kind = "ore", id = " 3 ", amount = "5", text = "" })
	local a = AdminWindowLogic.build("announce", { target = "", kind = "blox", id = "", amount = "", text = "  hi  " })
	local i = AdminWindowLogic.build("inspect", { target = "7", kind = "", id = "", amount = "", text = "" })
	check("payload: 지급 · 공지 · 상태 — 빠진 필드 없이 · 앞뒤 공백 정리", full(g) and full(a) and full(i) and g.target == 7 and g.id == "3"
		and g.amount == 5 and a.text == "hi" and i.action == "inspect")
	local bads = {
		AdminWindowLogic.build("grant", { target = "x", kind = "ore", id = "3", amount = "5", text = "" }),
		AdminWindowLogic.build("grant", { target = "7", kind = "nope", id = "3", amount = "5", text = "" }),
		AdminWindowLogic.build("grant", { target = "7", kind = "ore", id = "3", amount = "0", text = "" }),
		AdminWindowLogic.build("grant", { target = "7", kind = "ore", id = "3", amount = "1.5", text = "" }),
		AdminWindowLogic.build("announce", { target = "", kind = "", id = "", amount = "", text = "   " }),
		AdminWindowLogic.build("fly", { target = "7", kind = "ore", id = "3", amount = "5", text = "" }),
	}
	local n = 0
	for idx = 1, 6 do
		if bads[idx] ~= nil then
			n += 1
		end
	end
	check("편의 검사: 대상 · 종류 · 개수 · 빈 공지 · 모르는 행동 6종 → 보내지 않음", n == 0)
	local seen = {}
	local k = AdminConfig.KINDS[1]
	for _ = 1, #AdminConfig.KINDS do
		seen[k] = true
		k = AdminWindowLogic.nextKind(k)
	end
	local all = true
	for _, kind in ipairs(AdminConfig.KINDS) do
		all = all and seen[kind] == true
	end
	check("종류 돌리기: 한 바퀴에 6종 전부 · 처음으로 돌아온다", all and k == AdminConfig.KINDS[1])
	check("결과 글: 성공 · 실패(사유) · 상태 줄 · hello는 글 없음",
		AdminWindowLogic.resultText({ action = "grant", ok = true, reason = "", lines = {} }) == Locale.t("admin.ok")
			and AdminWindowLogic.resultText({ action = "grant", ok = false, reason = "bad_id", lines = {} }) == Locale.t("admin.fail", { reason = "bad_id" })
			and AdminWindowLogic.resultText({ action = "inspect", ok = true, reason = "", lines = { "a", "b" } }) == Locale.t("admin.ok") .. "\na\nb"
			and AdminWindowLogic.resultText({ action = "hello", ok = true, reason = "", lines = {} }) == nil)
end

do
	local sent = {}
	local h = AdminWindow.create({ send = function(p: any)
		table.insert(sent, p)
	end, onClose = function() end })
	h._debug.boxes.target.Text = "7"
	h._debug.boxes.id.Text = "3"
	h._debug.boxes.amount.Text = "5"
	h._debug.press("grant")
	h._debug.boxes.amount.Text = "0"
	h._debug.press("revoke")
	check("창: 지급은 보낸다 · 잘못된 개수는 안 보내고 실패 글", #sent == 1 and sent[1].action == "grant" and sent[1].kind == h._debug.kind()
		and h._debug.result.Text == Locale.t("admin.fail", { reason = "bad_amount" }))
	h.onResult({ action = "grant", ok = true, reason = "", lines = {} })
	check("창: 결과 글 = 완료", h._debug.result.Text == Locale.t("admin.ok"))
	local scaleOnly = true
	for _, obj in ipairs(h.root:GetDescendants()) do
		if obj:IsA("GuiObject") then
			scaleOnly = scaleOnly and obj.Size.X.Offset == 0 and obj.Size.Y.Offset == 0 and obj.Position.X.Offset == 0 and obj.Position.Y.Offset == 0
		end
	end
	check("창: 크기 · 위치 Scale만(Offset 0)", scaleOnly)
	h.root:Destroy()
end

print(string.format("[AdminWindowTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[AdminWindowTests] %d test(s) failed", failed))
end
