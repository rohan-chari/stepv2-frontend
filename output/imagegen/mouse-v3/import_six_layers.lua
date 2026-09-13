local root = app.params['root']
assert(root, 'root required')
local names = {'tail','far_hind','far_front','near_hind','near_front','body'}
local sprite = Sprite(96, 96, ColorMode.RGB)
for i=2,6 do sprite:newEmptyFrame() end
for index,name in ipairs(names) do
  local layer = index == 1 and sprite.layers[1] or sprite:newLayer()
  layer.name = name
  local source = app.open(root .. '/six-layer-' .. name .. '.png')
  local flat = Image(source)
  for i=1,6 do
    local cel = Image(96, 96, ColorMode.RGB)
    cel:clear()
    cel:drawImage(flat, Point(-(i-1)*96,0),255,BlendMode.SRC)
    sprite:newCel(layer,i,cel,Point(0,0))
    sprite.frames[i].duration=0.12
  end
  source:close()
end
local tag=sprite:newTag(1,6)
tag.name='walk_loop'
sprite:saveAs(root .. '/mouse_walk_right.aseprite')
print('Saved 6-frame mouse animation with six editable generated-art layers')
