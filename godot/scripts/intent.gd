class_name Intent
extends RefCounted

## То, что тело просят сделать в этот кадр, независимо от того, кто просит —
## клавиатура или мозг бота. Ровно из-за этого движение, удар и взаимодействие
## написаны один раз, а не дважды.

var move := Vector2.ZERO      ## x — вбок, y — вперёд, оба в [-1, 1]
var sprint := false
var crouch := false

var interact_pressed := false
var interact_held := false

var primary := false          ## ЛКМ: нож / лоза / удар
var secondary := false        ## ПКМ: серп / плющ / захват
var power1 := false           ## Q: крюк / поросль / таран
var power2 := false           ## F: двойники
var drop := false             ## G: бросить ношу
var struggle := false         ## Пробел: вырываться


## Нажатия живут один кадр. Мозг, забывший их сбросить, держит кнопку вечно.
func clear_presses() -> void:
	interact_pressed = false
	primary = false
	secondary = false
	power1 = false
	power2 = false
	drop = false
	struggle = false
