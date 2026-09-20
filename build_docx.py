#!/usr/bin/env python3
# 纯标准库生成 .docx（不依赖 python-docx / pandoc / npm）
import os, zipfile, re
from xml.sax.saxutils import escape

# ---------- markdown -> docx paragraphs ----------
def esc(t): return escape(t)

body = []  # list of xml strings (w:p / w:tbl)

def para(text="", style=None, bold=False, size=None, align=None, runs=None):
    ppr = ""
    if style: ppr += f'<w:pStyle w:val="{style}"/>'
    if align: ppr += f'<w:jc w:val="{align}"/>'
    ppr = f'<w:pPr>{ppr}</w:pPr>' if ppr else ""
    if runs is None:
        rpr = ""
        if bold: rpr += "<w:b/>"
        if size: rpr += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
        rpr = f'<w:rPr>{rpr}</w:rPr>' if rpr else ""
        run = f'<w:r>{rpr}<w:t xml:space="preserve">{esc(text)}</w:t></w:r>' if text != "" else ""
        return f"<w:p>{ppr}{run}</w:p>"
    rxml = ""
    for (rt, rb, rs) in runs:
        rpr = ""
        if rb: rpr += "<w:b/>"
        if rs: rpr += f'<w:sz w:val="{rs}"/><w:szCs w:val="{rs}"/>'
        rpr = f'<w:rPr>{rpr}</w:rPr>' if rpr else ""
        rxml += f'<w:r>{rpr}<w:t xml:space="preserve">{esc(rt)}</w:t></w:r>'
    return f"<w:p>{ppr}{rxml}</w:p>"

def heading(text, level):
    sizes = {1: 32, 2: 26, 3: 22}
    return para(text, bold=True, size=sizes.get(level, 22))

def code_block(text):
    out = []
    for line in text.split("\n"):
        out.append(para(line, size=18))
    return "".join(out)

def parse_md(md_text):
    lines = md_text.split("\n")
    res = []
    i = 0
    in_code = False
    code_buf = []
    def flush():
        nonlocal code_buf
        if code_buf:
            res.append(code_block("\n".join(code_buf)))
            code_buf = []
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            if in_code: flush(); in_code = False
            else: in_code = True
            i += 1; continue
        if in_code:
            code_buf.append(line); i += 1; continue
        s = line.strip()
        if s == "":
            res.append("<w:p/>"); i += 1; continue
        if s.startswith("##### "):
            res.append(heading(s[6:], 3)); i += 1; continue
        if s.startswith("#### "):
            res.append(heading(s[5:], 3)); i += 1; continue
        if s.startswith("### "):
            res.append(heading(s[4:], 3)); i += 1; continue
        if s.startswith("## "):
            res.append(heading(s[3:], 2)); i += 1; continue
        if s.startswith("# "):
            res.append(heading(s[2:], 1)); i += 1; continue
        # table detection: current line has | and next line is separator
        if "|" in s and i + 1 < len(lines) and re.match(r'^\s*\|?[\s:\-\|]+\|?\s*$', lines[i+1]):
            # collect table rows
            rows = []
            j = i
            while j < len(lines) and "|" in lines[j]:
                cells = [c.strip() for c in lines[j].strip().strip("|").split("|")]
                rows.append(cells)
                j += 1
            # skip separator row (index 1)
            headers = rows[0]
            data = rows[2:] if len(rows) > 2 else []
            res.append(make_table(headers, data))
            i = j; continue
        # bullet
        if re.match(r'^\s*[-*]\s+', s):
            txt = re.sub(r'^\s*[-*]\s+', '', s)
            res.append(para(txt, runs=[("\u2022 ", False, None), (txt, False, None)]))
            i += 1; continue
        # numbered like "1. "
        if re.match(r'^\s*\d+\.\s+', s):
            txt = re.sub(r'^\s*\d+\.\s+', '', s)
            res.append(para(txt))
            i += 1; continue
        # plain paragraph with **bold** handling
        res.append(md_inline(s))
        i += 1
    flush()
    return "".join(res)

def md_inline(s):
    # handle **bold**
    parts = re.split(r'(\*\*.+?\*\*)', s)
    runs = []
    for part in parts:
        if part.startswith("**") and part.endswith("**"):
            runs.append((part[2:-2], True, None))
        else:
            if part: runs.append((part, False, None))
    return para(runs=runs) if runs else "<w:p/>"

def make_table(headers, data):
    n = len(headers)
    widths = [int(9026 / n)] * n
    def cell(text, fill=None):
        shd = f'<w:shd w:val="clear" w:color="auto" w:fill="{fill}"/>' if fill else ""
        tcpr = f'<w:tcPr><w:tcW w:w="{widths[0]}" w:type="dxa"/>{shd}</w:tcPr>'
        return f'<w:tc>{tcpr}<w:p><w:r><w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p></w:tc>'
    # rebuild with per-column widths
    def cellw(text, idx, fill=None):
        shd = f'<w:shd w:val="clear" w:color="auto" w:fill="{fill}"/>' if fill else ""
        tcpr = f'<w:tcPr><w:tcW w:w="{widths[idx]}" w:type="dxa"/>{shd}</w:tcPr>'
        return f'<w:tc>{tcpr}<w:p><w:r><w:t xml:space="preserve">{esc(text)}</w:t></w:r></w:p></w:tc>'
    grid = "".join(f'<w:gridCol w:w="{w}"/>' for w in widths)
    head = "".join(cellw(h, i, "D5E8F0") for i, h in enumerate(headers))
    body_rows = "".join("<w:tr>" + "".join(cellw(c, i) for i, c in enumerate(row)) + "</w:tr>" for row in data)
    tbl = (f'<w:tbl><w:tblPr><w:tblW w:w="9026" w:type="dxa"/>'
           f'<w:tblBorders>'
           f'<w:top w:val="single" w:sz="4" w:color="CCCCCC"/>'
           f'<w:left w:val="single" w:sz="4" w:color="CCCCCC"/>'
           f'<w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/>'
           f'<w:right w:val="single" w:sz="4" w:color="CCCCCC"/>'
           f'<w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>'
           f'<w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>'
           f'</w:tblBorders></w:tblPr>'
           f'<w:tblGrid>{grid}</w:tblGrid>'
           f'<w:tr>{head}</w:tr>{body_rows}</w:tbl>')
    return tbl

# ---------- assemble ----------
def read(path): return open(path, encoding="utf-8").read()

content = []
content.append(para("ShowLocation 分步计划", bold=True, size=48, align="center"))
content.append(para("需求澄清 · 架构设计 · 模块拆分 · 机型清单 · 发布概览", size=24, align="center"))
content.append(para("版本 v1.0 ｜ 2026-08-10 ｜ 首期 Android 优先", size=20, align="center"))
content.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')

content.append(heading("一、需求澄清（requirements.md）", 1))
content.append(parse_md(read("docs/requirements.md")))
content.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')

content.append(heading("二、架构设计（architecture.md）", 1))
content.append(parse_md(read("docs/architecture.md")))
content.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')

content.append(heading("三、主流机型与系统版本（supported_devices.md）", 1))
content.append(parse_md(read("supported_devices.md")))
content.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')

content.append(heading("四、全周期阶段与发布概览（RELEASE_GUIDE.md）", 1))
content.append(parse_md(read("RELEASE_GUIDE.md")))

document_xml = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:body>' + "".join(content) +
    '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
    'w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    '</w:body></w:document>'
)

# ---------- package ----------
content_types = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '</Types>'
)
rels = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>'
)

out = "ShowLocation_计划书.docx"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", content_types)
    z.writestr("_rels/.rels", rels)
    z.writestr("word/document.xml", document_xml)
print("written", out, os.path.getsize(out), "bytes")
