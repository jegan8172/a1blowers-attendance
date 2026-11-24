from PIL import Image, ImageDraw
import glob, os

paths = sorted(glob.glob(r"tmp\pdfs\expanded-report-*.png"))
thumb_w = 306
thumb_h = 396
margin = 18
cols = 3
rows = (len(paths) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (thumb_w + margin) + margin, rows * (thumb_h + 34 + margin) + margin), "#dfe6f2")
draw = ImageDraw.Draw(sheet)
for i, path in enumerate(paths):
    image = Image.open(path).convert("RGB")
    image.thumbnail((thumb_w, thumb_h))
    x = margin + (i % cols) * (thumb_w + margin)
    y = margin + (i // cols) * (thumb_h + 34 + margin)
    sheet.paste(image, (x + (thumb_w - image.width) // 2, y))
    draw.text((x, y + thumb_h + 7), f"Page {i + 1}", fill="#081b3c")
sheet.save(r"tmp\pdfs\expanded-report-contact-sheet.png")
