"""Собирает кадры для App Store: заголовок, пояснение и экран в рамке."""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW, W_DIR, OUT = sys.argv[1:4]
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
    k = 1.08
    med = Image.open(f'{w_dir}/widget-medium-light.png')
    med = med.resize((int(med.width * k), int(med.height * k)), Image.LANCZOS)
    big = Image.open(f'{w_dir}/widget-large-light.png')
    big = big.resize((int(big.width * k), int(big.height * k)), Image.LANCZOS)
    gap = 80
    block = med.height + gap + big.height
    y = top + (H - top - block) // 2
    x = (W - med.width) // 2

    def put(img, xy, alpha=60):
        sh = Image.new('RGBA', (img.width + 240, img.height + 240), (0, 0, 0, 0))
        sh.paste((60, 20, 30, alpha), (120, 145), img.split()[3])
        c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(45)), (xy[0] - 120, xy[1] - 120))
        c.alpha_composite(img, xy)

    put(med, (x, y))
    put(big, (x, y + med.height + gap))
    return c.convert('RGB')


IPHONE = dict(size=(1320, 2868), screen_w=1010, radius=128, bezel=22, tsize=104, ssize=50)
IPAD = dict(size=(2064, 2752), screen_w=1560, radius=44, bezel=26, tsize=118, ssize=56)

def split_home():
    """Главный экран: светлая и тёмная тема, разделённые по диагонали."""
    light = Image.open(f'{RAW}/home-light.png').convert('RGB')
    dark = Image.open(f'{RAW}/home-dark.png').convert('RGB')
    w, h = light.size
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).polygon([(w, int(h * 0.42)), (w, h), (0, h), (0, int(h * 0.58))], fill=255)
    light.paste(dark, (0, 0), m)
    path = f'{RAW}/home-split.png'
    light.save(path)
    return path


def no_date(path):
    """iPad: в строке состояния — настоящая дата, а не дата демо. Убираем её."""
    s = Image.open(path).convert('RGB')
    bg = s.getpixel((400, 12))
    ImageDraw.Draw(s).rectangle((130, 0, 600, 60), fill=bg)
    out = path.replace('.png', '-nodate.png')
    s.save(out)
    return out


slides = [
    ('iphone', split_home(), 'Твоё расписание.\nВсегда под рукой',
     'Прямо из личного кабинета,\nработает без интернета'),
    ('iphone', 'widgets', 'Пары\nна главном экране',
     'Сколько до конца пары —\nне открывая приложение'),
    ('iphone', f'{RAW}/session.png', 'Сессия\nбез сюрпризов',
     'Все экзамены и зачёты,\nнапомнит накануне'),
    ('iphone', f'{RAW}/subjects.png', 'Все предметы\nсеместра',
     'Что сдавать по каждому —\nиз плана обучения'),
    ('iphone', f'{RAW}/subject.png', 'Всё о предмете\nв одном месте',
     'Экзамен, преподаватель\nи все пары до конца семестра'),
    ('iphone', f'{RAW}/lesson.png', 'Где пара —\nвидно сразу',
     'Корпус на карте, аудитория\nи преподаватель'),
    ('iphone', f'{RAW}/account.png', 'Напомнит\nзаранее',
     'О паре, о переносе\nи об отмене'),
    ('ipad', no_date(f'{RAW}/ipad-home.png'), 'Вся неделя\nна одном экране',
     'Идущая пара — с остатком времени'),
    ('ipad', no_date(f'{RAW}/ipad-session.png'), 'Сессия без сюрпризов',
     'Все экзамены и зачёты, напомнит накануне'),
    ('ipad', no_date(f'{RAW}/ipad-subject.png'), 'Всё о предмете в одном месте',
     'Экзамен, преподаватель и все пары'),
]
n = {'iphone': 0, 'ipad': 0}
for dev, path, title, sub in slides:
    n[dev] += 1
    if path == 'widgets':
        img = showcase(W_DIR, title, sub, **IPHONE)
    else:
        img = framed(path, title, sub, **(IPHONE if dev == 'iphone' else IPAD))
    img.save(f'{OUT}/{dev}-{n[dev]}.png')
    if dev == 'iphone':
        # 6,3": тот же кадр меньше.
        img.resize((1206, 2622), Image.LANCZOS).save(f'{OUT}/{dev}-63-{n[dev]}.png')
print('ok')
