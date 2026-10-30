--!strict
-- 아우라 창 (큰 창, Window 층 — 단일 오픈 · 배경 흐리게는 ScreenController). Phase 7 지시서 #11 A5.
-- 메뉴 레일 넷째 칸 "아우라"(screenName "Aura")가 연다.
--
-- 위에서부터:
--   팩 탭 1~3(그 월드의 팩 — 고른 탭은 하늘, 나머지 회색, 잠긴 팩은 "팩 N 잠김") · 오른쪽 끝 "칭호" 버튼(칭호 창 — 단일 오픈)
--   안내 줄(고른 팩 롤 비용 또는 해금 조건) · 오른쪽 "행운 ×N 적용"(P3)
--   카드 4장(일반 → 전설): 이름(희귀도 색) · 등급 · "힘·데미지 ×m" · 실제 확률 % · 보유/장착 · 장착 버튼
--   뽑기 버튼(하늘 btn_blue + 비용) · 그 아래 잠긴 이유 · 오른쪽 상태 문구
-- 캐릭터 미리보기는 두지 않는다 — ViewportFrame에서는 파티클이 그려지지 않는다(A5). 장착하면 실제 캐릭터에 보인다.
-- 값 · 문구는 UI/Logic/AuraWindowLogic(순수). 확인 단계 없음(상점 S8과 같다) — 결과 대기 중 · 롤 시계 동안 뽑기 버튼을 잠근다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage.Shared.Config.UiTheme)
local AuraConfig = require(ReplicatedStorage.Shared.Config.AuraConfig)
local Panel = require(script.Parent.Parent.Parent.Components.Panel)
local Button = require(script.Parent.Parent.Parent.Components.Button)
local WindowParts = require(script.Parent.Parent.Parent.Components.WindowParts)
local Store = require(script.Parent.Parent.Parent.Store)
local AuraWindowLogic = require(script.Parent.Parent.Parent.Logic.AuraWindowLogic)
local TitleWindowLogic = require(script.Parent.Parent.Parent.Logic.TitleWindowLogic)

local AuraWindow = {}

-- 본문 기준 배치. Claude가 정했다(docs/UI.md "지시서 #11" 절).
local TAB_H = 0.1
local TAB_W = 0.19
local TAB_GAP = 0.015
local MAX_TABS = 3
local TITLE_BTN_W = 0.16
local INFO_Y, INFO_H = 0.115, 0.07
local CARD_Y, CARD_H = 0.2, 0.54
local CARD_GAP = 0.02
local CARD_W = (1 - CARD_GAP * 3) / 4
local ROLL_Y, ROLL_H, ROLL_W = 0.76, 0.12, 0.4
local FOOT_Y, FOOT_H = 0.89, 0.09
local STATUS_X = 0.42
AuraWindow.Layout = { CARD_Y = CARD_Y, CARD_H = CARD_H, CARD_W = CARD_W, ROLL_Y = ROLL_Y }

export type Deps = {
	store: any?,
	sendRequest: (payload: { action: string, pack: number?, auraId: string? }) -> (),
	onClose: () -> (),
	openTitles: () -> (),
	now: (() -> number)?,
}

type CardParts = {
	frame: Frame,
	name: TextLabel,
	tierName: TextLabel,
	mult: TextLabel,
	chance: TextLabel,
	status: TextLabel,
	button: Button.ButtonHandle,
	buttonLabel: TextLabel,
	hit: TextButton,
}

type TabParts = { button: Button.ButtonHandle, label: TextLabel, hit: TextButton }

export type Handle = {
	root: Frame,
	refresh: () -> (),
	onResult: (any) -> (),
	_debug: {
		pressRoll: () -> (),
		pressTab: (index: number) -> (),
		pressEquip: (index: number) -> (),
		pressTitles: () -> (),
		cards: { CardParts },
		tabs: { TabParts },
		view: () -> { AuraWindowLogic.Card },
		shownPack: () -> number,
		rollButton: Button.ButtonHandle,
		rollLabel: TextLabel,
		rollFoot: TextLabel,
		info: TextLabel,
		luck: TextLabel,
		status: TextLabel,
	},
}

function AuraWindow.create(deps: Deps): Handle
	local source: any = deps.store or Store
	local now = deps.now or os.clock
	local panel = Panel.create("Large", AuraWindowLogic.TITLE)
	panel.root.Name = "AuraWindow"
	local body = panel.body
	local raise: { Instance } = { panel.closeButton.root }

	local function makeButton(name: string, color: Button.ColorName, x: number, y: number, w: number, h: number, parent: Instance, text: string)
		local b = Button.create({ size = "Small", color = color, widthScale = w, heightScale = h })
		b.root.Name = name
		b.root.Position = UDim2.fromScale(x, y)
		b.root.ZIndex = WindowParts.Z_BUTTON
		b.root.Parent = parent
		local label, hit = WindowParts.decorateButton(b, text)
		table.insert(raise, b.root)
		return b, label, hit
	end

	-- 팩 탭 (선택 표시는 색 — 고른 탭 하늘 / 나머지 회색. 버튼 색만 바꾸면 Button 내부 그림을 다시 만들어야 해서 탭마다 두 벌을 둔다)
	local tabs: { TabParts } = {}
	local tabBlue: { Button.ButtonHandle } = {}
	for i = 1, MAX_TABS do
		local x = (i - 1) * (TAB_W + TAB_GAP)
		local gray, label, hit = makeButton("Tab" .. i, "gray", x, 0, TAB_W, TAB_H, body, "")
		local blue = Button.create({ size = "Small", color = "blue", widthScale = 1, heightScale = 1 })
		blue.root.Name = "Selected"
		blue.root.Position = UDim2.fromScale(0, 0)
		blue.root.ZIndex = WindowParts.Z_BUTTON
		blue.root.Visible = false
		blue.root.Parent = gray.root
		tabs[i] = { button = gray, label = label, hit = hit }
		tabBlue[i] = blue
	end
	local _titleBtn, _titleLabel, titleHit = makeButton("TitleButton", "gray", 1 - TITLE_BTN_W, 0, TITLE_BTN_W, TAB_H, body, AuraWindowLogic.TITLE_BUTTON_TEXT)

	local info = WindowParts.makeText("Info", body, "small", 0, INFO_Y, 0.6, INFO_H)
	local luck = WindowParts.makeText("LuckLine", body, "small", 0.6, INFO_Y, 0.4, INFO_H, Enum.TextXAlignment.Right)

	-- 카드 4장
	local cards: { CardParts } = {}
	for i = 1, AuraConfig.TIER_COUNT do
		local frame = Instance.new("Frame")
		frame.Name = "Card" .. i
		frame.Position = UDim2.fromScale((i - 1) * (CARD_W + CARD_GAP), CARD_Y)
		frame.Size = UDim2.fromScale(CARD_W, CARD_H)
		frame.BackgroundColor3 = UiTheme.Colors.neutral.dark
		frame.BorderSizePixel = 0
		frame.ZIndex = 3
		frame.Parent = body
		local name = WindowParts.makeText("Name", frame, "medium", 0.05, 0.03, 0.9, 0.16, Enum.TextXAlignment.Center)
		local tierName = WindowParts.makeText("Tier", frame, "small", 0.05, 0.2, 0.9, 0.11, Enum.TextXAlignment.Center)
		local mult = WindowParts.makeText("Mult", frame, "small", 0.05, 0.32, 0.9, 0.11, Enum.TextXAlignment.Center)
		local chance = WindowParts.makeText("Chance", frame, "medium", 0.05, 0.45, 0.9, 0.15, Enum.TextXAlignment.Center)
		local status = WindowParts.makeText("Status", frame, "small", 0.05, 0.62, 0.9, 0.11, Enum.TextXAlignment.Center)
		local button, buttonLabel, hit = makeButton("EquipButton", "blue", 0.08, 0.76, 0.84, 0.2, frame, AuraWindowLogic.EQUIP_TEXT)
		cards[i] = { frame = frame, name = name, tierName = tierName, mult = mult, chance = chance, status = status, button = button, buttonLabel = buttonLabel, hit = hit }
	end

	local rollButton, rollLabel, rollHit = makeButton("RollButton", "blue", 0, ROLL_Y, ROLL_W, ROLL_H, body, AuraWindowLogic.ROLL_TEXT)
	local rollFoot = WindowParts.makeText("RollFoot", body, "small", 0, FOOT_Y, ROLL_W, FOOT_H, Enum.TextXAlignment.Center)
	local status = WindowParts.makeText("Status", body, "small", STATUS_X, ROLL_Y, 1 - STATUS_X, ROLL_H, Enum.TextXAlignment.Center)
	status.TextWrapped = true

	local closeHit = WindowParts.hitArea(panel.closeButton.root)
	WindowParts.raiseButtons(raise)

	local pending = TitleWindowLogic.newPending()
	local rollCooldownUntil = -math.huge
	local resultText: string? = nil
	local view: { AuraWindowLogic.Card } = {}
	local tabView: { AuraWindowLogic.PackTab } = {}
	-- 화면에서 고른 팩(서버 selectPack 응답 전에도 바로 바뀌게). 서버 값이 오면 그것을 따른다.
	local localPack: number? = nil

	local function shown(): number
		return localPack or AuraWindowLogic.shownPack(source.get("auras"))
	end

	local function render()
		local t = now()
		local summary = source.get("auras")
		local packId = shown()
		tabView = AuraWindowLogic.packs(summary, source.get("lifetimeBlox"))
		for i, parts in ipairs(tabs) do
			local tab = tabView[i]
			parts.button.root.Visible = tab ~= nil
			tabBlue[i].root.Visible = tab ~= nil and tab.packId == packId
			if tab ~= nil then
				parts.label.Text = tab.label
				if tab.packId == packId then
					info.Text = tab.infoText
				end
			end
		end
		luck.Text = AuraWindowLogic.luckText(source.get("upgrades"), source.get("shop"))
		view = AuraWindowLogic.cards(summary, source.get("upgrades"), packId, source.get("shop"))
		for i, parts in ipairs(cards) do
			local c = view[i]
			if c ~= nil then
				parts.name.Text = c.name
				parts.name.TextColor3 = UiTheme.rarityColor(c.rarityTier)
				parts.tierName.Text = c.tierName
				parts.tierName.TextColor3 = UiTheme.rarityColor(c.rarityTier)
				parts.mult.Text = c.multText
				parts.chance.Text = c.chanceText
				parts.status.Text = c.statusText
				parts.buttonLabel.Text = c.buttonText
				parts.button.setDisabled(not c.canEquip or pending.isPending("equip", t))
			end
		end
		local roll = AuraWindowLogic.rollState(summary, source.get("lifetimeBlox"), source.get("blox"), packId)
		rollLabel.Text = roll.buttonText
		rollButton.setDisabled(not roll.canRoll or pending.isPending("roll", t) or t < rollCooldownUntil)
		rollFoot.Text = roll.footText
		status.Text = resultText or ""
	end

	local function send(key: string, payload: { action: string, pack: number?, auraId: string? })
		if not pending.tryBegin(key, now()) then
			return
		end
		resultText = nil
		deps.sendRequest(payload)
		render()
		task.delay(TitleWindowLogic.PENDING_TIMEOUT_SEC + 0.05, render)
	end

	local function pressRoll()
		render()
		local packId = shown()
		if not AuraWindowLogic.rollState(source.get("auras"), source.get("lifetimeBlox"), source.get("blox"), packId).canRoll or now() < rollCooldownUntil then
			return
		end
		send("roll", { action = "roll", pack = packId })
	end

	local function pressTab(index: number)
		local tab = tabView[index]
		if tab == nil or tab.packId == shown() then
			return
		end
		localPack = tab.packId
		resultText = nil
		render()
		-- 저장은 기다리지 않는다(표시 선택이라 대기 잠금 없이 보낸다 — 서버 빈도 상한이 막는다)
		deps.sendRequest({ action = "selectPack", pack = tab.packId })
	end

	local function pressEquip(index: number)
		render()
		local c = view[index]
		if c ~= nil and c.canEquip then
			send("equip", { action = "equip", auraId = c.id })
		end
	end

	local function onResult(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local key = AuraWindowLogic.pendingKeyOf(payload)
		if key == nil then
			return
		end
		if key == "selectPack" then
			if not payload.ok then
				localPack = nil -- 서버가 거부하면 저장된 값으로 되돌린다
				render()
			end
			return
		end
		pending.finish(key)
		if key == "roll" then
			rollCooldownUntil = now() + AuraConfig.ROLL_INTERVAL_SEC
			task.delay(AuraConfig.ROLL_INTERVAL_SEC + 0.05, render)
		end
		resultText = AuraWindowLogic.resultText(payload)
		render()
	end

	for i, parts in ipairs(tabs) do
		parts.hit.Activated:Connect(function()
			pressTab(i)
		end)
	end
	for i, parts in ipairs(cards) do
		parts.hit.Activated:Connect(function()
			pressEquip(i)
		end)
	end
	rollHit.Activated:Connect(pressRoll)
	titleHit.Activated:Connect(function()
		deps.openTitles()
	end)
	closeHit.Activated:Connect(function()
		resultText = nil
		render()
		deps.onClose()
	end)
	source.subscribe("auras", function()
		local summary = source.get("auras")
		if localPack ~= nil and type(summary) == "table" and summary.selectedPack == localPack then
			localPack = nil -- 서버 값이 따라왔다
		end
		render()
	end)
	source.subscribe("upgrades", render)
	source.subscribe("shop", render) -- 행운 패스 · 행운 포션 → 현재 확률(지시서 #16)
	source.subscribe("blox", render)
	source.subscribe("lifetimeBlox", render)

	render()

	return {
		root = panel.root,
		refresh = render,
		onResult = onResult,
		_debug = {
			pressRoll = pressRoll,
			pressTab = pressTab,
			pressEquip = pressEquip,
			pressTitles = function()
				deps.openTitles()
			end,
			cards = cards,
			tabs = tabs,
			view = function()
				return view
			end,
			shownPack = shown,
			rollButton = rollButton,
			rollLabel = rollLabel,
			rollFoot = rollFoot,
			info = info,
			luck = luck,
			status = status,
		},
	}
end

return AuraWindow
