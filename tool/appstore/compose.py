"""Собирает кадры для App Store: заголовок, пояснение и экран в рамке."""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW, SPLIT, W_DIR, OUT = sys.argv[1:5]
SF = '/System/Library/Fonts/SFNS.ttf'
BG = (246, 240, 242)
TITLE = (28, 10, 16)
SUB = (110, 92, 98)


def font(size, weight):
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_axes([100, min(96, max(17, size / 3)), 400, weight])
    return f


def mask(w, h, r, k=4):
    m = Image.new('L', (w * k, h * k), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * k - 1, h * k - 1), r * k, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def text_block(c, title, sub, top, tsize, ssize):
    d = ImageDraw.Draw(c)
    y = top
    for line in title.split('\n'):
        f = font(tsize, 700)
        d.text(((c.width - d.textlength(line, font=f)) / 2, y), line, font=f, fill=TITLE)
        y += int(tsize * 1.16)
    y += int(ssize * 0.5)
    for line in sub.split('\n'):
        f = font(ssize, 400)
        d.text(((c.width - d.textlength(line, font=f)) / 2, y), line, font=f, fill=SUB)
        y += int(ssize * 1.3)
    return y


def framed(screen_path, title, sub, size, screen_w, radius, bezel, tsize, ssize):
    W, H = size
    c = Image.new('RGBA', (W, H), BG + (255,))
    bottom = text_block(c, title, sub, int(H * 0.06), tsize, ssize)
    s = Image.open(screen_path).convert('RGBA')
    if s.width > 1500:
        # iPadOS рисует в углу ручку изменения размера окна — закрашиваем фоном.
        bg = s.getpixel((s.width - 160, s.height - 160))
        ImageDraw.Draw(s).rectangle((s.width - 130, s.height - 130, s.width, s.height), fill=bg)
    k = screen_w / s.width
    s = s.resize((screen_w, int(s.height * k)), Image.LANCZOS)
    s.putalpha(mask(s.width, s.height, radius))
    fw, fh = s.width + 2 * bezel, s.height + 2 * bezel
    x, y = (W - fw) // 2, bottom + int(H * 0.035)
    sh = Image.new('RGBA', (fw + 240, fh + 240), (0, 0, 0, 0))
    sh.paste((60, 20, 30, 70), (120, 150), mask(fw, fh, radius + bezel))
    c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(50)), (x - 120, y - 120))
    frame = Image.new('RGBA', (fw, fh), (0, 0, 0, 0))
    frame.paste((22, 22, 24, 255), (0, 0), mask(fw, fh, radius + bezel))
    frame.alpha_composite(s, (bezel, bezel))
    c.alpha_composite(frame, (x, y))
    return c.convert('RGB')


def showcase(w_dir, title, sub, size, tsize, ssize, **_):
    """Виджеты крупно, без чужих иконок и обоев: так их показывают в App Store."""
    W, H = size
    c = Image.new('RGBA', (W, H), BG + (255,))
    top = text_block(c, title, sub, int(H * 0.06), tsize, ssize)
    k = 1.1
    med = Image.open(f'{w_dir}/widget-medium-light.png')
    med = med.resize((int(med.width * k), int(med.height * k)), Image.LANCZOS)
    sm = Image.open(f'{w_dir}/widget-small-light.png')
    sm = sm.resize((int(sm.width * k), int(sm.height * k)), Image.LANCZOS)
    icon = Image.open(f'{w_dir}/icon.png')
    gap = 90
    block = med.height + gap + sm.height
    y = top + (H - top - block) // 2
    x = (W - med.width) // 2

    def put(img, xy, alpha=60):
        sh = Image.new('RGBA', (img.width + 240, img.height + 240), (0, 0, 0, 0))
        sh.paste((60, 20, 30, alpha), (120, 145), img.split()[3])
        c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(45)), (xy[0] - 120, xy[1] - 120))
        c.alpha_composite(img, xy)

    put(med, (x, y))
    y2 = y + med.height + gap
    put(sm, (x, y2))
    # Иконка с подписью — в центре оставшегося места справа.
    right = x + sm.width
    cx = (right + x + med.width) // 2
    iy = y2 + (sm.height - icon.height - 70) // 2
    put(icon, (cx - icon.width // 2, iy), alpha=50)
    d = ImageDraw.Draw(c)
    f = font(46, 500)
    label = 'Расписание'
    d.text((cx - d.textlength(label, font=f) / 2, iy + icon.height + 22), label, font=f, fill=TITLE)
    return c.convert('RGB')


IPHONE = dict(size=(1320, 2868), screen_w=1010, radius=128, bezel=22, tsize=104, ssize=50)
IPAD = dict(size=(2064, 2752), screen_w=1560, radius=44, bezel=26, tsize=118, ssize=56)

slides = [
    ('iphone', f'{SPLIT}/01-home.png', 'Твоё расписание.\nВсегда под рукой',
     'Прямо из личного кабинета,\nработает без интернета'),
    ('iphone', 'widgets', 'Пары\nна главном экране',
     'Следующая пара видна,\nне открывая приложение'),
    ('iphone', f'{RAW}/05-change-light.png', 'Узнаёшь о переносах\nпервым',
     'Перенесли, отменили, сменили\nаудиторию — придёт уведомление'),
    ('iphone', f'{RAW}/02-lesson-light.png', 'Всё о паре\nв одном месте',
     'Аудитория, преподаватель,\nгруппа и ссылка на курс'),
    ('iphone', f'{RAW}/06-calendar-light.png', 'Пары\nв календаре iPhone',
     'Отдельный календарь «РАНХиГС»\nобновляется сам'),
    ('iphone', f'{RAW}/03-account-light.png', 'Напомнит\nзаранее',
     'За 5, 15 или 30 минут\nдо начала пары'),
    ('ipad', f'{RAW}/ipad-01-home-light.png', 'Вся неделя\nна одном экране',
     'Пары по дням, текущая — с рамкой'),
    ('ipad', f'{RAW}/ipad-02-lesson-light.png', 'Всё о паре\nв одном месте',
     'Аудитория, преподаватель, группа и ссылка на курс'),
    ('ipad', f'{RAW}/ipad-04-account-light.png', 'Напомнит заранее',
     'За 5, 15 или 30 минут до начала пары'),
]
n = {'iphone': 0, 'ipad': 0}
for dev, path, title, sub in slides:
    n[dev] += 1
    if path == 'widgets':
        img = showcase(W_DIR, title, sub, **IPHONE)
    else:
        img = framed(path, title, sub, **(IPHONE if dev == 'iphone' else IPAD))
    img.save(f'{OUT}/{dev}-{n[dev]}.png')
print('ok')
