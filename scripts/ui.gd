extends CanvasLayer
## The watcher's HUD: clock, speed, colony stores, chronicle and inspector.

const D = preload("res://scripts/data.gd")

signal speed_changed(s)
signal follow_toggled
signal event_clicked(who)

var w
var clock: Label
var stores: Label
var chron: RichTextLabel
var insp_panel: PanelContainer
var insp: RichTextLabel
var colony: RichTextLabel
var speed_btns = []
var selected = null
var last_events = -1
var follow_btn: Button

const KIND_COL := {"spell": "#c9b8ff", "good": "#7fdca8", "bad": "#ff8f96", "rise": "#f2b06a", "info": "#a9adbf"}

func _panel_style(alpha := 0.88) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.06, 0.09, alpha)
	s.border_color = Color(0.25, 0.23, 0.33)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func build(world) -> void:
	w = world
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# top bar
	var top = PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style(0.92))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 8
	root.add_child(top)
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	top.add_child(hb)
	var title = Label.new()
	title.text = "SHADOW SLAVE COLONY"
	title.add_theme_color_override("font_color", Color("#c9b8ff"))
	title.add_theme_font_size_override("font_size", 17)
	hb.add_child(title)
	clock = Label.new()
	clock.add_theme_font_size_override("font_size", 15)
	clock.custom_minimum_size.x = 300
	hb.add_child(clock)
	for s in [[0, "Pause"], [1, "1x"], [2, "2x"], [4, "4x"], [8, "8x"], [20, "20x"]]:
		var b = Button.new()
		b.text = s[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var sv: int = s[0]
		b.pressed.connect(func(): speed_changed.emit(sv))
		hb.add_child(b)
		speed_btns.append([sv, b])
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	stores = Label.new()
	stores.add_theme_font_size_override("font_size", 14)
	hb.add_child(stores)
	# right column
	var right = VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -400
	right.offset_right = -8
	right.offset_top = 60
	right.offset_bottom = -8
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	var cp = PanelContainer.new()
	cp.add_theme_stylebox_override("panel", _panel_style())
	right.add_child(cp)
	colony = RichTextLabel.new()
	colony.bbcode_enabled = true
	colony.fit_content = true
	colony.scroll_active = false
	colony.add_theme_font_size_override("normal_font_size", 13)
	cp.add_child(colony)
	var chp = PanelContainer.new()
	chp.add_theme_stylebox_override("panel", _panel_style())
	chp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(chp)
	chron = RichTextLabel.new()
	chron.bbcode_enabled = true
	chron.scroll_following = false
	chron.add_theme_font_size_override("normal_font_size", 13)
	chron.meta_clicked.connect(_on_meta)
	chp.add_child(chron)
	# inspector
	insp_panel = PanelContainer.new()
	insp_panel.add_theme_stylebox_override("panel", _panel_style())
	insp_panel.anchor_top = 1.0
	insp_panel.anchor_bottom = 1.0
	insp_panel.offset_left = 8
	insp_panel.offset_top = -330
	insp_panel.offset_right = 380
	insp_panel.offset_bottom = -8
	insp_panel.visible = false
	root.add_child(insp_panel)
	var iv = VBoxContainer.new()
	insp_panel.add_child(iv)
	insp = RichTextLabel.new()
	insp.bbcode_enabled = true
	insp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	insp.add_theme_font_size_override("normal_font_size", 13)
	iv.add_child(insp)
	follow_btn = Button.new()
	follow_btn.text = "Follow"
	follow_btn.toggle_mode = true
	follow_btn.focus_mode = Control.FOCUS_NONE
	follow_btn.pressed.connect(func(): follow_toggled.emit())
	iv.add_child(follow_btn)
	# help line
	var help = Label.new()
	help.text = "Drag to pan · scroll to zoom · click someone to inspect · Space pauses · 1-6 set speed · F follows"
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	help.add_theme_font_size_override("font_size", 12)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 400
	help.offset_top = -26
	help.offset_right = 1100
	root.add_child(help)

func set_speed(s: int) -> void:
	for b in speed_btns:
		b[1].button_pressed = b[0] == s

func _on_meta(meta) -> void:
	var id = int(str(meta))
	for p in w.pawns:
		if p.id == id:
			event_clicked.emit(p)
			return

func refresh() -> void:
	var h: float = w.hour()
	var hh = int(h)
	var mm = int((h - hh) * 60)
	var phase = "Night" if w.is_night() else ("Dawn" if h < 8 else ("Day" if h < 18 else "Dusk"))
	clock.text = "Year %d · Day %d · %02d:%02d %s" % [w.year() + 1, (w.day() % D.DAYS_PER_YEAR) + 1, hh, mm, phase]
	if w.raid_active:
		clock.text += "  ·  RAID"
	stores.text = "Wood %d   Stone %d   Ashroot %d   Meals %d   Soul shards %d" % [w.store.wood, w.store.stone, w.store.raw, w.store.meal, w.store.shards]
	var alive = 0
	var ranks = [0, 0, 0]
	for p in w.pawns:
		if p.alive:
			alive += 1
			ranks[p.rank] += 1
	var gstate: String
	if w.gate_open:
		gstate = "[color=#c9b8ff]Gateway open[/color]"
	elif w.assault:
		gstate = "[color=#ff8f96]Assault on the keep![/color]"
	else:
		gstate = "Sealed. %s: %d/%d" % [w.guardian.name, int(w.guardian.hp), int(w.guardian.max_hp)]
	colony.text = "[b][color=#c9b8ff]Camp beneath %s[/color][/b]\nPeople %d   ([color=#cfcfcf]%d Sleepers[/color], [color=#f2b06a]%d Awakened[/color], [color=#ffd27a]%d Masters[/color])\nGateway: %s\nRaids survived %d · Creatures slain %d · Graves %d" % [w.citadel_name, alive, ranks[0], ranks[1], ranks[2], gstate, w.raids_survived, w.kills, w.graves.size()]
	if w.events.size() != last_events:
		last_events = w.events.size()
		var s = "[b][color=#c9b8ff]Chronicle[/color][/b]\n"
		var n = 0
		for i in range(w.events.size() - 1, -1, -1):
			var e = w.events[i]
			var col: String = KIND_COL.get(e.kind, "#cccccc")
			var txt: String = e.text
			if e.who != null and e.who.has_method("remember"):
				txt = txt.replace(e.who.name, "[url=%d]%s[/url]" % [e.who.id, e.who.name])
			s += "[color=#6d7088]D%d %02d:00[/color]  [color=%s]%s[/color]\n" % [e.day + 1, int(e.hour), col, txt]
			n += 1
			if n > 80:
				break
		chron.text = s
	_inspect()

func show_inspect(o) -> void:
	selected = o
	insp_panel.visible = o != null
	_inspect()

func _bar(v: float) -> String:
	var n = int(round(clamp(v, 0, 100) / 10.0))
	var col = "#7fdca8" if v > 50 else ("#f2b06a" if v > 25 else "#ff8f96")
	return "[color=%s]%s[/color][color=#3a3c4a]%s[/color] %d" % [col, "■".repeat(n), "■".repeat(10 - n), int(v)]

func _inspect() -> void:
	if selected == null:
		return
	var o = selected
	if o.has_method("remember"):
		var p = o
		var s = "[b][font_size=17]%s[/font_size][/b]%s\n" % [p.name, "" if p.alive else "  [color=#ff8f96](dead)[/color]"]
		s += "[color=#c9b8ff]%s · %s Aspect[/color] · %s\n" % [D.RANKS[p.rank], p.nature, p.trait_name]
		var pk: String = D.PERK_TEXT[p.perk()]
		if pk != "":
			s += "[color=#8a8fa8]%s[/color]\n" % pk
		s += "Doing: %s\n" % ("Gone through the Gateway" if p.away_until > 0 else p.activity)
		s += "Health   %s\n" % _bar(p.hp / p.max_hp() * 100.0)
		s += "Hunger   %s\n" % _bar(p.hunger)
		s += "Rest     %s\n" % _bar(p.rest)
		s += "Mood     %s\n" % _bar(p.mood)
		s += "Soul core %d%%   Kills %d   Power %d\n" % [int(p.core * 100), p.kills, int(p.power() / 10)]
		var sk = []
		for k in D.SKILLS:
			sk.append("%s %.1f" % [D.SKILL_NAMES[k], p.skills[k]])
		s += "[color=#8a8fa8]%s[/color]\n" % ", ".join(sk)
		if p.thoughts.size() > 0:
			s += "[b]Thoughts[/b]\n"
			for t in p.thoughts:
				s += "[color=%s]%+d %s[/color]\n" % ["#7fdca8" if t[1] > 0 else "#ff8f96", t[1], t[0]]
		if p.history.size() > 0:
			s += "[b]Story[/b]\n"
			for hline in p.history.slice(-4):
				s += "[color=#a9adbf]%s[/color]\n" % hline
		insp.text = s
	else:
		var c = o
		insp.text = "[b][font_size=17]%s[/font_size][/b]\n[color=#ff8f96]%s[/color]%s\nHealth %d / %d\nStrike %d" % [c.name, c.rank_name, ("" if c.alive else "  (dead)"), int(max(c.hp, 0)), int(c.max_hp), int(c.dmg)] + ("\nThe Guardian of the keep. While it lives the Gateway stays sealed." if c.guardian else ("\nPart of a raid." if c.raider else "\nWanders the ash. Hunted for meat and soul shards."))
