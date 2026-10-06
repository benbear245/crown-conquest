class_name BotAbilities
extends RefCounted

# When bots press their ability buttons. Runs on its own slower timer.
# Normal: Swift March + Crown Shield. Hard: all four, and combines Bombard +
# Rally on enemy Crowns. Easy: none.


static func think(sim: Simulation, p: Player) -> void:
	var state: GameState = sim.state
	var now: float = state.match_time
	# Crown Shield: an enemy front is in our Crown zone right now.
	if p.crown_alert_until > now and not AbilitiesOps.is_crown_shield_active(p, now) \
			and p.crown_shield_cd_until <= now and not state.is_final_siege():
		sim.player_activate_crown_shield(p.id)
	# Swift March: while grabbing land in the opening rush, or racing for Ruins.
	var scan: BotScan = p.bot_scan as BotScan
	var racing_ruins: bool = scan != null and not scan.ruins_tiles.is_empty()
	if p.expansion_troops > 0.0 and (now < 180.0 or racing_ruins) and p.swift_march_cd_until <= now:
		sim.player_activate_swift_march(p.id)
	if p.difficulty < Balance.BOT_DIFFICULTY_HARD or scan == null:
		return
	# Bombard + Rally on a neighbour's Crown, then push.
	if now >= Balance.BOMBARD_UNLOCK_SEC and p.bombard_cd_until <= now:
		for id: int in scan.enemy_tile.keys():
			var e: Player = state.get_player(id)
			if e == null or not e.is_alive or e.crown_x < 0 or TrucesOps.has_truce(p, id, now):
				continue
			if not AbilitiesOps.bombard_in_range(sim, p, e.crown_x, e.crown_y):
				continue
			if not sim.player_activate_bombard(p.id, e.crown_x, e.crown_y):
				continue
			if now >= Balance.RALLY_UNLOCK_SEC and p.rally_cd_until <= now:
				sim.player_activate_rally(p.id)
			var pushing: bool = false
			for a: Attack in scan.my_attacks:
				pushing = pushing or a.defender_id == id
			if not pushing:
				var tile: Vector2i = state.idx_to_xy(int(scan.enemy_tile[id]))
				sim.player_attack(p.id, tile.x, tile.y, Bots.send_range(p.difficulty).y)
			return
	# Rally to finish a big push.
	if now >= Balance.RALLY_UNLOCK_SEC and p.rally_cd_until <= now and not AbilitiesOps.is_rally_active(p, now):
		for a: Attack in scan.my_attacks:
			if a.troops_remaining >= maxf(150.0, 0.15 * p.troops):
				sim.player_activate_rally(p.id)
				return
