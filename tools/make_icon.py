"""Minimal PaperDaily icon: one cream page on flat indigo, top-right corner folded over in amber."""
from PIL import Image, ImageDraw
import sys

S = 4096
INDIGO = (30, 35, 82)
CREAM = (243, 233, 210)
AMBER = (242, 166, 90)

img = Image.new("RGB", (S, S), INDIGO)
d = ImageDraw.Draw(img)

w, h = 2060, 2680            # page proportions ~ A-series
x0, y0 = (S - w) // 2, (S - h) // 2
x1, y1 = x0 + w, y0 + h
r = 170                       # corner radius of the page
fold = 740                    # size of the folded corner

d.rounded_rectangle([x0, y0, x1, y1], r, fill=CREAM)
# cut the top-right corner away (diagonal)
d.polygon([(x1 - fold, y0 - 2), (x1 + 2, y0 - 2), (x1 + 2, y0 + fold)], fill=INDIGO)
# the folded flap: shows the back of the page, in amber
d.polygon([(x1 - fold, y0), (x1 - fold, y0 + fold), (x1, y0 + fold)], fill=AMBER)

img.resize((1024, 1024), Image.LANCZOS).save(sys.argv[1], "PNG")
print("saved", sys.argv[1])
