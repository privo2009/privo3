--!strict
-- 서버 전체 알림(ServerNotice) · 업데이트 중 화면 검증(지시서 #48 1부 소프트 셧다운 · 4부 관리자 공지).
-- 알림 판정(모양이 틀리면 아무것도 안 함 · 글 자르기) · 대기실 도착 판정(순간이동 데이터) · 화면이 맨 위에서 입력을 막는가 · 문장.

if not require(game:GetService("ReplicatedStorage").Shared.TestGate).shouldRun() then return end -- Studio 전용(지시서 #27 T1)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerNoticeLogic = require(script.Parent.Parent.UI.Logic.ServerNoticeLogic)
local UpdateScreen = require(script.Parent.Parent.UI.Screens.Overlay.UpdateScreen)
local OverlayParts = require(script.Parent.Parent.UI.Screens.Overlay.OverlayParts)
local SoftShutdownConfig = require(ReplicatedStorage.Shared.Config.SoftShutdownConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

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

do
	local u = ServerNoticeLogic.decide({ kind = "updating", text = "", sec = 0 })
	local r = ServerNoticeLogic.decide({ kind = "restart", text = "", sec = 42.7 })
	local a = ServerNoticeLogic.decide({ kind = "announce", text = "hello", sec = 0 })
	check("알림: updating · restart(초 내림) · announce(글)", u ~= nil and u.kind == "updating" and r ~= nil and r.kind == "restart" and r.sec == 42
		and a ~= nil and a.kind == "announce" and a.text == "hello")
	local bad = { nil, 5, "x", {}, { kind = 3 }, { kind = "nope" }, { kind = "announce", text = "" }, { kind = "announce", text = 7 } }
	local leaked = 0
	for i = 1, 8 do
		if ServerNoticeLogic.decide(bad[i]) ~= nil then
			leaked += 1
		end
	end
	check("알림: 모양이 틀리면(8종) 아무것도 안 함", leaked == 0, tostring(leaked))
	local nan = ServerNoticeLogic.decide({ kind = "restart", text = "", sec = 0 / 0 })
	local long = ServerNoticeLogic.decide({ kind = "announce", text = string.rep("a", 500), sec = 0 })
	check("알림: 이상한 초는 0 · 긴 공지는 상한에서 자름", nan ~= nil and nan.sec == 0 and long ~= nil and #long.text == ServerNoticeLogic.MAX_TEXT)
end

do
	local key = SoftShutdownConfig.TELEPORT_DATA_KEY
	check("대기실 도착: 순간이동 데이터에 표시(true)일 때만",
		ServerNoticeLogic.arrivedForUpdate({ [key] = true }, key) and not ServerNoticeLogic.arrivedForUpdate(nil, key)
			and not ServerNoticeLogic.arrivedForUpdate({ [key] = "yes" }, key) and not ServerNoticeLogic.arrivedForUpdate({}, key))
end

do
	local h = UpdateScreen.create()
	local label = h.root:FindFirstChild("Text") :: TextLabel?
	check("업데이트 화면: 화면 전체 · 입력 막음 · 알림층 위(오류 · 토스트보다 위)", h.root.Size == UDim2.fromScale(1, 1) and h.root.Active == true
		and h.root.ZIndex > OverlayParts.Z.notice and h.root.BackgroundTransparency == 0)
	check("업데이트 화면: 글 = overlay.updating", label ~= nil and label.Text == Locale.t("overlay.updating") and label.Text ~= "")
	h.root:Destroy()
	local gui = UpdateScreen.teleportGui()
	check("순간이동 화면: ScreenGui 하나에 같은 화면", gui:IsA("ScreenGui") and gui:FindFirstChild("UpdateScreen") ~= nil)
	gui:Destroy()
end

print(string.format("[ServerNoticeTests] %d passed, %d failed", passed, failed))
if failed > 0 then
	error(string.format("[ServerNoticeTests] %d test(s) failed", failed))
end
