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
	reward: BigNumber,
	timeLeft: number,
	cleared: boolean,
	-- 진행 벽을 열어도 되는가. false면 벽을 비활성화하고 수령 발판만 남긴다
	-- (DESIGN.md 8. 월드 > 최종 월드의 마지막 층). 벽 배치 코드는 이 값만 보면 된다.
	canAdvance: boolean,
}

return GameTypes
