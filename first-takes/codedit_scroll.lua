--codedit scrolling

if not ... then require'codedit_demo'; return end

local editor = require'codedit_editor'

local function clamp(x, a, b)
	return math.min(math.max(x, a), b)
end

--invisible cursor margins for scrolling, in pixels
editor.scroll_margins = {left = 0, top = 0, right = 0, bottom = 0}

--how many lines are in the clipping rect
function editor:pagesize()
	return math.floor(self.clip_h / self.linesize)
end

--view rect from the pov. of the clip rect
function editor:buffer_rect()
	return self.scroll_x, self.scroll_y, self:buffer_dimensions()
end

--clip rect from the pov. of the buffer rect
function editor:clip_rect()
	return -self.scroll_x, -self.scroll_y, self.clip_w, self.clip_h
end

function editor:scroll_by(x, y)
	self.scroll_x = self.scroll_x + x
	self.scroll_y = self.scroll_y + y
end

function editor:scroll_up()
	self:scroll_by(0, self.linesize)
	--TODO: move cursor into view
end

function editor:scroll_down()
	self:scroll_by(0, -self.linesize)
	--TODO: move cursor into view
end

--scroll the editor to make a specific character visible
function editor:make_char_visible(line, vcol)
	--find the cursor rectangle that needs to be completely in the editor rectangle
	local x, y = self:char_coords(line, vcol)
	local w = self.charsize
	local h = self.linesize
	--enlarge the cursor rectangle with margins
	x = x - self.scroll_margins.left
	y = y - self.scroll_margins.top
	w = w + self.scroll_margins.right
	h = h + self.scroll_margins.bottom
	--compute the scroll offset (client area coords)
	self.scroll_x = -clamp(-self.scroll_x, x + w - self.clip_w, x)
	self.scroll_y = -clamp(-self.scroll_y, y + h - self.clip_h, y)
end

--which editor lines are (partially or entirely) visibile given the current vertical scroll
function editor:visible_lines()
	local line1 = math.floor(-self.scroll_y / self.linesize) + 1
	local line2 = math.ceil((-self.scroll_y + self.clip_h) / self.linesize)
	line1 = clamp(line1, 1, #self.buffer.lines)
	line2 = clamp(line2, 1, #self.buffer.lines)
	return line1, line2
end

