class_name EnemyType
extends Resource

# A data asset describing one kind of enemy. Author these as .tres files
# (right-click in the FileSystem dock -> New Resource -> EnemyType) and drop one
# onto an Enemy instance's "type" slot. One enemy.tscn, many types — no code per type.

@export var type_name: String = "Enemy"

@export_group("Combat")
@export var kill_threshold: float = 45.0   # player speed at/above which this enemy dies instantly
@export var max_health: float = 50.0       # HP; a sub-threshold hit chips off the player's current speed
@export var hit_distance: float = 4.0      # contact distance to the player (tune to mesh sizes)
@export var hit_cooldown: float = 0.4      # min seconds between contacts
@export var score: int = 100               # points awarded on death

@export_group("Movement")
@export var move_speed: float = 18.0       # surface speed (units/sec); keep below the Top's
@export var turn_speed: float = 4.0        # radians/sec the heading can swing toward the target
@export var chase_range: float = 60.0      # surface distance at which it starts chasing

@export_group("Appearance")
@export var texture: Texture2D             # the billboard sprite; null keeps the scene's default
@export var modulate: Color = Color.WHITE  # rgb tint over the texture (alpha ignored — use opacity)
@export_range(0.0, 1.0) var opacity: float = 1.0  # 1 = solid, 0 = fully transparent
# --- size: final world height = texture_pixels * pixel_size * sprite_scale ---
@export var pixel_size: float = 0.05       # world size per texture pixel
@export var sprite_scale: float = 1.0      # extra uniform multiplier on top of pixel_size
# --- placement: how far the sprite is lifted off the surface along the normal (world units).
#     0 = centered on the surface point; raise it to sit the art on top of the planet ---
@export var surface_offset: float = 0.0
