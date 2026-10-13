"""Вырезает виджеты с домашнего экрана симулятора и собирает варианты кадра."""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

src, out = sys.argv[1], sys.argv[2]
SF = '/System/Library/Fonts/SFNS.ttf'


def font(size, weight):
    f = ImageFont.truetype(SF, size)
    try:
        # Оси SF: ширина, оптический размер, GRAD, насыщенность.
        f.set_variation_by_axes([100, min(96, max(17, size / 3)), 400, weight])
    except Exception:
        pass
    return f


def rounded_mask(w, h, r, k=4):
    m = Image.new('L', (w * k, h * k), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * k - 1, h * k - 1), r * k, fill=255)
    return m.resize((w, h), Image.LANCZOS)


BOXES = {'medium': (98, 285, 1222, 809), 'small': (98, 937, 622, 1461)}
cut = {}
# Иконка приложения с домашнего экрана, крупнее, чем там.
_home = Image.open(f'{src}/home-light.png').convert('RGBA')
_ic = _home.crop((716, 1593, 906, 1783)).resize((300, 300), Image.LANCZOS)
_ic.putalpha(rounded_mask(300, 300, 70))
_ic.save(f'{out}/icon.png')
for theme in ('light', 'dark'):
    im = Image.open(f'{src}/home-{theme}.png').convert('RGBA')
    for name, box in BOXES.items():
        w = im.crop(box)
        w.putalpha(rounded_mask(w.width, w.height, 86))
        w.save(f'{out}/widget-{name}-{theme}.png')
        cut[name, theme] = w


def shadowed(canvas, img, xy, blur=40, alpha=60, dy=24):
    sh = Image.new('RGBA', (img.width + blur * 4, img.height + blur * 4), (0, 0, 0, 0))
    a = img.split()[3].point(lambda v: v * alpha // 255)
    sh.paste((0, 0, 0, 255), (blur * 2, blur * 2), a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(sh, (xy[0] - blur * 2, xy[1] - blur * 2 + dy))
    canvas.alpha_composite(img, xy)


def caption(canvas, title, sub, color, subcolor, top=230):
    d = ImageDraw.Draw(canvas)
    W = canvas.width
    y = top
    for line in title.split('\n'):
        f = font(112, 700)
        tw = d.textlength(line, font=f)
        d.text(((W - tw) / 2, y), line, font=f, fill=color)
        y += 130
    f = font(56, 400)
    y += 20
    for line in sub.split('\n'):
        tw = d.textlength(line, font=f)
        d.text(((W - tw) / 2, y), line, font=f, fill=subcolor)
        y += 72


W, H = 1320, 2868
TITLE = 'Пары\nна главном экране'
SUB = 'Следующая пара видна,\nне открывая приложение'

# A. Витрина: виджеты крупно на однотонном фоне.
for theme, bg, fg, sub in (
    ("light", (246, 240, 242), (28, 10, 16), (110, 92, 98)),
    ('accent', (142, 27, 46), (255, 255, 255), (245, 205, 210)),
    ('dark', (0, 0, 0), (255, 255, 255), (152, 152, 157)),
):
    c = Image.new('RGBA', (W, H), bg + (255,))
    wt = 'dark' if theme == 'dark' else 'light'
    scale = 1.08
    m = cut['medium', wt].resize((int(1124 * scale), int(524 * scale)), Image.LANCZOS)
    sm = cut['small', wt].resize((int(524 * scale), int(524 * scale)), Image.LANCZOS)
    group = 470 + 110 + m.height + 60 + sm.height
    top = (H - group) // 2
    caption(c, TITLE, SUB, fg, sub, top=top)
    y = top + 470 + 110
    x = (W - m.width) // 2
    shadowed(c, m, (x, y))
    shadowed(c, sm, (x, y + m.height + 60))
    c.convert('RGB').save(f'{out}/variant-A-{theme}.png')

# B. Чистый домашний экран: только наши виджеты и иконка на спокойном фоне.
for theme in ('light', 'dark'):
    base = Image.open(f'{src}/home-{theme}.png').convert('RGBA')
    top, bottom = ((236, 226, 230), (205, 170, 180)) if theme == 'light' else ((60, 20, 30), (20, 8, 12))
    wall = Image.new('RGBA', (W, H))
    d = ImageDraw.Draw(wall)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    # Строка состояния: белые значки с тёмного кадра.
    dark = Image.open(f'{src}/home-dark.png').convert('RGBA').crop((0, 0, W, 160))
    lum = dark.convert('L').point(lambda v: 255 if v > 200 else 0)
    fg = (0, 0, 0, 255) if theme == 'light' else (255, 255, 255, 255)
    bar = Image.new('RGBA', (W, 160), (0, 0, 0, 0))
    bar.paste(fg, (0, 0), lum)
    wall.alpha_composite(bar, (0, 0))
    for name, box in BOXES.items():
        wall.alpha_composite(cut[name, theme], box[:2])
    # Иконка приложения с подписью — тоже с кадра.
    icon_box = (708, 1585, 913, 1790)
    ic = base.crop(icon_box)
    ic.putalpha(rounded_mask(ic.width, ic.height, 52))
    wall.alpha_composite(ic, icon_box[:2])
    lf = font(40, 500)
    dd = ImageDraw.Draw(wall)
    for (label, cx, cy) in (('Расписание', 660, 850), ('Расписание', 360, 1500), ('Расписание', 810, 1825)):
        tw = dd.textlength(label, font=lf)
        dd.text((cx - tw / 2, cy), label, font=lf, fill=fg)
    wall.convert('RGB').save(f'{out}/variant-B-{theme}.png')
print('ok')
