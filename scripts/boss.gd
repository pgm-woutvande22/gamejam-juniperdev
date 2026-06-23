extends "res://scripts/enemy.gd"

# King Crab boss. Reuses the surface-glued movement + contact system from enemy.gd
# (great-circle chase, ram-to-chip-health, damage-number popups) and layers on boss
# behavior: a slow, bulky chase, an enrage state below a health threshold, and a
# boss_defeated signal the level/spawner can react to.
#
# Defeat model: the King Crab EnemyType sets kill_threshold absurdly high so the player
# can never one-shot it. Every ram chips max_health by the player's surface speed (see
# enemy._resolve_contact); enough hits bring it down.

signal boss_defeated(boss: Node, score: int)

@export_group("Enrage")
@export var enrage_enabled: bool = true
@export_range(0.0, 1.0) var enrage_threshold: float = 0.3   # health fraction that triggers enrage
@export var enrage_speed_mult: float = 1.4     # move/turn speed multiplier once enraged (kept modest: still bulky)
@export var enrage_color: Color = Color(1.0, 0.55, 0.55)    # permanent tint once enraged

var enraged: bool = false

func _ready() -> void:
	super._ready()                              # applies type + difficulty scaling, snaps to surface, joins "enemies"
	add_to_group("boss")

func _physics_process(delta: float) -> void:
	# full enemy behavior: contact, chase, anti-clump, move, orient, face player
	super._physics_process(delta)
	if not is_instance_valid(self):
		return
	_update_enrage()

func _update_enrage() -> void:
	if not enrage_enabled or enraged:
		return
	if max_health > 0.0 and health / max_health <= enrage_threshold:
		enraged = true
		move_speed *= enrage_speed_mult
		turn_speed *= enrage_speed_mult
		if sprite != null:
			sprite.modulate = enrage_color

func _die() -> void:
	boss_defeated.emit(self, score)
	super._die()                                # emits died(self, score) and queue_free
