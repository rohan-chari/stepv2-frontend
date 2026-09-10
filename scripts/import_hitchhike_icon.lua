-- Derive the existing production canvases from approved imagegen artwork.
-- Aseprite -b --script-param source=/path/generated.png
--   --script-param output=/path/powerups --script import_hitchhike_icon.lua
-- This resamples generated art; it does not draw a replacement hand.
local sourcePath = assert(app.params.source, 'source required')
local output = assert(app.params.output, 'output required')
local source = app.open(sourcePath)
local input = source.cels[1].image
local rgba = app.pixelColor
local minX, minY, maxX, maxY = input.width, input.height, -1, -1
-- Remove faint generation residue; preserve the opaque black outline.
for y = 0, input.height - 1 do
  for x = 0, input.width - 1 do
    if rgba.rgbaA(input:getPixel(x, y)) >= 128 then
      minX, minY = math.min(minX, x), math.min(minY, y)
      maxX, maxY = math.max(maxX, x), math.max(maxY, y)
    end
  end
end
assert(maxX >= minX, 'empty generated artwork')
for _, size in ipairs({{128, 128, 'hitchhike'}, {106, 88, 'hitchhike_thumb'}}) do
  local width, height, name = size[1], size[2], size[3]
  local sprite = Sprite(width, height, ColorMode.RGB)
  local image = sprite.cels[1].image
  local scale = math.min((width - 12) / (maxX-minX+1), (height - 12) / (maxY-minY+1))
  local w = math.floor((maxX-minX+1)*scale + .5)
  local h = math.floor((maxY-minY+1)*scale + .5)
  local left, top = math.floor((width-w)/2), math.floor((height-h)/2)
  for y = 0, h-1 do
    for x = 0, w-1 do
      local sx = math.min(maxX, minX + math.floor((x+.5)*(maxX-minX+1)/w))
      local sy = math.min(maxY, minY + math.floor((y+.5)*(maxY-minY+1)/h))
      local p = input:getPixel(sx, sy)
      if rgba.rgbaA(p) >= 128 then
        image:drawPixel(left+x, top+y, rgba.rgba(rgba.rgbaR(p), rgba.rgbaG(p), rgba.rgbaB(p),255))
      end
    end
  end
  sprite:saveAs(output..'/'..name..'.png')
  sprite:saveAs(output..'/'..name..'.aseprite')
  sprite:close()
end
source:close()
