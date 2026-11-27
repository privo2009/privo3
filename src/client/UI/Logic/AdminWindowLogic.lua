--!strict
-- 관리 창 순수 로직(지시서 #48 4부). 입력칸 글자 → AdminRequest payload · 결과 → 화면 글. 판정은 서버가 다시 한다(여기는 편의 검사).
-- payload는 빠진 필드 없이 { action, target, kind, id, amount, text }(Remotes "nil이면 키가 사라진다").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local AdminWindowLogic = {}

export type Fields = { target: string, kind: string, id: string, amount: string, text: string }

-- 종류 고르기: 다음 종류(끝이면 처음)
function AdminWindowLogic.nextKind(kind: string): string
	local list = AdminConfig.KINDS
	for i, k in ipairs(list) do
		if k == kind then
			return list[(i % #list) + 1]
		end
	end
	return list[1]
end

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- 행동 하나의 payload. 못 만들면 (nil, 사유 코드)
function AdminWindowLogic.build(action: string, f: Fields): (any?, string?)
	if not AdminConfig.ACTIONS[action] then
		return nil, "bad_action"
	end
	if action == "announce" then
		local text = trim(f.text)
		if text == "" then
			return nil, "bad_text"
		end
		return { action = action, target = 0, kind = "", id = "", amount = 0, text = text }, nil
	end
	local target = tonumber(trim(f.target))
	if target == nil or target % 1 ~= 0 or target <= 0 then
		return nil, "bad_target"
	end
	if action == "inspect" then
		return { action = action, target = target, kind = "", id = "", amount = 0, text = "" }, nil
	end
	if not AdminConfig.isKind(f.kind) then
		return nil, "bad_kind"
	end
	local amount = tonumber(trim(f.amount))
	if amount == nil or amount % 1 ~= 0 or amount < 1 then
		return nil, "bad_amount"
	end
	return { action = action, target = target, kind = f.kind, id = trim(f.id), amount = amount, text = "" }, nil
end

-- AdminResult → 화면 글(줄 묶음). hello는 nil(창을 만들라는 신호일 뿐)
function AdminWindowLogic.resultText(payload: any): string?
	if type(payload) ~= "table" or type(payload.action) ~= "string" or payload.action == "hello" then
		return nil
	end
	local head = if payload.ok == true then Locale.t("admin.ok") else Locale.t("admin.fail", { reason = tostring(payload.reason) })
	local lines = { head }
	if type(payload.lines) == "table" then
		for _, line in ipairs(payload.lines) do
			if type(line) == "string" then
				table.insert(lines, line)
			end
		end
	end
	return table.concat(lines, "\n")
end

return AdminWindowLogic
