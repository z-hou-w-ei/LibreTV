# Rewrite group-title of CNTV-V4 playlist into 6 specific groups (no 频道 suffix)
# 央视 / 卫视 / 地方 / 电影 / 剧集 / 专题
import re

SRC = r"C:\Hack APP\LibreTV\public\cntv-v4.m3u"
lines = open(SRC, encoding="utf-8", errors="replace").read().splitlines()

local_kw = ["综合","新闻","少儿","教育","生活","购物","经济","影视","公共","民生",
            "文艺","都市","法治","体育","农业","旅游","交通","音乐","文化","乡村",
            "频道","一套","二套","三套","四套","4K","高清","导视","经典",
            "电视台","科教","教科","娱乐","资讯","农村","农民","国际","经视","财经",
            "文体","竞赛","休闲","数码","留学","影院","移民","党建","哈萨克","维吾尔",
            "朝语","遂昌","上虞","余杭","万州","奎屯","句容","普陀","青田","营山",
            "通海","长白山","晋江","亳州","伊犁","延边","梨园","公园","钱江"]

def classify(name: str, old_group: str) -> str:
    n = name.strip()
    if n.startswith("CCTV") or n.startswith("CGTN"):
        return "央视"
    if "卫视" in n:
        return "卫视"
    if old_group in ("电影", "电影频道"):
        return "电影" if "电影" in n else "剧集"
    if old_group == "剧集频道":
        return "剧集"
    if any(k in n for k in local_kw):
        return "地方"
    return "专题"

out = []
counts = {}
for line in lines:
    if line.startswith("#EXTGRP:"):
        continue  # remove our previous EXTGRP lines (group-title is authoritative)
    if line.startswith("#EXTINF"):
        m = re.match(r"^(#EXTINF[^,]*,)(.*)$", line)
        if m:
            head, title = m.group(1), m.group(2)
            orig = re.search(r'group-title="([^"]*)"', line)
            orig_g = orig.group(1) if orig else ""
            grp = classify(title, orig_g)
            counts[grp] = counts.get(grp, 0) + 1
            # replace or insert group-title attr right after #EXTINF header attrs
            if orig:
                line = line.replace(f'group-title="{orig_g}"', f'group-title="{grp}"')
            else:
                comma = line.find(",")
                line = line[:comma] + f' group-title="{grp}"' + line[comma:]
    out.append(line)

open(SRC, "w", encoding="utf-8", newline="\n").write("\n".join(out))
print("group distribution:", counts)
print("total:", sum(counts.values()))
