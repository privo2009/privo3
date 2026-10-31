--!strict
-- 코드 입력 창의 결과 문구 (지시서 #20 C4 · C6 — DESIGN.md 9장 "코드 입력"). 순수 모듈 — 화면은 Screens/Window/CodeWindow.
--
-- ⚠️ 입력 글자를 받지 않는다 — 결과 문구는 서버 결과(CodeResult: ok · reason · rewards · blox)와 Strings 고정 문장으로만 만든다(C4).
--    그래서 이 모듈의 어떤 함수도 입력칸의 Text를 인자로 받지 않는다(CodeWindowTests가 잰다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BigNum = require(ReplicatedStorage.Shared.BigNum)
local Formatter = require(ReplicatedStorage.Shared.Formatter)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Names = require(ReplicatedStorage.Shared.Localization.Names)

local CodeWindowLogic = {}

CodeWindowLogic.PENDING_TIMEOUT_SEC = 3
CodeWindowLogic.SEPARATOR = " · "

-- 받은 보상 목록 → "Power Potion x2 · Damage Potion x2". 블럭스는 서버가 보낸 합(blox)을 쓴다.
function CodeWindowLogic.rewardsText(payload: any): string
	local parts: { string } = {}
	local addedBlox = false
	local rewards = if type(payload) == "table" and type(payload.rewards) == "table" then payload.rewards else {}
	for _, r in ipairs(rewards) do
		if type(r) == "table" then
			if r.type == "potion" and type(r.kind) == "string" and r.kind ~= "" then
				table.insert(parts, Names.boost(r.kind) .. " " .. Locale.t("daily.reward.count", { count = tonumber(r.count) or 0 }))
			elseif r.type == "bloxScaled" and not addedBlox then
				local b = payload.blox
				if type(b) == "table" and type(b.m) == "number" and type(b.e) == "number" then
					table.insert(parts, Formatter.format(BigNum.new(b.m, b.e)) .. " " .. Locale.t("daily.reward.blox"))
					addedBlox = true
				end
			elseif r.type == "pet" and type(r.petId) == "string" and r.petId ~= "" then
				table.insert(parts, Names.pet(r.petId))
			end
		end
	end
	return table.concat(parts, CodeWindowLogic.SEPARATOR)
end

-- 결과 → 창 문구. 사유 코드는 서버 CodeService · RewardService와 같은 문자열.
function CodeWindowLogic.resultText(payload: any): string?
	if type(payload) ~= "table" or type(payload.ok) ~= "boolean" then
		return nil
	end
	if payload.ok then
		return Locale.t("code.result.ok", { rewards = CodeWindowLogic.rewardsText(payload) })
	end
	local reason = tostring(payload.reason)
	if reason == "not_found" or reason == "already_redeemed" or reason == "expired" or reason == "too_many_attempts" then
		return Locale.t("code.reason." .. reason)
	elseif reason == "storage_full" then
		return Locale.t("daily.reason.storage_full")
	elseif reason == "rate_limited" then
		return Locale.t("common.reason.rate_limited")
	elseif reason == "no_profile" then
		return Locale.t("common.reason.no_profile")
	end
	return Locale.t("code.reason.failed")
end

return CodeWindowLogic
