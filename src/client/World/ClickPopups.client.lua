--!strict
-- 클릭 +숫자 팝업 (Phase 6 지시서 #8 2a). 클릭으로 실제로 붙은 힘을 캐릭터 머리 위에 잠깐 띄운다.
-- 값은 서버 확정값(PlayerState strength)의 증가분이다 — 판정 · 문구는 UI/Logic/FeedbackLogic.
-- 기구 위면 그 배수가 이미 들어 있고(서버 GymService가 곱했다), 배수도 옆에 적는다(GymLayout.resolve — 서버와 같은 함수).
--
-- 클라 전용이다(CLAUDE.md 절대 규칙 4 — 파티클 · 연출은 클라). 풀링한다: 빌보드 POPUP_POOL_SIZE개를 처음에 한 번 만들고
-- 돌려 쓴다. 움직임은 Heartbeat 하나에서 직접 계산한다 — 팝업마다 Tween을 만들지 않는다(반복 루프에서 Instance 생성 금지).
-- 크기는 studs(BillboardGui) — 3D 오브젝트에 붙는 표시라 화면 금지 구역 규칙의 예외다(docs/UI.md "2. 세이프존 > 규칙").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local TextScale = require(ReplicatedStorage.Shared.Config.TextScale)
local GymLayout = require(ReplicatedStorage.Shared.GymLayout)
local ShopEffectsLogic = require(ReplicatedStorage.Shared.ShopEffectsLogic)
local FeedbackLogic = require(script.Parent.Parent.UI.Logic.FeedbackLogic)
local Store = require(script.Parent.Parent.UI.Store)
local PlayerStateClient = require(script.Parent.Parent.Net.PlayerStateClient)

type BigNumber = BigNum.BigNumber

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 빌보드 크기(studs)와 머리 위 시작 높이. Claude가 정한 시각 값(세션 로그).
local POPUP_SIZE = Vector2.new(8, 1.8)
local START_HEIGHT = 2.5 -- HumanoidRootPart(지면 위 약 3) 기준 — 머리 바로 위에서 시작해 기구 표시(지면 위 10) 아래까지 오른다
local JITTER_X = 1.5 -- 연달아 뜰 때 겹치지 않게 좌우로 흩는다

type Popup = {
	gui: BillboardGui,
	label: TextLabel,
	startedAt: number?,
	jitter: number,
}

local pool: { Popup } = {}
for i = 1, FeedbackLogic.POPUP_POOL_SIZE do
	local gui = Instance.new("BillboardGui")
	gui.Name = string.format("ClickPopup_%02d", i)
	-- K10(#L2): 번역은 Strings(Locale.t)가 한다 — 로블록스 자동 번역이 우리 번역 위에 한 번 더 덮이지 않게 끈다
	gui.AutoLocalize = false
	gui.Size = UDim2.fromScale(POPUP_SIZE.X, POPUP_SIZE.Y)
	-- AlwaysOnTop을 켜지 않는다. 머리 위라 가릴 것이 거의 없고, 다른 3D 안내(WorldLabels)와 같은 방식이다
	-- (2026-10-23 Play: 켜면 Studio screen_capture에 안 찍혀 검증할 수 없었다).
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = UiTheme.FONT
	label.TextColor3 = UiTheme.Colors.power.light
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = TextScale.Levels.large.maxTextSize
	size.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui

	gui.Parent = playerGui
	table.insert(pool, { gui = gui, label = label, startedAt = nil, jitter = 0 })
end

local nextIndex = 1

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function show(gain: BigNumber)
	local root = rootPart()
	if root == nil then
		return
	end
	-- 로벅스로 열린 기구(공허 게임패스 — 지시서 #16)도 서버와 같은 판정(GymLayout.shopUnlocked)
	local gym = GymLayout.resolve(root.Position, Store.get("rebirths"),
		GymLayout.shopUnlocked(nil, ShopEffectsLogic.fromSummary(Store.get("shop")).owns))
	local popup = pool[nextIndex]
	nextIndex = nextIndex % #pool + 1

	popup.label.Text = FeedbackLogic.popupText(gain, gym.multiplier)
	popup.label.TextColor3 = if gym.multiplier > 1 then UiTheme.Colors.cashout.light else UiTheme.Colors.power.light
	popup.jitter = (math.random() * 2 - 1) * JITTER_X
	popup.startedAt = os.clock()
	popup.gui.Adornee = root
	popup.gui.StudsOffset = Vector3.new(popup.jitter, START_HEIGHT, 0)
	popup.label.TextTransparency = 0
	popup.gui.Enabled = true
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, popup in ipairs(pool) do
		local started = popup.startedAt
		if started ~= nil then
			local progress = (now - started) / FeedbackLogic.POPUP_LIFETIME_SEC
			if progress >= 1 then
				popup.startedAt = nil
				popup.gui.Enabled = false
			else
				local rise, transparency = FeedbackLogic.popupFrame(progress)
				popup.gui.StudsOffset = Vector3.new(popup.jitter, START_HEIGHT + rise, 0)
				popup.label.TextTransparency = transparency
				for _, child in ipairs(popup.label:GetChildren()) do
					if child:IsA("UIStroke") then
						child.Transparency = transparency
					end
				end
			end
		end
	end
end)

-- 첫 스냅샷(더미 → 서버 값)은 증가분이 아니다. 첫 상태를 받은 뒤의 값부터 비교한다.
local prev: BigNumber? = nil
local primed = false
PlayerStateClient.onFirstState(function()
	prev = Store.get("strength")
	primed = true
end)

Store.subscribe("strength", function(value: BigNumber)
	if not primed then
		return
	end
	local gain = FeedbackLogic.gainOf(prev, value)
	prev = value
	if gain ~= nil then
		show(gain)
	end
end)
