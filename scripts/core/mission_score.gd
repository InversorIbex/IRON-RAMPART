class_name MissionScore
extends RefCounted
## Mission score (documented in docs/GAME_DESIGN.md, "Puntuación"):
##
##   score = 500 x waves completed
##         + 10  x enemies destroyed
##         + 150 x HQ points remaining
##         + 1   x credits remaining
##         + 1000 if the mission is won
##
## Rating (stars, for the future campaign map): 3 = won with the HQ untouched,
## 2 = won with >= 50 % HQ, 1 = won, 0 = lost.

const PER_WAVE := 500
const PER_KILL := 10
const PER_HQ_POINT := 150
const PER_CREDIT := 1
const VICTORY_BONUS := 1000


static func compute(s: GameSession) -> int:
	return PER_WAVE * s.stats.waves_completed \
			+ PER_KILL * s.stats.kills \
			+ PER_HQ_POINT * s.base_hp \
			+ PER_CREDIT * s.wallet.get_credits() \
			+ (VICTORY_BONUS if s.phase == GameSession.Phase.VICTORY else 0)


static func stars(s: GameSession) -> int:
	if s.phase != GameSession.Phase.VICTORY:
		return 0
	if s.base_hp == s.level.base_max_hp:
		return 3
	return 2 if s.base_hp * 2 >= s.level.base_max_hp else 1
