"""Chroma-clean and pack complete generated poses; no separate anatomy layers."""
from pathlib import Path
from PIL import Image
import json
p=Path(__file__).resolve().parent
im=Image.open(p/'whole-body-chroma.png').convert('RGBA')
im.putdata([(0,0,0,0) if g>r*1.25 and g>b*1.25 and g>100 else (r,g,b,a) for r,g,b,a in im.getdata()])
im.save(p/'whole-body-clean.png')
frames=[]
for i in range(6):
 c=im.crop(((i%3)*512,(i//3)*512,(i%3+1)*512,(i//3+1)*512))
 c=c.crop(c.getbbox())
 c=c.resize((round(c.width*.18),round(c.height*.18)),Image.Resampling.NEAREST)
 f=Image.new('RGBA',(96,96));f.alpha_composite(c,(92-c.width,78-c.height));frames.append(f)
s=Image.new('RGBA',(576,96))
for i,f in enumerate(frames):s.alpha_composite(f,(i*96,0))
s.save(p/'otter_walk_right.png');frames[0].save(p/'otter_thumb.png')
pre=[]
for f in frames:
 bg=Image.new('RGBA',f.size,'white');bg.alpha_composite(f);pre.append(bg.convert('RGB').resize((384,384),Image.Resampling.NEAREST))
pre[0].save(p/'otter-walk-preview.gif',save_all=True,append_images=pre[1:],duration=120,loop=0)
bg=Image.new('RGBA',s.size,'white');bg.alpha_composite(s);bg.resize((1152,192),Image.Resampling.NEAREST).save(p/'contact-sheet.png')
assert len(set(f.tobytes() for f in frames))==6
assert all(f.getbbox()[0]>0 and f.getbbox()[2]<96 and f.getbbox()[3]==78 for f in frames)
(p/'validation.json').write_text(json.dumps({'frames':6,'dimensions':[576,96],'frameDurationMs':120,'transparentBorders':True,'footBoundary':78,'separateBodyParts':False},indent=2)+'\n')
