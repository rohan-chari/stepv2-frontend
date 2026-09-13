"""Composite generated sprite parts; creates no drawn artwork.

All motion is periodic. Paws follow a continuous stance/swing path, the generated
torso bobs and pitches, and the generated tail rotates about its attachment.
"""
from pathlib import Path
import math
import json
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent
SIZE, COUNT = 96, 24
TAU = math.tau

def load(name, size):
    return Image.open(ROOT / (name + '.png')).convert('RGBA').resize(size, Image.Resampling.NEAREST)

torso = load('torso', (44, 31))
head = load('head', (34, 33))
tail = load('tail', (29, 12))
parts = {name: load(name, size) for name,size in [('near_front',(12,19)),('near_hind',(10,18)),('far_front',(8,17)),('far_hind',(9,17))]}

def affine(image, matrix, translation):
    inv = np.linalg.inv(matrix)
    shift = -inv @ np.asarray(translation)
    coefficients = (inv[0,0], inv[0,1], shift[0], inv[1,0], inv[1,1], shift[1])
    return image.transform((SIZE, SIZE), Image.Transform.AFFINE, coefficients, Image.Resampling.BICUBIC)

def rotated(image, pivot, target, angle):
    c, s = math.cos(angle), math.sin(angle)
    matrix = np.array(((c,-s),(s,c)))
    return affine(image, matrix, np.asarray(target) - matrix @ np.asarray(pivot))

def body_state(t):
    bob = 1.5 * math.cos(2 * TAU * t)
    pitch = math.radians(1.8) * math.sin(TAU * t)
    c, s = math.cos(pitch), math.sin(pitch)
    matrix = np.array(((c,-s),(s,c)))
    pivot = np.array((30., 32.))
    target = np.array((57., 61. + bob))
    return matrix, target - matrix @ pivot

def pose(t):
    t %= 1.
    matrix, translation = body_state(t)
    def attach(local): return matrix @ np.array(local) + translation
    layers = {}
    root = attach((3., 30.))
    layers['tail'] = rotated(tail, (28., 9.), root, math.radians(4.) * math.sin(TAU*t + .4))
    traces = {}
    for name,local,phase in (
        ('far_hind',(9.,32.),0.), ('far_front',(36.,29.),.5),
        ('near_hind',(11.,34.),.5), ('near_front',(41.,29.),0.),
    ):
        p = (t + phase) % 1.
        hip = attach(local)
        stride = 4.6 * math.cos(TAU*p)
        lift = 0. if p <= .5 else 3.6 * math.sin(TAU*(p-.5))**2
        ground = 74.5 if name.startswith('far') else 76.
        foot = np.array((27.+local[0] + stride, ground-lift))
        image = parts[name]
        start = np.array((image.width*.4,image.height*.11))
        end = np.array((image.width*.6,image.height*.92))
        original = end - start
        length = np.linalg.norm(original)
        src_u = original / length
        src_v = np.array((-src_u[1],src_u[0]))
        delta = foot - hip
        dst_u = delta / np.linalg.norm(delta)
        dst_v = np.array((-dst_u[1],dst_u[0]))
        transform = np.outer(delta / length, src_u) + np.outer(dst_v, src_v)
        layers[name] = affine(image, transform, hip - transform @ start)
        traces[name] = {'hip':hip.tolist(), 'foot':foot.tolist(), 'stance':p<=.5, 'ground':ground}
    # The generated body covers the rounded limb attachment ends.
    layers['torso'] = affine(torso, matrix, translation + matrix @ np.array((0.,12.)))
    neck = attach((34.,24.)) + np.array((.5*math.sin(TAU*t),.55*math.sin(2*TAU*t+.9)))
    nod = math.atan2(matrix[1,0],matrix[0,0]) + math.radians(4.5)*math.sin(2*TAU*t+.9)
    layers['head'] = rotated(head,(8.,24.),neck,nod)
    # Feather only the generated neck attachment where opaque torso lies below.
    # Exposed head/ear/cheek contours keep their original alpha and pixel texture.
    head_pixels = np.array(layers['head'])
    torso_alpha = np.asarray(layers['torso'].getchannel('A'))
    yy,xx = np.mgrid[0:SIZE,0:SIZE]
    c,s = math.cos(nod),math.sin(nod)
    source_x = c*(xx-neck[0]) + s*(yy-neck[1]) + 8.
    source_y = -s*(xx-neck[0]) + c*(yy-neck[1]) + 24.
    neck_overlap = (source_x<16) & (source_y>18) & (torso_alpha>250)
    inner_alpha = np.asarray(layers['head'].getchannel('A').filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(.55)))
    head_pixels[:,:,3] = np.where(neck_overlap, np.minimum(head_pixels[:,:,3],inner_alpha), head_pixels[:,:,3])
    layers['head'] = Image.fromarray(head_pixels)
    order = ('tail','far_hind','far_front','near_hind','torso','near_front','head')
    composite = Image.new('RGBA',(SIZE,SIZE))
    for key in order: composite.alpha_composite(layers[key])
    return composite, layers, traces

frames=[]
layer_sheets={key:Image.new('RGBA',(SIZE*COUNT,SIZE)) for key in ('tail','far_hind','far_front','near_hind','torso','near_front','head')}
traces=[]
for i in range(COUNT):
    frame,layers,trace=pose(i/COUNT)
    frames.append(frame)
    traces.append(trace)
    for key,layer in layers.items(): layer_sheets[key].alpha_composite(layer,(i*SIZE,0))
sheet=Image.new('RGBA',(SIZE*COUNT,SIZE))
for i,frame in enumerate(frames): sheet.alpha_composite(frame,(i*SIZE,0))
sheet.save(ROOT/'mouse_walk_right.png')
frames[0].save(ROOT/'mouse_thumb.png')
for key,layer in layer_sheets.items():layer.save(ROOT/('layer-'+key+'.png'))
contact=Image.new('RGBA',(SIZE*8,SIZE*3),'white')
for i,frame in enumerate(frames):contact.alpha_composite(frame,((i%8)*SIZE,(i//8)*SIZE))
contact.resize((1536,576),Image.Resampling.NEAREST).convert('RGB').save(ROOT/'contact-sheet.png')
previews=[]
for frame in frames:
    white=Image.new('RGBA',(SIZE,SIZE),'white');white.alpha_composite(frame)
    previews.append(white.resize((384,384),Image.Resampling.NEAREST).convert('RGB'))
previews[0].save(ROOT/'mouse-walk-preview.gif',save_all=True,append_images=previews[1:],duration=30,loop=0,disposal=2)
# Validate the mathematical loop, including the interval omitted by pose sheets.
assert pose(0)[0].tobytes()==pose(1)[0].tobytes()
assert len({f.tobytes() for f in frames})==COUNT
body0=pose(0)[1]['torso'];body6=pose(.25)[1]['torso'];assert body0.tobytes()!=body6.tobytes()
assert pose(0)[1]['head'].tobytes()!=pose(.25)[1]['head'].tobytes()
assert all(f.getbbox()[0]>0 and f.getbbox()[2]<SIZE and f.getbbox()[1]>0 and f.getbbox()[3]<SIZE for f in frames)
for trace in traces:
    for leg in trace.values():
        if leg['stance']:assert abs(leg['foot'][1]-leg['ground'])<1e-8
diffs=[]
for i in range(COUNT):
    a=np.asarray(frames[i],dtype=float);b=np.asarray(frames[(i+1)%COUNT],dtype=float)
    diffs.append(float(np.abs(a-b).mean()))
assert diffs[-1] <= max(diffs[:-1])*1.1
evidence={'frames':COUNT,'frameSize':SIZE,'cycleMs':720,'fullPeriodPixelMatch':True,'distinctFrames':COUNT,'bodyMoves':True,'independentHeadNod':True,'frontLegDepth':{'farWidth':8,'nearWidth':12,'farGround':74.5,'nearGround':76,'farShoulderX':36,'nearShoulderX':41},'stanceGroundY':76,'cyclicFrameDifferences':diffs,'lastToFirstDifference':diffs[-1],'maxOtherDifference':max(diffs[:-1])}
(ROOT/'animation-validation.json').write_text(json.dumps(evidence,indent=2)+'\n')
print(json.dumps(evidence))
