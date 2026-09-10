-- Owner-approved precise cleanup after imagegen could not preserve the sprite.
-- Input is the inspected historical sheet, not a general white-removal filter.
-- Aseprite performs all raster edits; Python verification only reads images.
-- Parameters: source=<before.png> output=<native.aseprite> sheet=<result.png>
local source = assert(app.params.source, 'source required')
local output = assert(app.params.output, 'output required')
local sheet = assert(app.params.sheet, 'sheet required')
local original = app.open(source)
assert(original.width == 704 and original.height == 88)
local input = Image(original.spec)
input:drawSprite(original, 1)
local pc = app.pixelColor
local function pale(p)
  return pc.rgbaA(p) > 0 and math.min(pc.rgbaR(p), pc.rgbaG(p), pc.rgbaB(p)) >= 150
end
local result = Sprite(88, 88, ColorMode.RGB)
local layer = result.layers[1]
layer.name = 'Original turtle — corrected fringe'
local changed = 0
for frame = 0, 7 do
  if frame > 0 then result:newEmptyFrame() end
  result.frames[frame + 1].duration = 0.08
  local cell = Image(88, 88, ColorMode.RGB)
  for y = 0, 87 do
    for x = 0, 87 do
      local gx = frame * 88 + x
      local value = input:getPixel(gx, y)
      if pale(value) then
        local best, score = nil, math.huge
        -- Copy an existing adjacent outline color, retaining opaque silhouette.
        -- No blur, resampling, alpha changes or invented palette colors.
        for _, d in ipairs({{0,-1},{-1,0},{1,0},{0,1}}) do
          local nx, ny = x + d[1], y + d[2]
          if nx >= 0 and nx < 88 and ny >= 0 and ny < 88 then
            local neighbor = input:getPixel(frame * 88 + nx, ny)
            local luminance = pc.rgbaR(neighbor) + pc.rgbaG(neighbor) + pc.rgbaB(neighbor)
            if pc.rgbaA(neighbor) == 255 and not pale(neighbor) and luminance < score then
              best, score = neighbor, luminance
            end
          end
        end
        assert(best, 'residue lacks original outline neighbor')
        value = best
        changed = changed + 1
      end
      cell:drawPixel(x, y, value)
    end
  end
  if frame == 0 and layer:cel(1) then result:deleteCel(layer:cel(1)) end
  result:newCel(layer, frame + 1, cell, Point(0, 0))
end
assert(changed == 90, 'unexpected source; inspect before editing')
app.activeSprite = result
result:saveAs(output)
app.command.ExportSpriteSheet{ui=false, type=SpriteSheetType.HORIZONTAL,
  textureFilename=sheet, dataFilename='', trimSprite=false, trim=false}
print('Corrected '..changed..' opaque fringe pixels; eight 88x88 frames, 80ms each.')
