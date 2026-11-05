--!strict
-- 근처 확인 공용 함수 (지시서 #23 N1 ~ N3 — DESIGN.md 13장). Touched 처리 전에 HumanoidRootPart가 그 파트 근처인지 본다.
--
-- 왜: 캐릭터 물리는 클라 소유라 순간 이동한 위치가 서버로 넘어온다. 판정은 서버 런 상태로 하므로 위조되는 것은
-- 재화가 아니라 "걷는 시간"이다(#22 R2). Touched는 신호일 뿐 권한이 아니다(CLAUDE.md 절대 규칙 3) — 이 함수는 신호를 거르는 앞 단계다.
--
-- 근처 = 파트 로컬 좌표(CFrame:PointToObjectSpace — 회전된 파트도 맞다)에서 축마다 |d| ≤ 크기/2 + 여유(ProximityConfig).
-- 거부는 사유 코드만 로그한다(no_character · no_root · far — LogFold로 접음). 유저 안내 · 킥 없음.
-- ⚠️ 서버가 직접 부르는 경로(자동 진행 advance · cashout, 워프 순간 이동)는 이 함수를 거치지 않는다(N2).
-- ⚠️ yield하지 않는다 — Touched 핸들러의 디바운스 앞에서 부른다(같은 프레임 두 접촉의 순서를 바꾸지 않는다).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProximityConfig = require(ReplicatedStorage.Shared.Config.ProximityConfig)
local LogFold = require(script.Parent.LogFold)

local Proximity = {}

Proximity.REASON_NO_CHARACTER = "no_character"
Proximity.REASON_NO_ROOT = "no_root"
Proximity.REASON_FAR = "far"

-- 순수 판정. rootPosition이 nil이면 no_root.
function Proximity.isNear(rootPosition: Vector3?, partCFrame: CFrame, partSize: Vector3, margin: number): (boolean, string?)
	if rootPosition == nil then
		return false, Proximity.REASON_NO_ROOT
	end
	local d = partCFrame:PointToObjectSpace(rootPosition)
	if math.abs(d.X) <= partSize.X / 2 + margin and math.abs(d.Y) <= partSize.Y / 2 + margin and math.abs(d.Z) <= partSize.Z / 2 + margin then
		return true, nil
	end
	return false, Proximity.REASON_FAR
end

-- 플레이어 → 루트 위치. 캐릭터 · 루트가 없으면 (nil, 사유)
function Proximity.rootPosition(player: any): (Vector3?, string?)
	local character = player.Character
	if character == nil then
		return nil, Proximity.REASON_NO_CHARACTER
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, Proximity.REASON_NO_ROOT
	end
	return (root :: BasePart).Position, nil
end

local rejects = 0
local folder = LogFold.new(LogFold.WINDOW_SEC, os.clock, function(line: string)
	print(line)
end)

-- 이번 서버에서 거부한 수(Play 확인용 — 읽기만)
function Proximity.rejectCount(): number
	return rejects
end

-- Touched 핸들러용. 근처면 true. 아니면 사유 코드 로그(접음) 뒤 false. site는 로그용 이름(cashout_pad 등).
function Proximity.check(player: any, part: BasePart, site: string, margin: number?): boolean
	local position, why = Proximity.rootPosition(player)
	local ok, reason = false, why
	if position ~= nil then
		ok, reason = Proximity.isNear(position, part.CFrame, part.Size, margin or ProximityConfig.PROXIMITY_MARGIN)
	end
	if ok then
		return true
	end
	rejects += 1
	local distance = if position ~= nil then string.format("%.1f", (position - part.Position).Magnitude) else "-"
	folder.log(string.format("%s:%s:%s", tostring(player.UserId), site, tostring(reason)),
		string.format("[Proximity] 거부 site=%s part=%s reason=%s user=%s dist=%s", site, part.Name, tostring(reason), tostring(player.UserId), distance))
	return false
end

return Proximity
