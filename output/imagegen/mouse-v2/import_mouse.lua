-- import_sheet.lua — split a horizontal spritesheet PNG into an N-frame .aseprite
-- Usage:
--   aseprite -b -script-param source=in.png -script-param out=out.aseprite \
--            -script-param fw=64 -script-param fh=64 -script import_sheet.lua
--
-- Frames are laid out left→right in a single row of fw×fh cells.
local source = app.params["source"]
local out = app.params["out"]
local fw = tonumber(app.params["fw"])
local fh = tonumber(app.params["fh"])
assert(source and out and fw and fh, "need source, out, fw, fh params")

local sheet = app.open(source)
assert(sheet, "could not open " .. source)

-- Render the whole sheet (all layers) into one flat image.
local flat = Image(sheet)            -- renders frame 1 of the sprite
local n = math.floor(sheet.width // fw)

local dst = Sprite(fw, fh, sheet.colorMode)
if sheet.colorMode == ColorMode.INDEXED then
  dst:setPalette(sheet.palettes[1])
end
local layer = dst.layers[1]
layer.name = "mouse"

for i = 1, n do
  if i > 1 then dst:newEmptyFrame() end
  local cel = Image(fw, fh, dst.colorMode)
  cel:clear()
  cel:drawImage(flat, Point(-(i - 1) * fw, 0), 255, BlendMode.SRC)
  dst:newCel(layer, i, cel, Point(0, 0))
  dst.frames[i].duration = 0.06     -- 12.5 fps default; tune in Aseprite
end

dst:saveAs(out)
print(string.format("wrote %s  (%d frames of %dx%d)", out, n, fw, fh))
