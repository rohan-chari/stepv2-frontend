local image=Image('output/imagegen/mouse-v5/mouse_walk_right.png')
local sprite=Sprite(96,96,ColorMode.RGB)
for i=0,5 do
 if i>0 then sprite:newEmptyFrame() end
 local frame=Image(96,96,ColorMode.RGB)
 frame:drawImage(image,Point(-96*i,0))
 sprite:newCel(sprite.layers[1],i+1,frame,Point(0,0))
 sprite.frames[i+1].duration=0.12
end
sprite:saveAs('output/imagegen/mouse-v5/mouse_walk_right.aseprite')
