--!strict
-- 저사양 폰 모드 값(지시서 #48 3부). 켜면 연출의 양만 줄인다 — 게임 판정 · 연출 속도 · 서버 값은 그대로다.
-- 값은 클라 세션 메모리(Client/UI/LowEndPrefs)에만 있다 — 새 서버 저장 필드를 만들지 않는다(지시서). 그래서 접속할 때마다
-- 기기 그래픽 품질로 다시 정한다(DEFAULT_FROM_QUALITY). 켜고 끄기는 설정 창 줄 하나.
--
-- 공식 문서(2026-11-28 확인): UserSettings().GameSettings.SavedQualityLevel — Enum.SavedQualitySetting
--   Automatic = 0 · QualityLevel1 ~ QualityLevel10 = 1 ~ 10. "Automatic"이면 실제 단계를 알 수 없다 → 꺼짐.
--   읽기가 막히면(pcall 실패) 꺼짐.

local LowEndConfig = {}

-- 기기 품질 단계가 1 ~ 이 값이면 첫 접속 기본 켜짐(사용자가 품질을 낮게 고정한 기기). Automatic(0) · 읽기 실패는 꺼짐
LowEndConfig.QUALITY_ON_MAX = 3

-- 켜면 줄이는 것(끄면 괄호 안 원래 값 — 원본은 각 모듈)
LowEndConfig.FRAGMENT_CAP = 100 -- 동시 파편(ParticlePool 200 — 절대 규칙 4 상한의 절반)
LowEndConfig.FRAGMENT_FULL_BATCH = 3 -- 이 개수 이하로 부서지면 전부 파편(ChunkBreaker 6)
LowEndConfig.FRAGMENT_TARGET = 6 -- 큰 배치에서 배치당 파편 수(ChunkBreaker 12)
LowEndConfig.COIN_BURST = 3 -- 한 번에 날아가는 코인(CoinFx 6)
LowEndConfig.DROP_VISIBLE_MAX = 20 -- 동시에 그리는 바닥 드롭(서버 상한 OreDropService MAX_FLOOR_DROPS의 절반 — 줍기 판정은 서버라 그대로)
LowEndConfig.DROP_SPARKLE = false -- 드롭 반짝이 파티클(DropRenderer — effectId)
LowEndConfig.SHINE = false -- 버튼 빛 띠(Shine — 연출 줄이기와 같은 멈춤)
LowEndConfig.REBIRTH_FLASH = false -- 환생 화면 번쩍임(화면 흔들림은 이 게임에 없다 — 화면 전체 연출은 이것 하나)

-- 기기 품질 → 첫 접속 기본값. level은 Enum.SavedQualitySetting.Value(0 ~ 10) 또는 nil(못 읽음)
function LowEndConfig.defaultFromQuality(level: number?): boolean
	if type(level) ~= "number" or level ~= level then
		return false
	end
	return level >= 1 and level <= LowEndConfig.QUALITY_ON_MAX
end

-- 켜짐이면 낮은 값, 아니면 원래 값
function LowEndConfig.pick(on: boolean, normal: number, low: number): number
	return if on then math.min(normal, low) else normal
end

return LowEndConfig
