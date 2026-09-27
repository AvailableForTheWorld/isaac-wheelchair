"""Build the trainer's small binary BMFont v3 atlas from an installed font.

Requires Pillow. No source TTF/TTC is copied into the mod. The shipped raster
atlas covers HUD labels, this trainer's item names, and printable ASCII.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import re
import struct

from PIL import Image, ImageFont


LABELS = """
无尽模式 错误王冠 已选择 正确 错误 成功率 次数 提前一项 滞后一项
上一个 下一个 目标道具 准备中 识别轮换中 本次 选中目标 提前两项 滞后两项
道具被改变，本轮重试 下一轮 暂停 无上限 统计已保留 偏差 目标前一个 目标后一个
单人练习 请重新开局 继续游戏 本轮无效 总计 按键 重新开始 重置 等待 移动拾取
循环顺序 命中 其他 连续 最佳 未知 练习结束 房间 唯一五选一 错误王冠无尽练习
原生 拾取后 自动进行 种子 保存成功 悔改 中文 状态 提示 说明 时机 成绩 当前移速
：，。（）【】→←·％
"""


def block(kind: int, payload: bytes) -> bytes:
    return struct.pack("<BI", kind, len(payload)) + payload


def chinese_literals() -> str:
    """Collect authored HUD/name literals without importing game-only Lua code."""
    content = Path(__file__).resolve().parents[1] / "content"
    values = []
    for path in sorted(content.rglob("*.lua")):
        source = path.read_text(encoding="utf-8")
        for match in re.finditer(r'"([^"\\]*(?:\\.[^"\\]*)*)"', source):
            value = match.group(1)
            if any(ord(char) > 127 for char in value):
                values.append(value)
    return "".join(values)


def generate(font_path: Path, ascii_font_path: Path, output: Path, size: int) -> None:
    font = ImageFont.truetype(str(font_path), size=size)
    ascii_font = ImageFont.truetype(str(ascii_font_path), size=size)
    ascent, descent = font.getmetrics()
    ascii_ascent, ascii_descent = ascii_font.getmetrics()
    # Use the Chinese face's baseline and align Latin glyphs to it. Keep room
    # for either face's descenders without adding blank ascender padding.
    line_height = ascent + max(descent, ascii_descent)
    glyphs = sorted(
        set(chr(code) for code in range(32, 127))
        | set("".join(LABELS.split())) | set(chinese_literals()),
        key=ord,
    )

    padding = 2
    cell = max(size * 2, line_height + padding * 2)
    atlas_width = 512
    columns = atlas_width // cell
    rows = math.ceil(len(glyphs) / columns)
    atlas_height = 2 ** math.ceil(math.log2(max(rows * cell, 1)))
    atlas = Image.new("RGBA", (atlas_width, atlas_height), (255, 255, 255, 0))
    records = bytearray()

    for index, char in enumerate(glyphs):
        face = ascii_font if ord(char) < 128 else font
        face_ascent = ascii_ascent if ord(char) < 128 else ascent
        # FreeType performs monochrome hinting directly at the final size.
        # Do not threshold or shrink antialiased glyphs: their bounds can differ
        # from monochrome bounds, which would cut off thin strokes.
        mask, (left, top) = face.getmask2(char, mode="1")
        width, height = mask.size
        top += ascent - face_ascent
        x = (index % columns) * cell + padding
        y = (index // columns) * cell + padding
        if width + padding * 2 > cell or height + padding * 2 > cell:
            raise ValueError(f"Glyph {char!r} exceeds its atlas cell")
        if width and height:
            alpha = Image.frombytes("L", mask.size, bytes(mask))
            glyph = Image.new("RGBA", mask.size, (255, 255, 255, 255))
            glyph.putalpha(alpha)
            atlas.alpha_composite(glyph, (x, y))
        advance = round(face.getlength(char))
        records.extend(struct.pack(
            "<IHHHHhhhBB", ord(char), x, y, width, height,
            left, top, advance, 0, 15,
        ))

    # BMFont v3: Unicode glyph IDs, one unpacked alpha page, no kerning table.
    info = struct.pack("<hBBHBBBBBBBB", size, 64, 0, 100, 1, 0, 0, 0, 0, 1, 1, 0)
    info += b"GCPractice HUD Raster\0"
    common = struct.pack(
        "<HHHHHBBBBB", line_height, ascent, atlas_width, atlas_height,
        1, 0, 0, 4, 4, 4,
    )
    binary = b"BMF\x03" + block(1, info) + block(2, common)
    binary += block(3, b"gcpractice.png\0") + block(4, bytes(records))

    output.mkdir(parents=True, exist_ok=True)
    (output / "gcpractice.fnt").write_bytes(binary)
    atlas.save(output / "gcpractice.png", optimize=True)
    (Path(__file__).parent / "font-glyphs.txt").write_text(
        "".join(glyphs) + "\n", encoding="utf-8",
    )
    print(f"Generated {len(glyphs)} glyphs; size={size}, lineHeight={line_height}, base={ascent}")
    print(f"Atlas: {atlas_width}x{atlas_height}; CJK source: {font_path}; ASCII source: {ascii_font_path}")
    print(f"Output: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, default=Path("C:/Windows/Fonts/simsun.ttc"))
    parser.add_argument("--ascii-font", type=Path, default=Path("C:/Windows/Fonts/msyh.ttc"))
    parser.add_argument("--size", type=int, default=13)
    parser.add_argument(
        "--output", type=Path,
        default=Path(__file__).resolve().parents[1] / "content" / "resources" / "font",
    )
    args = parser.parse_args()
    generate(args.font, args.ascii_font, args.output, args.size)
