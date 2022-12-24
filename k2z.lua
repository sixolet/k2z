--
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~~~~~~ k2z ~~~~~~~~~~~~~~
-- ~~~~~~~~~ by zbs ~~~~~~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- ~~~~~ a new kria port ~~~~~~~
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- 0.1 ~~~~~~~~~~~~~~~~~~~~~~~~~

screen_graphics = include('lib/screen_graphics')
grid_graphics = include('lib/grid_graphics')
Prms = include('lib/prms')
Onboard = include('lib/onboard')
gkeys = include('lib/gkeys')
mu = require 'musicutil'


-- grid level macros
OFF=0
LOW=2
MED=5
HIGH=12

-- other globals
NUM_TRACKS = 4
NUM_PATTERNS = 16
NUM_SCALES = 16

post_buffer = 'k2z v0.1'

scale_defaults = {
	{0,2,2,1,2,2,2}
,	{0,2,1,2,2,2,1}
,	{0,1,2,2,2,1,2}
,	{0,2,2,2,1,2,2}
,	{0,2,2,1,2,2,1}
,	{0,2,1,2,2,1,2}
,	{0,1,2,2,1,2,2}
,	{0,0,1,0,1,1,1}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
,	{0,0,0,0,0,0,0}
}

page_ranges = {
	{0,1,0} -- trig
,	{1,7,1} -- note
,	{1,7,3} -- octave
,	{1,7,1} -- gate
,	{-1,6,1} -- retrig
,	{1,7,1} -- transpose
,	{1,7,1} -- slide
}
page_map = {
	[6] = 1
,	[7] = 2
,	[8] = 3
,	[9] = 4
,	[15] = 5
,	[16] = 6
}
page_names = {'trig', 'note', 'octave', 'gate','scale','patterns'}
alt_page_names = {'retrig', 'transpose', 'slide'}
combined_page_list = {'trig','note','octave','gate','retrig','transpose','slide','scale','patterns'}
mod_names = {'none','loop','time','prob'}
play_modes = {'forward', 'reverse', 'triangle', 'drunk', 'random'}
prob_map = {0, 25, 50, 100}
div_sync_modes = {'none','track','all'}

time_desc = {
	{	
		'all divs independent'
	},{
		'most divs independent'
	,	'trig & note divs synced'
	},{
		'divs synced in track'
	,	'but tracks independent'
	},{
		'trig & note divs synced'
	,	'other divs synced separate'
	},{
		'all divs synced'
	},{		
		'most divs globally synced'
	,	'trig & note synced separate'
	}
}
config_desc = {
	{
		'trig & note edits synced'
	,	'note & trig edits free'
	},{
		'all loops independent'
	,	'loops synced inside tracks'
	,	'all loops synced'
	}
}

function resolve_menu_param_ranges()
	params:lookup_param('screen_menu_pos').max = get_screen_page().len
	params:lookup_param('screen_submenu_pos').max = get_screen_subpage().len
end

loop_first = -1
loop_last = -1
wavery_light = MED
waver_dir = 1
shift = false

pulse_indicator = 1 -- todo implement

kbuf = {} -- key state buffer, true/false
rbuf = {} -- render buffer, states 0-15 on all 128 positions

g = grid.connect()

function init_grid_buffers()
	for x=1,16 do
		table.insert(kbuf,{})
		table.insert(rbuf,{})
		for y=1,8 do
			kbuf[x][y] = false -- key buffer
			rbuf[x][y] = OFF -- rendering
		end
	end
end

function post(str)
	post_buffer = str
	-- print('post:',str)
end

function intro()
	clock.sleep(2)
	post('by @zbs')
	clock.sleep(2)
	post('based on kria by @tehn')
	clock.sleep(2)
	post(':-)')
end

function key(n,d) Onboard:key(n,d) end
function enc(n,d) Onboard:enc(n,d) end
function g.key(x,y,z) gkeys:key(x,y,z) end

function init()
	init_grid_buffers()
	Prms:add()
	clock.run(visual_ticker)
	clock.run(step_ticker)
	clock.run(intro)
end

function edit_loop(track, first, last)
	local f = math.min(first,last)
	local l = math.max(first,last)
	local p = get_page_name()
	params:set('loop_first_'..p..'_t'..track,f)
	params:set('loop_last_'..p..'_t'..track,l)
	post('t'..track..' '..p..' loop: ['..f..'-'..l..']')
end

function new_pos_for_track(t,p) -- track,page
	local old_pos = params:get('pos_'..p..'_t'..t)
	local first = params:get('loop_first_'..p..'_t'..t)
	local last = params:get('loop_last_'..p..'_t'..t)
	local mode = params:get('playmode_t'..t)
	local new_pos;

	if mode == 1 then -- forward
		new_pos = old_pos + 1
		if out_of_bounds(t,p,new_pos) then
			new_pos = first
		end
	elseif mode == 2 then -- reverse
		new_pos = old_pos - 1
		if out_of_bounds(t,p,new_pos) then
			new_pos = last
		end
	elseif mode == 3 then -- triangle
		local delta = params:get('pipo_dir_t'..t) == 1 and 1 or -1
		new_pos = old_pos + delta
		if out_of_bounds(t,p,new_pos) then 
			new_pos = (delta == 0) and first or last
			params:delta('pipo_dir_t'..t,1)
		end
	elseif mode == 4 then -- drunk
		local delta
		if new_pos == first then delta = 1
		elseif new_pos == last then delta = -1
		else delta = math.random() > 0.5 and 1 or -1
		end
		new_pos = old_pos + delta
		if new_pos > last then 
			new_pos = last
		elseif new_pos < first then
			new_pos = first
		end
		-- ^ have to do it this way vs out_of_bounds() because we want to get to the closest boundary, not necessarily first or last step in loop.

	elseif mode == 5 then --random
		pos = util.round(math.random(first,last))
	end

	return new_pos
end

function make_scale()
	-- todo can probably squish this significantly
	local new_scale = {0,0,0,0,0,0,0}
	local table_from_params = {}
	local output_scale = {}
	for i=1,7 do
		table.insert(table_from_params,params:get('scale_'..params:get('scale_num')..'_deg_'..i))
	end
	for i=2,7 do
		new_scale[i] = new_scale[i-1] + table_from_params[i]
	end
	return new_scale
end

function note_out(t)
	local s = make_scale()
	local n = s[current_val(t,'note')] + s[current_val(t,'transpose')]
	local up_one_octave = false
	print('n before octave switching is '..n)
	if n > 7 then
		n = n - 7
		up_one_octave = true
	end
	n = n + 12*current_val(t,'octave')
	if up_one_octave then n = n + 12 end
	-- naomi, i choose you!
end

function advance()
	for t=1,NUM_TRACKS do
		for k,v in ipairs(combined_page_list) do
			if v == 'scale' or v == 'patterns' then break end
			params:delta('data_t'..t..'_'..v..'_counter',1)
			if 		params:get('data_t'..t..'_'..v..'_counter')
				>	params:get('divisor_'..v..'_t'..t) 
			then
				params:set('data_t'..t..'_'..v..'_counter',1)
				params:set('pos_'..v..'_t'..t,new_pos_for_track(t,v))
			end
		end
		if params:get('data_trig_'..params:get('pos_trig_t'..t)..'_t'..t) == 1 then
			note_out(t)
		end
	end
end

function step_ticker()
	while true do
		clock.sync(1/4)
		if params:get('playing') == 1 then
			advance()
		end
	end
end

function visual_ticker()
	while true do
		clock.sleep(1/30)
		redraw()

		wavery_light = wavery_light + waver_dir
		if wavery_light > MED + 2 then
			waver_dir = -1
		elseif wavery_light < MED - 2 then
			waver_dir = 1
		end
		grid_graphics:render()
	end
end

function redraw()
	screen_graphics:render()
end

function at() -- get active track
	return params:get('active_track')
end

function out_of_bounds(track,p,value)
	-- returns true if value is out of bounds on page p, track
	return 	(value < params:get('loop_first_'..p..'_t'..track))
	or		(value > params:get('loop_last_'..p..'_t'..track))
end

function get_page_name()
	local p
	if params:get('alt_page') == 1 then
		p = alt_page_names[params:get('page')]
	else
		p = page_names[params:get('page')]
	end

	return p
end

function current_val(track,page)
	return params:get('data_'..page..'_'..params:get('pos_'..page..'_t'..track)..'_t'..track)
end

function get_mod_key()
	return mod_names[params:get('mod')]
end

function highlight(l) -- level number
	local o = 15
	if l == LOW then
		o = 3
	elseif l == MED then
		o = 7
	elseif l == HIGH then
		o = 15
	else
		o = l + 2
	end

	return util.clamp(o,0,15)
end

function dim(l) -- level number
	local o
	if l == LOW then
		o = 1
	elseif l == MED then
		o = 3
	elseif l == HIGH then
		o = 9
	else
		o = l - 1
	end

	return util.clamp(o,0,15)
end