--!strict
-- 서버와 클라가 함께 보는 도메인 타입의 유일한 정의처.
--
-- 왜 Remotes.lua가 아니라 별도 모듈인가:
--   BlockChange는 BlockService가, RunStateView는 ChallengeService가 만드는 값이다.
--   두 서비스는 네트워크를 몰라도 되는 도메인 계층인데, 타입을 Remotes.lua에 두면
--   "블록 HP를 계산하는 모듈"이 "RemoteEvent를 만드는 모듈"을 require하게 된다.
--   방향이 거꾸로다. 타입만 있는 모듈을 하나 두면 서비스도 Remotes도 이쪽만 보면 된다.
--   (Remotes.lua는 이 타입들을 payload 별칭으로 다시 export한다 — 발신·수신부가
--    채널 이름과 payload 형태를 한 파일에서 같이 읽게 하려는 것)
--
-- 정의는 여기 하나뿐이다. 같은 형태를 다른 파일에 다시 적지 말 것.
-- 이 프로젝트는 문서에서 같은 수치를 두 곳에 적었다가 두 번 어긋난 전례가 있다.
--
-- 이 타입들은 RemoteEvent를 건넌다. 그래서 지켜야 하는 제약:
--   - 선택 필드(`foo: number?`)를 만들지 말 것. nil이면 키가 통째로 사라져서
--     수신부가 다른 형태를 받는다
--   - BigNumber는 { m, e } 평범한 테이블이고 메타테이블이 없다. 직렬화 후에도
--     BigNum 함수에 그대로 넘어간다 (자세한 근거는 Remotes.lua 상단)

local BigNum = require(script.Parent.BigNum)

type BigNumber = BigNum.BigNumber

local GameTypes = {}

-- 블록 한 개의 HP 변화. 서버는 HP만 보낸다 — 큐브 개수는 클라가 HP 비율로 역산한다
-- (CLAUDE.md "4. 파편·파티클은 클라이언트 전용").
export type BlockChange = {
	index: number,
	hp: BigNumber,
	destroyed: boolean,
}

-- 런 상태의 클라 노출본. 서버 내부 RunState(startedAt 등)와는 다르다 —
-- 클라에 줄 필요가 없는 필드는 여기 없다.
export type RunStateView = {
	stage: number,
	reward: BigNumber, -- 지금 수령하면 받는 양(블럭스 획득량 업그레이드 반영 — ChallengeService.payableReward)
	-- 다음 층을 깨면 받는 양(같은 식). 다음 층이 없으면 0. 서버는 항상 채운다 — 선택 표시는 테스트 · 자리 채움용
	-- 상태를 만들 때만 생략할 수 있게 둔 것이다(없으면 클라가 StageConfig 층 보상, 즉 배수 1로 본다)
	nextReward: BigNumber?,
	timeLeft: number,
	cleared: boolean,
	-- 진행 벽을 열어도 되는가. false면 벽을 비활성화하고 수령 발판만 남긴다
	-- (DESIGN.md 8. 월드 > 최종 월드의 마지막 층). 벽 배치 코드는 이 값만 보면 된다.
	canAdvance: boolean,
}

-- 플레이어 상태의 클라 노출본 (PlayerState 채널, Phase 6 지시서 #5).
-- 서버가 프로필과 서비스 상태에서 만든다 — 클라는 이 값을 Store에 넣고 화면은 Store만 본다.
-- 레벨 · 다음 레벨 진행률은 싣지 않는다: strength 하나에서 LevelConfig(서버 SpeedService와 같은
-- 함수)로 파생되는 값이라, 따로 실으면 strength와 다른 시점에 갱신될 위험이 생긴다
-- (client/UI/Store.lua "level 필드는 없다" 참고).
export type PlayerStateView = {
	blox: BigNumber,
	strength: BigNumber,
	lifetimeBlox: BigNumber, -- 평생 누적
	lifeBlox: BigNumber, -- 이번 생애 누적 (패드 해금 기준)
	rebirths: BigNumber,
	walkSpeed: number, -- 서버 Humanoid.WalkSpeed (캐릭터가 없으면 0)
	maxWalkSpeed: number, -- SpeedService.getMaxSpeed
	maxStage: number,
	padIndex: number, -- 지금 세팅된 클릭 파워 패드
	-- 업그레이드 레벨. 키 = UpgradeConfig.Upgrades의 이름 8개 전부(비노출 포함), 값 = 0 이상 정수 (지시서 #7)
	upgrades: { [string]: number },
	-- 칭호 요약 (지시서 #10). owned = 보유 id(희귀도 낮은 순), equipped = 장착 id(없으면 ""), autoRoll = 자동 롤 켬
	titles: TitleSummary,
	-- 아우라 요약 (지시서 #11). owned = 보유 id(팩 · 등급 순), equipped = 장착 id(없으면 ""), selectedPack · hideOtherAuras
	auras: AuraSummary,
	-- 펫 요약 (지시서 #12). owned = 보유 전부(uid 번호 순), equipped = 장착 uid(장착 순서), slots · storage = 파생값
	pets: PetSummary,
	-- 상점 요약 (Phase 8 지시서 #16). 세션 값이다 — 프로필에 없다(절대 규칙 5)
	shop: ShopSummary,
}

-- gamepasses = 보유 게임패스 키(이름순 — GamepassService 세션 값 · 가짜 소유 포함)
-- paidRandomRestricted = 로벅스 행운 상품을 숨기고 효과를 끄는가(S13 — PolicyGate. 판정 실패 · 확인 전도 true)
-- boosts = 활성 부스트(BoostService — ShopConfig.BOOST_ORDER 순서, 남은 초 올림). 제한 유저의 행운 포션은 뺀다. 없으면 빈 목록
--   ⚠️ 남은 초는 매초 바뀌지만 매초 보내지 않는다 — 서버는 BOOST_RESYNC_SEC 넘게 어긋날 때만 다시 보내고 클라가 받은 뒤로 센다
-- autoClick = 자동 클리커가 켜져 있는가(세션 값 — 접속하면 false)
export type ShopSummary = {
	gamepasses: { string },
	paidRandomRestricted: boolean,
	boosts: { BoostView },
	autoClick: boolean,
}

export type BoostView = {
	type: string,
	mult: number,
	remainingSec: number,
}

-- 보유 펫 한 마리. level = 강화 단계 1~4(프로필에는 tier라는 이름으로 저장된다 — DESIGN 10장). 종 희귀도는 petId로 Config에서 읽는다.
export type PetEntryView = {
	uid: string,
	petId: string,
	level: number,
}

export type PetSummary = {
	owned: { PetEntryView },
	equipped: { string },
	slots: number, -- PetConfig.getSlots(petSlots 레벨, 슬롯 게임패스)
	storage: number, -- PetConfig.getStorage(저장 공간 게임패스)
	hideOtherPets: boolean,
	world: number,
}

export type AuraSummary = {
	owned: { string },
	equipped: string,
	selectedPack: number,
	hideOtherAuras: boolean,
	world: number, -- progress.currentWorld (그 월드의 팩만 창에 보인다)
}

export type TitleSummary = {
	owned: { string },
	equipped: string,
	autoRoll: boolean,
}

return GameTypes
