--!strict
-- 효과음 12개 (지시서 #25 S1 — docs/UI.md "효과음"). 소리 ID는 사람이 Creator Store에서 고른다(docs/TUNING.md "소리 넣는 법").
--
--   id       오디오 에셋 번호(숫자). nil이면 재생하지 않는다 — 오류 · 경고 없이 건너뛴다(시작 때 "비어 있는 소리 N개" 한 줄)
--   volume   Sound.Volume(0 ~ 1 안에서 고른다. 엔진 범위는 0 ~ 10)
--
--   button       버튼 누름(ButtonFx가 붙은 HitArea — 비활성 제외)
--   click        클릭 +숫자 팝업이 뜰 때(같은 키 0.05초 스로틀 — UIFxConfig.SFX_MIN_INTERVAL)
--   cashout      수령(런 끝 — RunStateChanged reason cashout)
--   advance      다음 층으로 진행(reason advance)
--   fail         시간 초과 실패(reason timeout — 실패 안내가 뜨는 때)
--   rollCommon   뽑기 결과 일반(표시 단계 tier1 ~ 2)
--   rollRare     레어 · 영웅(tier3 ~ 4)
--   rollLegend   전설 · 신화 · 리미티드(tier5 ~ 6) — 칭호 · 아우라 · 펫 모두 같은 규칙
--   levelUp      레벨 숫자가 오를 때(레벨 튀기와 같은 자리 · 같은 0.5초 간격)
--   rebirth      환생 성공 결과
--   purchase     로벅스 구매 완료 결과
--   dailyClaim   일일 보상 받기 성공 결과

local SoundConfig = {}

export type SoundDef = { id: number?, volume: number }

SoundConfig.KEYS = {
	"button", "click", "cashout", "advance", "fail", "rollCommon", "rollRare", "rollLegend", "levelUp", "rebirth", "purchase", "dailyClaim",
} :: { string }

SoundConfig.Sounds = {
	button = { id = nil, volume = 0.5 },
	click = { id = nil, volume = 0.3 },
	cashout = { id = nil, volume = 0.7 },
	advance = { id = nil, volume = 0.6 },
	fail = { id = nil, volume = 0.6 },
	rollCommon = { id = nil, volume = 0.5 },
	rollRare = { id = nil, volume = 0.6 },
	rollLegend = { id = nil, volume = 0.8 },
	levelUp = { id = nil, volume = 0.5 },
	rebirth = { id = nil, volume = 0.8 },
	purchase = { id = nil, volume = 0.7 },
	dailyClaim = { id = nil, volume = 0.7 },
} :: { [string]: SoundDef }

-- 키마다 미리 둘 Sound 수(처음 재생할 때 한 번 만든다 — 겹쳐 나는 소리는 돌려 쓴다)
SoundConfig.POOL_PER_KEY = 3

function SoundConfig.validate(): boolean
	local n = 0
	for key, def in pairs(SoundConfig.Sounds) do
		n += 1
		assert(table.find(SoundConfig.KEYS, key) ~= nil, "SoundConfig: KEYS에 없는 키 — " .. key)
		assert(def.id == nil or (type(def.id) == "number" and def.id > 0 and def.id % 1 == 0), "SoundConfig: id는 nil 또는 양의 정수 — " .. key)
		assert(type(def.volume) == "number" and def.volume >= 0 and def.volume <= 1, "SoundConfig: volume 0 ~ 1 — " .. key)
	end
	assert(n == #SoundConfig.KEYS and n == 12, "SoundConfig: 키 12개")
	assert(SoundConfig.POOL_PER_KEY >= 1 and SoundConfig.POOL_PER_KEY <= 8, "SoundConfig: 풀 1 ~ 8")
	return true
end

return SoundConfig
