# Original Lumi geometric artwork, CC0-1.0. Requires Pillow.
from PIL import Image,ImageDraw
import sqlite3,os,json,zipfile,tempfile,hashlib,math,shutil
from pathlib import Path
output = Path(__file__).resolve().parents[2] / "Lumi/Resources/Lumi-Starter-Memes.zip"
items=[('happy','开心','开心 高兴 耶 笑'),('shy','害羞','害羞 撒娇 脸红'),('sad','难过','难过 伤心 哭'),('angry','生气','生气 哼 愤怒'),('confused','疑惑','疑惑 问号 不懂'),('sigh','无语','无语 叹气'),('comfort','抱抱','抱抱 安慰 陪伴'),('like','比心','喜欢 比心 爱'),('sleep','晚安','晚安 困 睡觉'),('morning','早安','早安 早上好 你好'),('happy','收到','收到 好的 点赞 OK'),('comfort','加油','加油 鼓励 支持')]
folder=tempfile.mkdtemp(prefix='lumi-starter-');os.mkdir(folder+'/memes')
db=sqlite3.connect(folder+'/index.db');db.execute('CREATE TABLE memes(path TEXT PRIMARY KEY,tag TEXT,file_name TEXT,caption TEXT,keywords TEXT,mtime REAL,captioned_at REAL)')
checks={}
for i,(mood,caption,keywords) in enumerate(items):
 im=Image.new('RGBA',(320,320),(0,0,0,0));d=ImageDraw.Draw(im);col=[(253,210,158),(242,195,195),(174,207,209),(249,181,153),(194,189,230),(186,210,191)][i%6]
 points=[]
 for j in range(10):
  a=-math.pi/2+j*math.pi/5;r=126 if j%2==0 else 92;points.append((160+math.cos(a)*r,164+math.sin(a)*r))
 d.polygon(points,fill=col);d.ellipse((91,153,120,169),fill=(250,146,142));d.ellipse((201,153,230,169),fill=(250,146,142))
 if mood in ['happy','comfort','morning','like']:
  d.arc((118,133,140,154),180,355,fill=(67,61,65),width=5);d.arc((180,133,202,154),180,355,fill=(67,61,65),width=5);d.arc((144,150,177,177),0,180,fill=(67,61,65),width=5)
 elif mood=='sleep':
  d.line((118,145,140,145),fill=(67,61,65),width=5);d.line((180,145,202,145),fill=(67,61,65),width=5);d.ellipse((154,164,166,174),fill=(67,61,65))
 elif mood=='angry':
  d.line((116,133,139,144),fill=(67,61,65),width=5);d.line((182,144,204,133),fill=(67,61,65),width=5);d.arc((148,165,174,183),180,360,fill=(67,61,65),width=5)
 else:
  d.ellipse((126,139,135,150),fill=(67,61,65));d.ellipse((185,139,194,150),fill=(67,61,65));d.line((151,173,169,173),fill=(67,61,65),width=4)
  if mood=='sad':d.ellipse((129,153,139,181),fill=(108,175,228))
  if mood=='shy':d.arc((145,154,176,178),0,180,fill=(67,61,65),width=4)
 path='memes/%02d.png'%i;im.save(folder+'/'+path)
 checks[path]=hashlib.sha256(open(folder+'/'+path,'rb').read()).hexdigest()
 db.execute('INSERT INTO memes VALUES(?,?,?,?,?,0,0)',(path,mood,os.path.basename(path),caption,keywords))
db.commit();db.close();checks['index.db']=hashlib.sha256(open(folder+'/index.db','rb').read()).hexdigest()
manifest={'id':'lumi-starter','name':'Lumi 小星星','description':'12 张原创几何小星星占位表情；每张均为代码绘制，无外部素材。','version':'1.0.0','license':'CC0-1.0','source':'Lumi original geometric placeholder artwork, 2026-11-01'}
open(folder+'/manifest.json','w').write(json.dumps(manifest,ensure_ascii=False))
open(folder+'/checksums.json','w').write(json.dumps(checks))
with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
 for parent,_,files in os.walk(folder):
  for f in files:z.write(parent+'/'+f,os.path.relpath(parent+'/'+f,folder))

shutil.rmtree(folder)
