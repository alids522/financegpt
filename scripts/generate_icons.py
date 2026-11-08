"""Render the code-defined ledger mark for the Flutter platform icon assets."""
from pathlib import Path
from PIL import Image, ImageDraw
root=Path(__file__).resolve().parents[1]
def render(size):
    scale=size*4;image=Image.new('RGB',(scale,scale),'#456D9A');d=ImageDraw.Draw(image)
    def rect(box,width=3):d.rounded_rectangle(tuple(round(x*scale/48)for x in box),radius=round(scale/32),outline='#FFFFFF',width=max(1,round(width*scale/48)))
    def line(points,width=2):d.line(tuple((round(x*scale/48),round(y*scale/48))for x,y in points),fill='#FFFFFF',width=max(1,round(width*scale/48)))
    rect((13,11,35,37),2);line([(13,19),(35,19)]);line([(23,19),(23,37)]);line([(27,25),(31,25)]);line([(27,31),(31,31)]);line([(17,25),(19,25)]);line([(17,31),(19,31)])
    return image.resize((size,size),Image.Resampling.LANCZOS)
paths=list((root/'android/app/src/main/res').glob('mipmap-*/ic_launcher.png'))+list((root/'ios/Runner/Assets.xcassets/AppIcon.appiconset').glob('*.png'))+list((root/'web/icons').glob('*.png'))+[root/'web/favicon.png']
for path in paths:
    size=Image.open(path).size[0];render(size).save(path)
print('Rendered Finance Tracker icons for Android, iOS, and Web.')
