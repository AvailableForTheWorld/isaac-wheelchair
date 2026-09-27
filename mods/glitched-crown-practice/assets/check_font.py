"""Check HUD string coverage and draw a 480x270 layout preview from the atlas.

This uses BMFont glyph records, matching main.lua's unscaled DrawStringUTF8
positions. The outlined square is only a target-sprite placeholder; this is
not an in-game screenshot or a test of the game's font loader.
"""

from pathlib import Path
import re
import struct

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "content" / "resources" / "font"
data = (FONT / "gcpractice.fnt").read_bytes()
assert data[:4] == b"BMF\x03", "Expected binary BMFont v3"
blocks = {}
position = 4
while position < len(data):
    kind, length = struct.unpack_from("<BI", data, position)
    position += 5
    blocks[kind] = data[position:position + length]
    position += length
assert position == len(data), "Truncated BMFont block"
records = {}
for position in range(0, len(blocks[4]), 20):
    codepoint, *glyph = struct.unpack_from("<IHHHHhhhBB", blocks[4], position)
    records[chr(codepoint)] = glyph

sources = [path.read_text(encoding="utf-8") for path in sorted((ROOT / "content").rglob("*.lua"))]
literals = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', "\n".join(sources))
labels = [value for value in literals if any(ord(char) > 127 for char in value)]
missing = sorted(set("".join(labels)) - records.keys())
assert not missing, "Missing HUD glyphs: " + "".join(missing)
assert all(chr(code) in records for code in range(32, 127)), "Missing ASCII glyphs"
assert labels, "No Chinese HUD strings found"
print(f"Verified {len(labels)} Chinese string literals and all printable ASCII against {len(records)} glyphs.")
item_source = (ROOT / "content" / "scripts" / "items.lua").read_text(encoding="utf-8")
item_names = re.findall(r'\[(\d+)\] = \{ zh = "([^"]+)", en = "([^"]+)" \}', item_source)
assert len(item_names) == 51 and len({item[0] for item in item_names}) == 51
assert all(all(32 <= ord(char) <= 126 for char in item[2]) for item in item_names)
longest = max(item_names, key=lambda item: sum(records[char][6] for char in item[1]))
assert sum(records[char][6] for char in longest[1]) <= 160
assert all(sum(records[char][6] for char in item[2]) <= 160 for item in item_names)
print("Verified 51 unique item names; Chinese and English names fit the 160px target label at native size.")

atlas = Image.open(FONT / "gcpractice.png").convert("RGBA")
assert set(atlas.getchannel("A").tobytes()) <= {0, 255}, "Expected directly rasterized monochrome glyphs"
assert struct.unpack_from("<h", blocks[1])[0] == 13, "Expected native 13px font"
canvas = Image.new("RGBA", (480, 270), (38, 33, 35, 255))
draw = ImageDraw.Draw(canvas)
# Approximate reserved space for the item-only layer at anchor (390, 92).
# The exact visible bounds depend on the game's current item texture.
draw.rectangle((374, 60, 406, 92), outline=(118, 107, 100, 255))
ink_white = (255, 255, 255, 255)
ink_gold = (255, 209, 89, 255)
ink_green = (115, 255, 153, 255)
ink_blue = (115, 204, 255, 255)
ink_red = (255, 122, 122, 255)


def text(value, x, y, color=ink_white, centered=False):
    if centered:
        x -= sum(records[char][6] for char in value) / 2
    x, y = int(x), int(y)
    for char in value:
        sx, sy, width, height, left, top, advance, page, channel = records[char]
        assert page == 0 and channel == 15
        assert sx + width <= atlas.width and sy + height <= atlas.height
        if width and height:
            alpha = atlas.crop((sx, sy, sx + width, sy + height)).getchannel("A")
            shadow = Image.new("RGBA", (width, height), (8, 8, 8, 166))
            shadow.putalpha(alpha.point(lambda pixel: round(pixel * 0.65)))
            glyph = Image.new("RGBA", (width, height), color)
            glyph.putalpha(alpha)
            canvas.alpha_composite(shadow, (x + left + 1, y + top + 1))
            canvas.alpha_composite(glyph, (x + left, y + top))
        x += advance


# main.lua:OnRender positions and sample counters beyond the former 120 cap.
text("无尽模式", 240, 12, ink_gold, True)
text("已选择: 126", 24, 42)
text("正确: 98  错误: 28", 24, 59)
text("成功率: 77.8%", 24, 76)
text("+1 次数: 7", 24, 93, ink_red)
text("-1 次数: 5", 24, 110, ink_blue)
text("+2 次数: 4", 24, 127, ink_red)
text("-2 次数: 4", 24, 144, ink_blue)
text("历史未分类: 8", 24, 161)
text("当前移速: 1.35", 240, 221, ink_green, True)
text("本次: -1 目标前一个", 240, 245, ink_gold, True)
text("目标道具", 390, 42, ink_green, True)
text(longest[1], 390, 100, ink_white, True)
text("#" + longest[0], 390, 116, (179, 184, 194, 255), True)
canvas.convert("RGB").save(ROOT / "assets" / "hud-layout-preview.png")
print("Saved assets/hud-layout-preview.png (layout mock, no game sprites).")

canvas = Image.new("RGBA", (480, 160), (25, 28, 38, 255))
for index, value in enumerate([
    "错误王冠  无尽模式",
    "已选择: 126  正确: 98  成功率: 77.8%",
    "+1 次数: 7  -1 次数: 5  +2 次数: 4  -2 次数: 4",
    "当前移速: 1.35  本次: -1 目标前一个",
    "丢失的隐形眼镜  神体蘑菇  The Sad Onion #213",
    "准备中 / 识别轮换中 / 道具被改变，本轮重试",
]):
    text(value, 12, 8 + index * 24)
canvas.convert("RGB").save(ROOT / "assets" / "font-preview.png")
print("Saved assets/font-preview.png (native 13px monochrome glyph specimen).")
