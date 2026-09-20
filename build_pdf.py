#!/usr/bin/env python3
# 生成中文 PDF（fpdf2 + 系统黑体 simhei.ttf）
from fpdf import FPDF

FONT = r"C:\Windows\Fonts\simhei.ttf"

class PDF(FPDF):
    def header(self):
        if self.page_no() == 1:
            return
        self.set_font("CN", "", 9)
        self.set_text_color(120)
        self.cell(0, 8, "ShowLocation 分步计划", align="R")
        self.ln(10)
    def footer(self):
        self.set_y(-15)
        self.set_font("CN", "", 9)
        self.set_text_color(120)
        self.cell(0, 10, f"第 {self.page_no()} 页", align="C")

pdf = PDF(orientation="P", unit="mm", format="A4")
pdf.add_font("CN", "", FONT)
pdf.add_font("CN", "B", FONT)  # 黑体无独立粗体，复用同字体
pdf.set_auto_page_break(auto=True, margin=18)
pdf.set_margins(18, 18, 18)
EPW = pdf.epw  # effective page width

def read(path):
    return open(path, encoding="utf-8").read()

def mc(w, h, txt, **kw):
    """multi_cell that resets x to left margin when using full width."""
    if w == 0:
        pdf.set_x(pdf.l_margin)
    pdf.multi_cell(w, h, txt, **kw)

def clean(s):
    # remove markdown markers lightly
    s = s.replace("**", "")
    # replace glyphs missing in SimHei used by our docs
    s = s.replace("\u2022", "-").replace("\u2705", "[x]").replace("\u2b1c", "[ ]")
    s = s.replace("\u25c4", "->").replace("\u25b6", "->").replace("\u00a5", "Y")
    return s

import re

def add_md(md_text):
    lines = md_text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s == "":
            pdf.ln(2); i += 1; continue
        if s.startswith("```"):
            # code block
            buf = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                buf.append(lines[i]); i += 1
            i += 1
            pdf.set_font("CN", "", 9)
            pdf.set_fill_color(245, 245, 245)
            for cl in buf:
                mc(0, 5, clean(cl), fill=True)
            pdf.ln(2); continue
        if s.startswith("##### "):
            pdf.set_font("CN", "B", 12); mc(0, 7, clean(s[6:])); pdf.ln(1); i += 1; continue
        if s.startswith("#### "):
            pdf.set_font("CN", "B", 12); mc(0, 7, clean(s[5:])); pdf.ln(1); i += 1; continue
        if s.startswith("### "):
            pdf.set_font("CN", "B", 13); mc(0, 7, clean(s[4:])); pdf.ln(1); i += 1; continue
        if s.startswith("## "):
            pdf.set_font("CN", "B", 15); mc(0, 8, clean(s[3:])); pdf.ln(2); i += 1; continue
        if s.startswith("# "):
            pdf.set_font("CN", "B", 18); mc(0, 10, clean(s[2:])); pdf.ln(2); i += 1; continue
        # table
        if "|" in s and i + 1 < len(lines) and re.match(r'^\s*\|?[\s:\-\|]+\|?\s*$', lines[i+1]):
            rows = []
            j = i
            while j < len(lines) and "|" in lines[j]:
                rows.append([c.strip() for c in lines[j].strip().strip("|").split("|")])
                j += 1
            headers = rows[0]
            data = rows[2:] if len(rows) > 2 else []
            n = len(headers)
            avail = EPW
            col_w = avail / n
            # header
            pdf.set_font("CN", "B", 9)
            pdf.set_fill_color(213, 232, 240)
            for h in headers:
                pdf.cell(col_w, 7, clean(h), border=1, align="C", fill=True)
            pdf.ln()
            pdf.set_font("CN", "", 9)
            for row in data:
                # compute height via multi_cell measurement -> simple: use single line, truncate
                # estimate lines for wrapping
                max_lines = 1
                for ci, c in enumerate(row):
                    txt = clean(c)
                    # approx chars per line
                    cpl = int(col_w / (9 * 0.35)) if col_w else 20
                    lines_n = max(1, (len(txt) // cpl) + 1)
                    max_lines = max(max_lines, lines_n)
                h = 6 * max_lines
                x0 = pdf.get_x(); y0 = pdf.get_y()
                for ci, c in enumerate(row):
                    x = pdf.get_x(); y = pdf.get_y()
                    pdf.rect(x, y, col_w, h)
                    pdf.set_xy(x, y + 1)
                    pdf.multi_cell(col_w, 6, clean(c), border=0)
                    pdf.set_xy(x + col_w, y)
                pdf.set_xy(x0, y0 + h)
            pdf.ln(2)
            i = j; continue
        if re.match(r'^\s*[-*]\s+', s):
            txt = re.sub(r'^\s*[-*]\s+', '', s)
            pdf.set_font("CN", "", 10)
            x = pdf.get_x()
            pdf.cell(6, 5, "-")
            pdf.multi_cell(EPW - 6, 5, clean(txt))
            i += 1; continue
        if re.match(r'^\s*\d+\.\s+', s):
            txt = re.sub(r'^\s*\d+\.\s+', '', s)
            pdf.set_font("CN", "", 10); mc(0, 5, clean(txt)); i += 1; continue
        # plain
        pdf.set_font("CN", "", 10)
        mc(0, 5.5, clean(s))
        pdf.ln(0.5)
        i += 1

# Cover
pdf.add_page()
pdf.set_font("CN", "B", 26)
pdf.ln(40)
mc(0, 14, "ShowLocation 分步计划", align="C")
pdf.set_font("CN", "", 14)
pdf.ln(6)
mc(0, 9, "需求澄清 · 架构设计 · 模块拆分 · 机型清单 · 发布概览", align="C")
pdf.ln(4)
mc(0, 8, "版本 v1.0 ｜ 2026-08-10 ｜ 首期 Android 优先", align="C")

pdf.add_page()
pdf.set_font("CN", "B", 16)
mc(0, 9, "目录")
pdf.set_font("CN", "", 12)
pdf.ln(2)
for t in ["一、需求澄清（requirements.md）", "二、架构设计（architecture.md）",
          "三、主流机型与系统版本（supported_devices.md）",
          "四、全周期阶段与发布概览（RELEASE_GUIDE.md）"]:
    mc(0, 8, t)
pdf.ln(4)

pdf.add_page()
pdf.set_font("CN", "B", 16)
mc(0, 9, "一、需求澄清（requirements.md）")
add_md(read("docs/requirements.md"))

pdf.add_page()
pdf.set_font("CN", "B", 16)
mc(0, 9, "二、架构设计（architecture.md）")
add_md(read("docs/architecture.md"))

pdf.add_page()
pdf.set_font("CN", "B", 16)
mc(0, 9, "三、主流机型与系统版本（supported_devices.md）")
add_md(read("supported_devices.md"))

pdf.add_page()
pdf.set_font("CN", "B", 16)
mc(0, 9, "四、全周期阶段与发布概览（RELEASE_GUIDE.md）")
add_md(read("RELEASE_GUIDE.md"))

pdf.output("ShowLocation_计划书.pdf")
print("written ShowLocation_计划书.pdf")
