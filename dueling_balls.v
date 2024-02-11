// Copyright (c) 2024 Delyan Angelov. All rights reserved.
// Use of this source code is governed by an MIT license that can be found in the LICENSE file.
import gg
import gx
import time
import rand
import math.vec
import miniaudio as ma
import os

const wtitle = 'Dueling Balls (miniaudio)'
const wwidth = 640
const wheight = 480
const wcolor = gx.rgba(110, 110, 110, 255)
const neutral_field_color = gx.rgba(120, 120, 120, 255)
const fwidth = 20
const fheight = 20
const update_delay_ms = 8

const color_palette = [gx.rgba(250, 0, 0, 55), gx.rgba(0, 0, 255, 55),
	gx.rgba(0, 255, 0, 55), gx.rgba(255, 0, 0, 55), gx.rgba(155, 228, 255, 125)]

const ball_1 = &Ball{
	tag: 0
	center: vec.vec2[f32](50, 50)
	velocity: vec.vec2[f32](4, 1.2)
	color: gx.rgba(255, 255, 255, 255)
	hitcolor: gx.rgba(55, 55, 55, 255)
	radius: 18
}
const ball_2 = &Ball{
	tag: 1
	center: vec.vec2[f32](520, 200)
	velocity: vec.vec2[f32](3, 2.5)
	color: gx.rgba(55, 55, 255, 255)
	hitcolor: gx.rgba(220, 220, 220, 255)
	radius: 18
}

@[heap]
struct App {
mut:
	gg              &gg.Context = unsafe { nil }
	balls           []&Ball
	field           Field
	update_delay_ms int = update_delay_ms
	wwidth          int = wwidth
	wheight         int = wheight
	sound_player    &Player
}

struct Ball {
mut:
	tag      int
	center   vec.Vec2[f32]
	velocity vec.Vec2[f32]
	radius   f32
	color    gx.Color
	hitcolor gx.Color
	score    int
}

struct Field {
mut:
	values []gx.Color
	w      int
	h      int
	cw     f32
	ch     f32
}

fn Field.new(w int, h int, app_w int, app_h int, color gx.Color) Field {
	mut res := Field{
		w: w
		h: h
		values: []gx.Color{len: w * h, init: color}
	}
	res.resize(app_w, app_h)
	return res
}

fn (mut f Field) resize(app_w int, app_h int) {
	f.cw = f32(app_w) / f.w
	f.ch = f32(app_h) / f.h
}

fn (mut f Field) reset() {
	for mut c in f.values {
		c = rand.element(color_palette) or { continue }
	}
}

@[inline]
fn (mut f Field) at(x f32, y f32, radius f32) &gx.Color {
	mut xx := clamp(int(x / f.cw), 0, f.w)
	mut yy := clamp(int(y / f.ch), 0, f.h)
	idx := clamp(f.w * yy + xx, 0, f.values.len - 1)
	// eprintln('>> x: ${x:7.2} | y: ${y:5.2} | xx: ${xx:5.2} | yy: ${yy:5.2} | idx: ${idx} | f.cw: ${f.cw} | f.ch: ${f.ch}')
	return unsafe { &f.values[idx] }
}

fn (mut app App) draw_field() {
	for idx, color in app.field.values {
		y := idx / app.field.h
		x := idx % app.field.w
		app.gg.draw_rect_filled(x * app.field.cw, y * app.field.ch, app.field.cw, app.field.ch,
			color)
	}
}

fn (mut app App) draw_balls() {
	for ball in app.balls {
		app.gg.draw_circle_filled(ball.center.x, ball.center.y, ball.radius, ball.color)
	}
}

fn (mut app App) label(x int, y int, txt string, size int, color gx.Color) {
	app.gg.draw_rect_filled(x - 8, y - 2, txt.len * 12, 29, gx.rgba(50, 50, 0, 95))
	app.gg.draw_text(x, y, txt, size: size, color: gx.rgba(5, 5, 0, 255))
	app.gg.draw_text(x + 2, y + 2, txt, size: size, color: gx.rgba(255, 255, 255, 255))
	app.gg.draw_text(x + 1, y + 1, txt, size: size, color: color)
}

fn (mut app App) frame() {
	app.gg.begin()
	app.draw_field()
	app.draw_balls()
	app.label(app.wwidth - 134, 2, 'Ball 1: ${app.balls[0].score:04}', 24, app.balls[0].color)
	app.label(app.wwidth - 134, 31, 'Ball 2: ${app.balls[1].score:04}', 24, app.balls[1].color)
	app.label(app.wwidth - 220, app.wheight - 20, 'Keys: m, Up, Down, Escape, Space',
		14, gx.white)
	app.gg.show_fps()
	app.gg.end()
}

fn (mut app App) bounce_ball(mut b Ball) {
	app.sound_player.play(b.tag)
	b.velocity.multiply_scalar(-1.1)
	if b.velocity.magnitude() > 5 {
		b.velocity.x += rand.f32n(6.0) or { 0 } - 2.0
		b.velocity.y += rand.f32n(6.0) or { 0 } - 2.0
		b.velocity = b.velocity.unit()
		b.velocity.multiply_scalar(5.0)
	}
}

fn (mut app App) update() {
	for {
		// check for bounces between the balls:
		mut b1 := unsafe { &app.balls[0] }
		mut b2 := unsafe { &app.balls[1] }
		for b1.center.distance(b2.center) < b1.radius + b2.radius {
			for mut b in app.balls {
				app.bounce_ball(mut *b) // TODO: v bug
				b.center += b.velocity
			}
		}
		// interactions between the balls and the field:
		for mut b in app.balls {
			mut c := app.field.at(b.center.x, b.center.y, b.radius)
			if c == b.hitcolor {
				continue
			}
			unsafe {
				*c = b.hitcolor
			}
			app.bounce_ball(mut *b) // TODO: v bug
		}
		// update the score for each ball
		mut score1 := 0
		mut score2 := 0
		for color in app.field.values {
			if color == b1.hitcolor {
				score1++
				continue
			}
			if color == b2.hitcolor {
				score2++
				continue
			}
		}
		b1.score = score1
		b2.score = score2
		// keep the balls inside the viewport:
		for mut b in app.balls {
			if b.center.x < b.radius || b.center.x > app.wwidth - b.radius {
				for b.velocity.magnitude_x() < 1 {
					b.velocity.x *= 3
				}
				b.velocity.x *= -1
				app.sound_player.play(b.tag)
			}
			if b.center.y < b.radius || b.center.y > app.wheight - b.radius {
				for b.velocity.magnitude_y() < 1 {
					b.velocity.y *= 3
				}
				b.velocity.y *= -1
				app.sound_player.play(b.tag)
			}
		}
		// move the balls:
		for mut b in app.balls {
			b.center += b.velocity
		}
		for mut b in app.balls {
			b.center.x = clamp(b.center.x, 3, app.wwidth - 3)
			b.center.y = clamp(b.center.y, 3, app.wheight - 3)
		}
		if b1.center.x > app.wwidth - 10 && b2.center.x > app.wwidth - 10 {
			app.reset_balls()
		}
		time.sleep(app.update_delay_ms * time.millisecond)
	}
}

fn (mut app App) on_event(e &gg.Event, data voidptr) {
	match e.typ {
		.resized, .restored, .resumed {
			app.resize()
		}
		else {}
	}
}

fn (mut app App) resize() {
	window_size := app.gg.window_size()
	app.wwidth = window_size.width
	app.wheight = window_size.height
	app.field.resize(window_size.width, window_size.height)
}

fn (mut app App) reset_balls() {
	for mut b in app.balls {
		b.center.x = rand.intn(app.wwidth) or { 0 }
		b.center.y = rand.intn(app.wheight) or { 0 }
		b.velocity.x = rand.f32n(100) or { 0 } - 5
		b.velocity.y = rand.f32n(100) or { 0 } - 5
		b.velocity.unit()
	}
}

fn (mut app App) keydown(code gg.KeyCode, mod gg.Modifier, data voidptr) {
	match code {
		.escape {
			exit(0)
		}
		.enter {
			dump(app.balls)
			dump(app.update_delay_ms)
		}
		.up {
			app.update_delay_ms = clamp(app.update_delay_ms + 1, 0, 1000)
		}
		.down {
			app.update_delay_ms = clamp(app.update_delay_ms - 1, 0, 1000)
		}
		.space {
			app.field.reset()
			app.reset_balls()
		}
		.m {
			app.sound_player.muted = !app.sound_player.muted
		}
		else {}
	}
}

@[inline]
fn clamp[T](x T, a T, b T) T {
	if x < a {
		return a
	}
	if x > b {
		return b
	}
	return x
}

//
@[heap]
struct Player {
mut:
	engine &ma.Engine
	sounds []&ma.Sound
	muted  bool
}

fn Player.new() &Player {
	engine := &ma.Engine{}
	result := ma.engine_init(ma.null, engine)
	if result != .success {
		panic('Failed to initialize audio engine.')
	}
	mut p := &Player{
		engine: engine
	}
	for sname in ['ball1', 'ball2', 'BeepBox-Song'] {
		sound_path := os.resource_abs_path('${sname}.mp3')
		sound := &ma.Sound{}
		res := ma.sound_init_from_file(engine, sound_path.str, 0, ma.null, ma.null, sound)
		if res != .success {
			panic('Failed to load sound ${sound_path}, res: ${res}')
		}
		ma.sound_set_volume(sound, 0.20)
		p.sounds << sound
	}
	bmusic := unsafe { p.sounds[2] }
	ma.sound_set_volume(bmusic, 0.50)
	ma.sound_set_looping(bmusic, 1)
	ma.sound_start(bmusic)
	return p
}

fn (mut p Player) stop() {
	p.muted = true
	for _, mut s in p.sounds {
		ma.sound_stop(s)
	}
	ma.engine_stop(p.engine)
}

fn (mut p Player) play(tag int) {
	if !p.muted {
		if tag >= 0 && tag < p.sounds.len {
			ma.sound_start(unsafe { p.sounds[tag] })
		} else {
			eprintln('> unknown sound tag: ${tag}, p.sounds.len: ${p.sounds.len}')
		}
	}
}

fn main() {
	mut app := &App{
		balls: [ball_1, ball_2]
		field: Field.new(fwidth, fheight, wwidth, wheight, neutral_field_color)
		sound_player: Player.new()
	}
	app.field.reset()
	app.reset_balls()
	app.gg = gg.new_context(
		window_title: wtitle
		bg_color: wcolor
		width: wwidth
		height: wheight
		sample_count: 2
		frame_fn: app.frame
		keydown_fn: app.keydown
		event_fn: app.on_event
		user_data: app
	)
	spawn app.update()
	app.gg.run()
	app.sound_player.stop()
}
