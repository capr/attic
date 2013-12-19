--scene graph for cairo: renders a 2D scene graph on a cairo context.
--some modules are loaded on-demand: look for require() in the code.
local ffi = require'ffi'
local cairo = require'cairo'
local glue = require'glue'
local BaseSG = require'sg_base'

local SG = glue.update({}, BaseSG)

function SG:new(surface, cache)
	local o = BaseSG.new(self, cache)
	self.cr = surface:create_context()
	return o
end

function SG:free()
	self.cr:free()
	BaseSG.free(self)
	if self.freetype then self.freetype:free() end
end

SG.defaults = {
	font = {family = 'Arial', slant = 'normal', weight = 'normal'},
	font_size = 12,
	font_options = {antialias = 'default', subpixel_order = 'default',
							hint_style = 'default', hint_metrics = 'default'},
	fill_rule = 'nonzero',
	line_width = 1,
	line_cap = 'square',
	line_join = 'miter',
	miter_limit = 4,
	line_dashes = {},
	operator = 'over',
	gradient_filter = 'fast',
	gradient_extend = 'pad',
	image_filter = 'best',
	image_extend = 'none',
}

local function cairo_sym(k) return cairo[k] end --raises an exception for invalid k's
local function cairo_enum(prefix) --eg. cairo_enum('CAIRO_OPERATOR_') -> t; t.over -> cairo.CAIRO_OPERATOR_OVER
	return setmetatable({}, {__index = function(t,k)
		local v = glue.unprotect(pcall(cairo_sym, prefix..k:upper()))
		t[k] = v
		return v
	end})
end

local antialias_methods = cairo_enum'CAIRO_ANTIALIAS_'
local subpixel_orders = cairo_enum'CAIRO_SUBPIXEL_ORDER_'
local hint_styles = cairo_enum'CAIRO_HINT_STYLE_'
local hint_metrics = cairo_enum'CAIRO_HINT_METRICS_'

SG:state_value('font_options', function(self, e)
	local fopt = self.cache:get(e)
	if not fopt then
		fopt = cairo.cairo_font_options_create()
		fopt:set_antialias(antialias_methods[e.antialias or self.defaults.font_options.antialias])
		fopt:set_subpixel_order(subpixel_orders[e.subpixel_order or self.defaults.font_options.subpixel_order])
		fopt:set_hint_style(hint_styles[e.hint_style or self.defaults.font_options.hint_style])
		fopt:set_hint_metrics(hint_metrics[e.hint_metrics or self.defaults.font_options.hint_metrics])
		self.cache:set(e, fopt)
	end
	self.cr:set_font_options(fopt)
end)

local font_slants = cairo_enum'CAIRO_FONT_SLANT_'
local font_weights = cairo_enum'CAIRO_FONT_WEIGHT_'

local function font_file_free(ff)
	ff.cairo_face:free()
	ff.ft_face:free()
end

local function bitmask(consts, bits, prefix)
	if not vt then return 0 end
	local v = 0
	for k in pairs(bits) do
		v = bit.bor(v, consts[prefix..k:upper()])
	end
	return v
end

function SG:load_font_file(e) --for preloading
	if not e then return nil end
	local ff = self.cache:get(e)
	if not ff then
		local freetype = require'freetype'
		if not self.freetype then self.freetype = freetype.new() end
		local ft_face = self.freetype:new_face(e.path)
		local load_options = bitmask(freetype, e.load_options, 'FT_LOAD_')
		local cairo_face = cairo.cairo_ft_font_face_create_for_ft_face(ft_face, load_options)
		local ff_object = newproxy(true)
		getmetatable(ff_object).__index = {
			ft_face = ft_face,
			cairo_face = cairo_face,
			free = font_file_free,
		}
		getmetatable(ff_object).__gc = font_file_free
		self.cache:set(e, ff)
	end
	return ff
end

SG:state_value('font_file', function(self, e)
	self.cr:set_font_face(self:load_font_file(e))
end)

SG:state_value('font_size', function(self, size)
	self.cr:set_font_size(size)
end)

SG:state_value('font', function(self, font)
	if font.file then
		self:set_font_file(font.file)
	else
		self.cr:select_font_face(font.family or self.defaults.font.family,
										font_slants[font.slant or self.defaults.font.slant],
										font_weights[font.weight or self.defaults.font.weight])
	end
	self:set_font_options(font.options)
	self:set_font_size(font.size)
end)

SG:state_value('line_dashes', function(self, e)
	local d = self.cache:get(e)
	if not d then
		local a = #e > 0 and ffi.new('double[?]', #e, e) or nil
		d = {a = a, n = #e, offset = e.offset}
		self.cache:set(d)
	end
	self.cr:set_dash(d.a, d.n, d.offset or 0)
end)

SG:state_value('line_width', function(self, width)
	self.cr:set_line_width(width)
end)

--like state_value but use a lookup table; for invalid values, set the default value and record the error.
function SG:state_enum(k, enum, set) --too much abstraction?
	self:state_value(k, function(self, e)
		set(self, self:assert(enum[e], 'invalid %s %s', k, tostring(e)) or enum[self.defaults[k]])
	end)
end

SG:state_enum('line_cap', cairo_enum'CAIRO_LINE_CAP_', function(self, cap)
	self.cr:set_line_cap(cap)
end)

SG:state_enum('line_join', cairo_enum'CAIRO_LINE_JOIN_', function(self, join)
	self.cr:set_line_join(join)
end)

SG:state_value('miter_limit', function(self, limit)
	self.cr:set_miter_limit(limit)
end)

local fill_rules = {
	nonzero = cairo.CAIRO_FILL_RULE_WINDING,
   evenodd = cairo.CAIRO_FILL_RULE_EVEN_ODD,
}

SG:state_enum('fill_rule', fill_rules, function(self, rule)
	self.cr:set_fill_rule(rule)
end)

SG:state_enum('operator', cairo_enum'CAIRO_OPERATOR_', function(self, op)
	self.cr:set_operator(op)
end)

local function new_matrix(...)
	return ffi.new('cairo_matrix_t', ...)
end

local function invertible(mt)
	local mt2 = ffi.new'cairo_matrix_t'
	ffi.copy(mt2, mt, ffi.sizeof(mt))
	return mt2:invert() == 0
end

local function safe_transform(cr, mt)
	if invertible(mt) then cr:transform(mt) end
end

local function transform_matrix(mt, transforms)
	for _,t in ipairs(transforms) do
		local op = t[1]
		if op == 'matrix' then
			local tmt = new_matrix(unpack(t, 2))
			if invertible(tmt) then mt:transform(tmt) end
		elseif op == 'translate' then
			mt:translate(t[2], t[3] or 0)
		elseif op == 'rotate' then
			local cx, cy = t[3], t[4]
			if cx or cy then mt:translate(cx or 0, cy or 0) end
			mt:rotate(math.rad(t[2]))
			if cx or cy then mt:translate(-(cx or 0), -(cy or 0)) end
		elseif op == 'scale' then
			mt:scale(t[2], t[3] or t[2])
		elseif op == 'skew' then
			mt:skew(math.rad(t[2]), math.rad(t[3]))
		end
	end
	return mt
end

function SG:transform(e)
	if e.absolute then self.cr:identity_matrix() end
	if e.matrix then safe_transform(self.cr, new_matrix(unpack(e.matrix))) end
	if e.x or e.y then self.cr:translate(e.x or 0, e.y or 0) end
	if e.cx or e.cy then self.cr:translate(e.cx or 0, e.cy or 0) end
	if e.angle then self.cr:rotate(math.rad(e.angle)) end
	if e.scale then self.cr:scale(e.scale, e.scale) end
	if e.sx or e.sy then self.cr:scale(e.sx or 1, e.sy or 1) end
	if e.cx or e.cy then self.cr:translate(-(e.cx or 0), -(e.cy or 0)) end
	if e.skew_x or e.skew_y then self.cr:skew(math.rad(e.skew_x or 0), math.rad(e.skew_y or 0)) end
	if e.transforms then
		self.cr:set_matrix(transform_matrix(self.cr:get_matrix(), e.transforms))
	end
end

function SG:save()
	self.cr:save()
	return self:state_save()
end

function SG:restore(state)
	self.cr:restore()
	self:state_restore(state)
end

function SG:push_group()
	self.cr:push_group()
	return self:state_save()
end

function SG:pop_group(state)
	self:state_restore(state)
	return self.cr:pop_group()
end

function SG:pop_group_to_source(state)
	self:state_restore(state)
	return self.cr:pop_group_to_source()
end

function SG:draw_round_rect(x1, y1, w, h, r)
	local x2, y2 = x1+w, y1+h
	self.cr:new_sub_path()
	self.cr:arc(x1+r, y1+r, r, -math.pi, -math.pi/2)
	self.cr:arc(x2-r, y1+r, r, -math.pi/2, 0)
	self.cr:arc(x2-r, y2-r, r, 0, math.pi/2)
	self.cr:arc(x1+r, y2-r, r, math.pi/2, math.pi)
	self.cr:close_path()
end

local function rotate(x, y, angle) --from cairosvg/helpers.py, for elliptical_arc
	return
		x * math.cos(angle) - y * math.sin(angle),
		y * math.cos(angle) + x * math.sin(angle)
end

local function point_angle(cx, cy, px, py) --from cairosvg/helpers.py, for elliptical_arc
    return math.atan2(py - cy, px - cx)
end

function SG:draw_elliptical_arc(x1, y1, rx, ry, rotation, large, sweep, x3, y3) --from cairosvg/path.py
	if x1 == x3 and y1 == y3 then return end
	rx, ry, rotation, large, sweep = math.abs(rx), math.abs(ry), math.fmod(rotation, 2*math.pi),
												large ~= 0 and 1 or 0,
												sweep ~= 0 and 1 or 0
	if rx==0 or ry==0 then
		self.cr:line_to(x3, y3)
		return
	end
	x3 = x3 - x1
   y3 = y3 - y1
	local radii_ratio = ry/rx
	--cancel the rotation of the second point
	local xe, ye = rotate(x3, y3, -rotation)
	ye = ye / radii_ratio
	-- find the angle between the second point and the x axis
	local angle = point_angle(0, 0, xe, ye)
	-- put the second point onto the x axis
	xe = (xe^2 + ye^2)^.5
	ye = 0
	rx = math.max(rx, xe / 2) --update the x radius if it is too small
	-- find one circle centre
	local xc = xe / 2
	local yc = (rx^2 - xc^2)^.5
	-- choose between the two circles according to flags
	if large + sweep ~= 1 then yc = -yc end
	-- define the arc sweep
	local arc = sweep == 1 and self.cr.arc or self.cr.arc_negative
	-- put the second point and the center back to their positions
	xe, ye = rotate(xe, 0, angle)
	xc, yc = rotate(xc, yc, angle)
	-- find the drawing angles
	local angle1 = point_angle(xc, yc, 0, 0)
	local angle2 = point_angle(xc, yc, xe, ye)
	-- draw the arc
	local mt = self.cr:get_matrix()
	self.cr:translate(x1, y1)
	self.cr:rotate(rotation)
	self.cr:scale(1, radii_ratio)
	arc(self.cr, xc, yc, rx, angle1, angle2)
	self.cr:set_matrix(mt)
end

local function opposite_point(x, y, cx, cy)
	return 2*cx-(x or cx), 2*cy-(y or cy)
end

function SG:set_path(path)
	if self.current_path == path then return end --path is global state, not part of saveable/restorable state
	self.cr:new_path() --no current point after this
	if type(path[1]) ~= 'string' then
		self:error'path must start with a command'
		return
	end
	local i = 1
	local s
	local function get(n)
		for j=1,n do
			if type(path[i+j-1]) ~= 'number' then
				self:error('path: invalid %s arg# %d at index %d: %s, number expected)', s, j, i, type(path[i+j-1]), i)
				return
			end
		end
		i = i + n
		return unpack(path, i-n, i-1)
	end
	local bx, by --last cubic bezier control point
	local qx, qy --last quad bezier control point
	while i <= #path do
		if type(path[i]) == 'string' then --see if command changed
			s = path[i]; i = i + 1
		end
		if s == 'move' then
			self.cr:move_to(get(2))
		elseif s == 'rel_move' then
			self.cr:rel_move_to(get(2))
		elseif s == 'line' then
			self.cr:line_to(get(2))
		elseif s == 'rel_line' then
			self.cr:rel_line_to(get(2))
		elseif s == 'hline' then
			local cpx,cpy = self.cr:get_current_point()
			self.cr:line_to(get(1), cpy)
		elseif s == 'rel_hline' then
			self.cr:rel_line_to(get(1), 0)
		elseif s == 'vline' then
			local cpx,cpy = self.cr:get_current_point()
			self.cr:line_to(cpx, get(1))
		elseif s == 'rel_vline' then
			self.cr:rel_line_to(0, get(1))
		elseif s == 'curve' then
			local x1,y1,x2,y2,x3,y3 = get(6)
			self.cr:curve_to(x1,y1,x2,y2,x3,y3)
			bx,by = x2,y2
		elseif s == 'rel_curve' then
			local x1,y1,x2,y2,x3,y3 = get(6)
			local cpx,cpy = self.cr:get_current_point()
			self.cr:rel_curve_to(x1,y1,x2,y2,x3,y3)
			bx,by = cpx+x2, cpy+y2
		elseif s == 'smooth_curve' then
			local x2,y2,x3,y3 = get(4)
			local x1,y1 = opposite_point(bx, by, self.cr:get_current_point())
			self.cr:curve_to(x1,y1,x2,y2,x3,y3)
			bx,by = x2,y2
		elseif s == 'rel_smooth_curve' then
			local x2,y2,x3,y3 = get(4)
			local cpx, cpy = self.cr:get_current_point()
			local x1, y1 = opposite_point(bx, by, cpx, cpy)
			self.cr:rel_curve_to(x1-cpx,y1-cpy,x2,y2,x3,y3)
			bx,by = cpx+x2, cpy+y2
		elseif s == 'quad_curve' then
			local x1,y1,x2,y2 = get(4)
			self.cr:quad_curve_to(x1,y1,x2,y2)
			qx,qy = x1,y1
		elseif s == 'rel_quad_curve' then
			local x1,y1,x2,y2 = get(4)
			local cpx,cpy = self.cr:get_current_point()
			self.cr:rel_quad_curve_to(x1,y1,x2,y2)
			qx,qy = cpx+x1, cpy+y1
		elseif s == 'smooth_quad_curve' then
			local x2,y2 = get(2)
			local x1,y1 = opposite_point(qx, qy, self.cr:get_current_point())
			self.cr:quad_curve_to(x1,y1,x2,y2)
			qx,qy = x1,y1
		elseif s == 'rel_smooth_quad_curve' then
			local x2,y2 = get(2)
			local cpx, cpy = self.cr:get_current_point()
			local x1,y1 = opposite_point(qx, qy, cpx, cpy)
			self.cr:rel_quad_curve_to(x1-cpx,y1-cpy,x2,y2)
			qx,qy = x1,y1
		elseif s == 'elliptical_arc' then
			local cpx, cpy = self.cr:get_current_point()
			local rx, ry, rotation, large, sweep, x3, y3 = get(7)
			self:draw_elliptical_arc(cpx, cpy, rx, ry, math.rad(rotation), large, sweep, x3, y3)
		elseif s == 'rel_elliptical_arc' then
			local cpx, cpy = self.cr:get_current_point()
			local rx, ry, rotation, large, sweep, x3, y3 = get(7)
			self:draw_elliptical_arc(cpx, cpy, rx, ry, math.rad(rotation), large, sweep, cpx+x3, cpy+y3)
		elseif s == 'close' then
			self.cr:close_path()
		elseif s == 'break' then --only useful for drawing a standalone arc
			self.cr:new_sub_path() --no current point after this
		elseif s == 'arc' then
			local cx, cy, r, a1, a2 = get(5)
			self.cr:arc(cx, cy, r, math.rad(a1), math.rad(a2))
		elseif s == 'negative_arc' then
			local cx, cy, r, a1, a2 = get(5)
			self.cr:arc_negative(cx, cy, r, math.rad(a1), math.rad(a2))
		elseif s == 'rel_arc' then
			local cx, cy, r, a1, a2 = get(5)
			local cpx, cpy = self.cr:get_current_point()
			self.cr:arc(cpx+cx, cpy+cy, r, math.rad(a1), math.rad(a2))
		elseif s == 'rel_negative_arc' then
			local cx, cy, r, a1, a2 = get(5)
			local cpx, cpy = self.cr:get_current_point()
			self.cr:arc_negative(cpx+cx, cpy+cy, r, math.rad(a1), math.rad(a2))
		elseif s == 'ellipse' then
			local cx, cy, rx, ry = get(4)
			local mt = self.cr:get_matrix()
			self.cr:translate(cx, cy)
			self.cr:scale(rx/ry, 1)
			self.cr:translate(-cx, -cy)
			self.cr:new_sub_path()
			self.cr:arc(cx, cy, ry, 0, 2*math.pi)
			self.cr:set_matrix(mt)
			self.cr:close_path()
		elseif s == 'circle' then
			local cx, cy, r = get(3)
			self.cr:new_sub_path()
			self.cr:arc(cx, cy, r, 0, 2*math.pi)
			self.cr:close_path()
		elseif s == 'rect' then
			self.cr:rectangle(get(4))
		elseif s == 'round_rect' then
			self:draw_round_rect(get(5))
		elseif s == 'text' then
			local font,x,y,s = path[i], path[i+1], path[i+2], path[i+3]; i=i+4
			self:set_font(font)
			self.cr:move_to(x,y)
			self.cr:text_path(s)
		else
			self:error('unknown path command %s', s)
			return
		end

		if s ~= 'curve' and s ~= 'rel_curve' and s ~= 'smooth_curve' and s ~= 'rel_smooth_curve' then
			bx, by = nil
		end
		if s ~= 'quad_curve' and s ~= 'rel_quad_curve' and s ~= 'smooth_quad_curve' and s ~= 'rel_smooth_quad_curve' then
			qx, qy = nil
		end
	end
	self.current_path = path
end

local function visible(e)
	return e and not e.hidden and (not e.alpha or e.alpha > 0)
end

local unbounded_operators = glue.index{'in', 'out', 'dest_in', 'dest_atop'}

function SG:paint(e)
	if not visible(e) then return end
	if false and (not e.alpha or e.alpha >= 1) and (not e.operator or e.operator == 'over') then
		self:draw(e)
	else
		local state = self:push_group()
		self:draw(e)
		self:pop_group_to_source(state)
		self:set_operator(e.operator)
		self.cr:paint_with_alpha(e.alpha or 1)
	end
end

function SG:fill(e)
	if not visible(e) then return end
	local state = self:save()
	self.cr:clip()
	self:paint(e)
	self:restore(state)
end

function SG:stroke(e)
	if not visible(e) then return end
	local state = self:push_group()
	self:paint(e)
	self:pop_group_to_source(state)
	self.cr:stroke_preserve()
end

SG.pattern_filters = cairo_enum'CAIRO_FILTER_'
SG.pattern_extends = cairo_enum'CAIRO_EXTEND_'

function SG:set_gradient_source(e)
	local pat = self.cache:get(e)
	if not pat then
		if e.r1 then
			pat = cairo.cairo_pattern_create_radial(e.x1, e.y1, e.r1, e.x2, e.y2, e.r2)
		else
			pat = cairo.cairo_pattern_create_linear(e.x1, e.y1, e.x2, e.y2)
		end
		for i=1,#e,2 do
			local offset, c = e[i], e[i+1]
			pat:add_color_stop_rgba(offset, c[1], c[2], c[3], c[4] or 1)
		end
		pat:set_filter(self.pattern_filters[e.filter or self.defaults.gradient_filter])
		pat:set_extend(self.pattern_extends[e.extend or self.defaults.gradient_extend])
		self.cache:set(e, pat)
	end
	if e.relative then --fill follows the bounding box of the shape on which it is applied
		assert(self.shape_bounding_box, 'relative fill not inside a shape')
		local bx1, by1, bx2, by2 = unpack(self.shape_bounding_box)
		local x, y, w, h = bx1, by1, bx2-bx1, by2-by1
		pat:set_matrix(new_matrix(1/w, 0, 0, 1/h, -x/w, -y/h))
	end
	self.cr:set_source(pat)
end

local function image_source_free(source)
	source.surface:free()
end

local imagefile_load_options = {
		accept = ffi.abi'le' and
			{top_down = true, bgra = true} or
			{top_down = true, argb = true}
}

function SG:load_image_file(e)
	local source = self.cache:get(e)
	if not source then
		--load image
		local imagefile = require'imagefile'
		local img = self:assert(glue.unprotect(glue.pcall(imagefile.load, e, imagefile_load_options)))
		if not img then return end
		--link image bits to a surface
		local surface = cairo.cairo_image_surface_create_for_data(img.data,
									cairo.CAIRO_FORMAT_ARGB32, img.w, img.h, img.w * 4)
		if surface:status() ~= 0 then
			self:error(surface:status_string())
			surface:free()
			return
		end
		--cache it, alnong with the image bits which we need to keep around
		source = newproxy(true)
		local source_t = {
			surface = surface,
			data = img.data,
			w = img.w, h = img.h,
			free = image_source_free
		}
		getmetatable(source).__index = source_t
		getmetatable(source).__gc = image_source_free
		self.cache:set(e, source)
	end
	return source
end

function SG:set_image_source(e)
	local source = self:load_image_file(e.file)
	if not source then return end
	self.cr:set_source_surface(source.surface, 0, 0)
	local pat = self.cr:get_source()
	pat:set_filter(self.pattern_filters[e.filter or self.defaults.image_filter])
	pat:set_extend(self.pattern_extends[e.extend or self.defaults.image_extend])
end

function SG:draw_group(e)
	local mt = self.cr:get_matrix()
	for i=1,#e do
		self:paint(e[i])
		self.cr:set_matrix(mt)
	end
end

function SG:draw_shape(e)
	local mt = self.cr:get_matrix()
	self:set_fill_rule(e.fill_rule)
	self:set_line_width(e.line_width)
	self:set_line_cap(e.line_cap)
	self:set_line_join(e.line_join)
	self:set_miter_limit(e.miter_limit)
	self:set_line_dashes(e.line_dashes)
	self:set_path(e.path)
	self.shape_bounding_box = {self.cr:path_extents()}
	if e.stroke_first then
		self:stroke(e.stroke)
		self.cr:set_matrix(mt)
		self:set_path(e.path)
		self:fill(e.fill)
	else
		self:fill(e.fill)
		self.cr:set_matrix(mt)
		self:set_path(e.path)
		self:stroke(e.stroke)
	end
end

function SG:load_svg_file(e)
	local object = self.cache:get(e)
	if not object then
		local svg_parser = require'svg_parser'
		object = svg_parser.parse(e)
		self.cache:set(e, object)
	end
	return object
end

function SG:draw_svg(e)
	self:paint(self:load_svg_file(e.file))
end

function SG:draw(e)
	self:transform(e)
	if e.type == 'color' then
		self.cr:set_source_rgba(e[1], e[2], e[3], e[4] or 1)
		self:set_operator(nil)
		self.cr:paint()
	elseif e.type == 'gradient' then
		self:set_gradient_source(e)
		self:set_operator(nil)
		self.cr:paint()
	elseif e.type == 'image' then
		self:set_image_source(e)
		self:set_operator(nil)
		self.cr:paint()
	elseif e.type == 'group' then
		self:draw_group(e)
	elseif e.type == 'shape' then
		self:draw_shape(e)
	end
end

function SG:render(e)
	self.cr:identity_matrix()
	self:paint(e)
end

--measuring API

function SG:box_to_device(x1,y1,x2,y2)
	local dx1,dy1 = self.cr:user_to_device(x1,y1)
	local dx2,dy2 = self.cr:user_to_device(x2,y2)
	local dx3,dy3 = self.cr:user_to_device(x1,y2)
	local dx4,dy4 = self.cr:user_to_device(x2,y1)
	return
		math.min(dx1,dx2,dx3,dx4), math.min(dy1,dy2,dy3,dy4),
		math.max(dx1,dx2,dx3,dx4), math.max(dy1,dy2,dy3,dy4)
end

function SG:measure_image(e)
	local source = self:load_image_file(e.file)
	return self:box_to_device(0,0,source.w,source.h)
end

function SG:measure_shape(e)
	self:set_path(e.path)
	if e.stroke then
		self:set_line_width(e.line_width)
		self:set_line_cap(e.line_cap)
		self:set_line_join(e.line_join)
		self:set_miter_limit(e.miter_limit)
		self:set_line_dashes(e.line_dashes)
		self.cr:identity_matrix()
		return self.cr:path_extents()
	else
		self.cr:identity_matrix()
		return self.cr:path_extents()
	end
end

function SG:measure_group(e)
	local mt = self.cr:get_matrix()
	local dx1,dy1,dx2,dy2 = math.huge, math.huge, -math.huge, -math.huge
	for i=1,#e do
		local x1,y1,x2,y2 = self:measure_object(e[i])
		if x1 then
			dx1, dy1 = math.min(dx1,x1), math.min(dy1,y1)
			dx2, dy2 = math.max(dx2,x2), math.max(dy2,y2)
		end
		self.cr:set_matrix(mt)
	end
	if dx1 == math.huge then return end
	return dx1,dy1,dx2,dy2
end

SG.ext_measure = {} --{object_type = measure_function(e) -> x1, y1, x2, y2}

function SG:measure_object(e)
	self:transform(e)
	if e.type == 'group' then
		return self:measure_group(e)
	elseif e.type == 'shape' then
		return self:measure_shape(e)
	elseif e.type == 'svg' then
		return self:measure_svg(e)
	elseif e.type == 'image' then
		return self:measure_image(e)
	elseif self.ext_measure[e.type] then
		return self.ext_measure[e.type](self, e)
	end
end

function SG:measure_svg(e)
	return self:measure_object(self:load_svg_file(e.file))
end

function SG:measure(e)
	self.cr:identity_matrix()
	local x1,y1,x2,y2 = self:measure_object(e)
	return x1,y1,x2,y2
end

--showcase

if not ... then require'sg_cairo_test' end

return SG
