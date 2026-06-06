from __future__ import annotations

from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
CARD_DIR = ROOT / "assets" / "images" / "sanguosha" / "cards" / "standard_108"
GENERAL_DIR = ROOT / "assets" / "images" / "sanguosha" / "generals" / "standard_adult_female"
SCRIPT_DIR = ROOT / "scripts" / "room" / "sanguosha"
CARD_BACK_PATH = ROOT / "assets" / "images" / "sanguosha" / "cards" / "card_back.png"
CARD_SIZE = (300, 420)
GENERAL_SIZE = (512, 720)
FONT_CANDIDATES = [
    Path("C:/Windows/Fonts/msyhbd.ttc"),
    Path("C:/Windows/Fonts/msyh.ttc"),
    Path("C:/Windows/Fonts/simhei.ttf"),
    Path("C:/Windows/Fonts/simsun.ttc"),
]


SUIT_META = {
    "heart": {"label": "红桃", "symbol": "♥", "color": "#b91c1c", "short": "H"},
    "diamond": {"label": "方片", "symbol": "♦", "color": "#dc2626", "short": "D"},
    "spade": {"label": "黑桃", "symbol": "♠", "color": "#111827", "short": "S"},
    "club": {"label": "梅花", "symbol": "♣", "color": "#111827", "short": "C"},
}

TYPE_META = {
    "basic": {"label": "基本", "color": "#f8fafc", "accent": "#b91c1c"},
    "trick": {"label": "锦囊", "color": "#eef2ff", "accent": "#4338ca"},
    "equip": {"label": "装备", "color": "#fef3c7", "accent": "#a16207"},
}

CARD_KEYS = {
    "杀": ("slash", "basic", "basic", "slash"),
    "闪": ("dodge", "basic", "basic", "dodge"),
    "桃": ("peach", "basic", "basic", "peach"),
    "桃园结义": ("peach_garden", "trick", "non_delay_trick", "peach_garden"),
    "万箭齐发": ("arrow_barrage", "trick", "non_delay_trick", "arrow_barrage"),
    "五谷丰登": ("harvest", "trick", "non_delay_trick", "harvest"),
    "乐不思蜀": ("indulgence", "trick", "delay_trick", "indulgence"),
    "无中生有": ("draw_two", "trick", "non_delay_trick", "draw_two"),
    "过河拆桥": ("dismantle", "trick", "non_delay_trick", "dismantle"),
    "闪电": ("lightning", "trick", "delay_trick", "lightning"),
    "决斗": ("duel", "trick", "non_delay_trick", "duel"),
    "顺手牵羊": ("snatch", "trick", "non_delay_trick", "snatch"),
    "南蛮入侵": ("barbarian_assault", "trick", "non_delay_trick", "barbarian_assault"),
    "无懈可击": ("negate", "trick", "non_delay_trick", "negate"),
    "借刀杀人": ("borrow_sword", "trick", "non_delay_trick", "borrow_sword"),
    "麒麟弓": ("qilin_bow", "equip", "weapon", "weapon"),
    "雌雄双股剑": ("double_swords", "equip", "weapon", "weapon"),
    "青龙偃月刀": ("green_dragon_blade", "equip", "weapon", "weapon"),
    "青釭剑": ("blue_steel_blade", "equip", "weapon", "weapon"),
    "丈八蛇矛": ("serpent_spear", "equip", "weapon", "weapon"),
    "诸葛连弩": ("crossbow", "equip", "weapon", "weapon"),
    "贯石斧": ("rock_cleaving_axe", "equip", "weapon", "weapon"),
    "方天画戟": ("halberd", "equip", "weapon", "weapon"),
    "寒冰剑": ("ice_sword", "equip", "weapon", "weapon"),
    "八卦阵": ("eight_diagram", "equip", "armor", "armor"),
    "仁王盾": ("renwang_shield", "equip", "armor", "armor"),
    "赤兔": ("red_hare", "equip", "attack_horse", "attack_horse"),
    "大宛": ("dayuan", "equip", "attack_horse", "attack_horse"),
    "紫骍": ("zixing", "equip", "attack_horse", "attack_horse"),
    "爪黄飞电": ("zhuahuang_feidian", "equip", "defense_horse", "defense_horse"),
    "绝影": ("jueying", "equip", "defense_horse", "defense_horse"),
    "的卢": ("dilu", "equip", "defense_horse", "defense_horse"),
}

WEAPON_RANGE = {
    "qilin_bow": 5,
    "double_swords": 2,
    "green_dragon_blade": 3,
    "blue_steel_blade": 2,
    "serpent_spear": 3,
    "crossbow": 1,
    "rock_cleaving_axe": 3,
    "halberd": 4,
    "ice_sword": 2,
}

DECK_ROWS = [
    ("heart", "A", ["桃园结义", "万箭齐发"]),
    ("heart", "2", ["闪", "闪"]),
    ("heart", "3", ["桃", "五谷丰登"]),
    ("heart", "4", ["桃", "五谷丰登"]),
    ("heart", "5", ["麒麟弓", "赤兔"]),
    ("heart", "6", ["桃", "乐不思蜀"]),
    ("heart", "7", ["桃", "无中生有"]),
    ("heart", "8", ["桃", "无中生有"]),
    ("heart", "9", ["桃", "无中生有"]),
    ("heart", "10", ["杀", "杀"]),
    ("heart", "J", ["杀", "无中生有"]),
    ("heart", "Q", ["桃", "过河拆桥", "闪电"]),
    ("heart", "K", ["闪", "爪黄飞电"]),
    ("spade", "A", ["决斗", "闪电"]),
    ("spade", "2", ["雌雄双股剑", "八卦阵", "寒冰剑"]),
    ("spade", "3", ["过河拆桥", "顺手牵羊"]),
    ("spade", "4", ["过河拆桥", "顺手牵羊"]),
    ("spade", "5", ["青龙偃月刀", "绝影"]),
    ("spade", "6", ["乐不思蜀", "青釭剑"]),
    ("spade", "7", ["杀", "南蛮入侵"]),
    ("spade", "8", ["杀", "杀"]),
    ("spade", "9", ["杀", "杀"]),
    ("spade", "10", ["杀", "杀"]),
    ("spade", "J", ["顺手牵羊", "无懈可击"]),
    ("spade", "Q", ["过河拆桥", "丈八蛇矛"]),
    ("spade", "K", ["南蛮入侵", "大宛"]),
    ("diamond", "A", ["诸葛连弩", "决斗"]),
    ("diamond", "2", ["闪", "闪"]),
    ("diamond", "3", ["闪", "顺手牵羊"]),
    ("diamond", "4", ["闪", "顺手牵羊"]),
    ("diamond", "5", ["闪", "贯石斧"]),
    ("diamond", "6", ["杀", "闪"]),
    ("diamond", "7", ["杀", "闪"]),
    ("diamond", "8", ["杀", "闪"]),
    ("diamond", "9", ["杀", "闪"]),
    ("diamond", "10", ["杀", "闪"]),
    ("diamond", "J", ["闪", "闪"]),
    ("diamond", "Q", ["桃", "方天画戟", "无懈可击"]),
    ("diamond", "K", ["杀", "紫骍"]),
    ("club", "A", ["决斗", "诸葛连弩"]),
    ("club", "2", ["杀", "八卦阵", "仁王盾"]),
    ("club", "3", ["杀", "过河拆桥"]),
    ("club", "4", ["杀", "过河拆桥"]),
    ("club", "5", ["杀", "的卢"]),
    ("club", "6", ["杀", "乐不思蜀"]),
    ("club", "7", ["杀", "南蛮入侵"]),
    ("club", "8", ["杀", "杀"]),
    ("club", "9", ["杀", "杀"]),
    ("club", "10", ["杀", "杀"]),
    ("club", "J", ["杀", "杀"]),
    ("club", "Q", ["借刀杀人", "无懈可击"]),
    ("club", "K", ["借刀杀人", "无懈可击"]),
]

SKILL_DEFINITIONS = {
    "rende": ("仁德", "play", "把手牌交给其他角色；达到规则阈值后可回复体力。"),
    "jijiang": ("激将", "lord", "蜀势力角色可按主公请求代为打出或使用杀。"),
    "wusheng": ("武圣", "conversion", "可将红色牌当杀使用或打出。"),
    "paoxiao": ("咆哮", "locked", "出牌阶段使用杀的次数不受一次限制。"),
    "longdan": ("龙胆", "conversion", "可在杀与闪之间互相转换使用或打出。"),
    "mashu": ("马术", "locked", "计算你到其他角色的距离时减少一。"),
    "tieji": ("铁骑", "slash", "使用杀指定目标后，可进行判定并限制目标响应。"),
    "guanxing": ("观星", "phase_start", "准备阶段可观看牌堆顶牌并调整顺序。"),
    "kongcheng": ("空城", "locked", "没有手牌时，不能成为杀或决斗的目标。"),
    "jizhi": ("集智", "trick", "使用非延时锦囊后可摸牌。"),
    "qicai": ("奇才", "locked", "使用锦囊牌无距离限制。"),
    "jianxiong": ("奸雄", "damage", "受到伤害后可获得造成伤害的牌。"),
    "hujia": ("护驾", "lord", "魏势力角色可按主公请求代为打出闪。"),
    "fankui": ("反馈", "damage", "受到伤害后可获得伤害来源的一张牌。"),
    "guicai": ("鬼才", "judge", "判定牌生效前可打出手牌替换判定结果。"),
    "ganglie": ("刚烈", "damage", "受到伤害后可判定并反制伤害来源。"),
    "tuxi": ("突袭", "draw", "摸牌阶段可少摸牌并获得其他角色手牌。"),
    "luoyi": ("裸衣", "draw", "摸牌阶段可少摸牌，使本回合杀或决斗伤害增加。"),
    "tiandu": ("天妒", "judge", "判定牌生效后可获得此判定牌。"),
    "yiji": ("遗计", "damage", "受到伤害后可摸牌并分配给任意角色。"),
    "qingguo": ("倾国", "conversion", "可将黑色手牌当闪使用或打出。"),
    "luoshen": ("洛神", "phase_start", "准备阶段可连续判定并获得黑色判定牌。"),
    "zhiheng": ("制衡", "play", "出牌阶段限一次，可弃置任意牌并摸等量牌。"),
    "jiuyuan": ("救援", "lord", "吴势力角色对主公使用桃时可增强回复。"),
    "qixi": ("奇袭", "conversion", "可将黑色牌当过河拆桥使用。"),
    "keji": ("克己", "discard", "若本回合未使用或打出杀，可跳过弃牌阶段。"),
    "kurou": ("苦肉", "play", "出牌阶段可失去体力并摸牌。"),
    "yingzi": ("英姿", "draw", "摸牌阶段额外摸牌。"),
    "fanjian": ("反间", "play", "令目标选择花色后获得你一张手牌，若猜错则受伤。"),
    "guose": ("国色", "conversion", "可将方片牌当乐不思蜀使用。"),
    "liuli": ("流离", "slash_target", "成为杀目标时，可弃牌转移此杀目标。"),
    "qianxun": ("谦逊", "locked", "不能成为顺手牵羊和乐不思蜀的目标。"),
    "lianying": ("连营", "hand_empty", "失去最后手牌后可摸牌。"),
    "jieyin": ("结姻", "play", "可弃牌令自己与一名受伤男性角色各回复体力。"),
    "xiaoji": ("枭姬", "equip_lost", "失去装备区牌后可摸牌。"),
    "jijiu": ("急救", "conversion", "回合外可将红色牌当桃使用。"),
    "qingnang": ("青囊", "play", "出牌阶段限一次，可弃一张手牌令一名角色回复体力。"),
    "wushuang": ("无双", "locked", "杀和决斗结算时，目标需要额外响应。"),
    "lijian": ("离间", "play", "可弃牌令两名男性角色视为由一方对另一方使用决斗。"),
    "biyue": ("闭月", "phase_end", "结束阶段可摸牌。"),
}

GENERALS = [
    ("shu_liubei", "刘备", "shu", "male", 4, True, ["rende", "jijiang"], "young_adult"),
    ("shu_guanyu", "关羽", "shu", "male", 4, False, ["wusheng"], "mature_adult"),
    ("shu_zhangfei", "张飞", "shu", "male", 4, False, ["paoxiao"], "young_adult"),
    ("shu_zhaoyun", "赵云", "shu", "male", 4, False, ["longdan"], "young_adult"),
    ("shu_machao", "马超", "shu", "male", 4, False, ["mashu", "tieji"], "young_adult"),
    ("shu_zhugeliang", "诸葛亮", "shu", "male", 3, False, ["guanxing", "kongcheng"], "mature_adult"),
    ("shu_huangyueying", "黄月英", "shu", "female", 3, False, ["jizhi", "qicai"], "young_adult"),
    ("wei_caocao", "曹操", "wei", "male", 4, True, ["jianxiong", "hujia"], "mature_adult"),
    ("wei_simayi", "司马懿", "wei", "male", 3, False, ["fankui", "guicai"], "mature_adult"),
    ("wei_xiahoudun", "夏侯惇", "wei", "male", 4, False, ["ganglie"], "mature_adult"),
    ("wei_zhangliao", "张辽", "wei", "male", 4, False, ["tuxi"], "young_adult"),
    ("wei_xuchu", "许褚", "wei", "male", 4, False, ["luoyi"], "mature_adult"),
    ("wei_guojia", "郭嘉", "wei", "male", 3, False, ["tiandu", "yiji"], "young_adult"),
    ("wei_zhenji", "甄姬", "wei", "female", 3, False, ["qingguo", "luoshen"], "young_adult"),
    ("wu_sunquan", "孙权", "wu", "male", 4, True, ["zhiheng", "jiuyuan"], "young_adult"),
    ("wu_ganning", "甘宁", "wu", "male", 4, False, ["qixi"], "young_adult"),
    ("wu_lvmeng", "吕蒙", "wu", "male", 4, False, ["keji"], "mature_adult"),
    ("wu_huanggai", "黄盖", "wu", "male", 4, False, ["kurou"], "mature_adult"),
    ("wu_zhouyu", "周瑜", "wu", "male", 3, False, ["yingzi", "fanjian"], "young_adult"),
    ("wu_daqiao", "大乔", "wu", "female", 3, False, ["guose", "liuli"], "young_adult"),
    ("wu_luxun", "陆逊", "wu", "male", 3, False, ["qianxun", "lianying"], "young_adult"),
    ("wu_sunshangxiang", "孙尚香", "wu", "female", 3, False, ["jieyin", "xiaoji"], "young_adult"),
    ("qun_huatuo", "华佗", "qun", "male", 3, False, ["jijiu", "qingnang"], "mature_adult"),
    ("qun_lvbu", "吕布", "qun", "male", 4, False, ["wushuang"], "young_adult"),
    ("qun_diaochan", "貂蝉", "qun", "female", 3, False, ["lijian", "biyue"], "young_adult"),
]

KINGDOM_META = {
    "shu": ("蜀", "#166534", "#bbf7d0"),
    "wei": ("魏", "#1d4ed8", "#bfdbfe"),
    "wu": ("吴", "#b91c1c", "#fecaca"),
    "qun": ("群", "#7c3aed", "#ddd6fe"),
}


def card_entries() -> list[dict]:
    result = []
    index = 1
    for suit, rank, names in DECK_ROWS:
        for copy_index, name in enumerate(names, start=1):
            key, card_type, subtype, effect_key = CARD_KEYS[name]
            template_id = f"std_{index:03d}"
            file_name = f"{template_id}_{suit}_{rank.lower()}_{key}.png".replace("*", "x")
            metadata = {}
            if subtype == "weapon":
                metadata["range"] = WEAPON_RANGE.get(key, 1)
            elif subtype == "attack_horse":
                metadata["distance_to_others_delta"] = -1
            elif subtype == "defense_horse":
                metadata["distance_from_others_delta"] = 1
            result.append(
                {
                    "template_id": template_id,
                    "card_key": key,
                    "name": name,
                    "suit": suit,
                    "rank": rank,
                    "copy_index": copy_index,
                    "type": card_type,
                    "subtype": subtype,
                    "effect_key": effect_key,
                    "asset_path": f"res://assets/images/sanguosha/cards/standard_108/{file_name}",
                    "asset_format": "png",
                    "metadata": metadata,
                }
            )
            index += 1
    return result


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def clean_legacy_svg_assets() -> None:
    for directory in [CARD_DIR, GENERAL_DIR]:
        if not directory.exists():
            continue
        for path in directory.glob("*.svg"):
            path.unlink()
    legacy_back = ROOT / "assets" / "images" / "sanguosha" / "cards" / "card_back.svg"
    if legacy_back.exists():
        legacy_back.unlink()


def hex_rgb(value: str) -> tuple[int, int, int]:
    text = value.strip().lstrip("#")
    return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    ordered = FONT_CANDIDATES[:]
    if bold and len(ordered) > 1:
        ordered = [ordered[0], ordered[2], ordered[1], ordered[3]]
    for path in ordered:
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=font)
    return box[2] - box[0], box[3] - box[1]


def fit_font(draw: ImageDraw.ImageDraw, text: str, max_width: int, start_size: int, min_size: int, bold: bool = False) -> ImageFont.ImageFont:
    size = start_size
    while size >= min_size:
        font = load_font(size, bold)
        width, _height = text_size(draw, text, font)
        if width <= max_width:
            return font
        size -= 2
    return load_font(min_size, bold)


def draw_center_text(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], text: str, font: ImageFont.ImageFont, fill: str) -> None:
    width, height = text_size(draw, text, font)
    x = box[0] + ((box[2] - box[0] - width) / 2)
    y = box[1] + ((box[3] - box[1] - height) / 2)
    draw.text((x, y), text, font=font, fill=fill)


def save_card_png(path: Path, card: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    suit = SUIT_META[card["suit"]]
    type_meta = TYPE_META[card["type"]]
    accent = type_meta["accent"]
    image = Image.new("RGB", CARD_SIZE, "#111827")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((5, 5, 295, 415), radius=20, fill="#f8fafc", outline="#111827", width=3)
    draw.rounded_rectangle((14, 14, 286, 406), radius=15, fill=type_meta["color"], outline="#1f2937", width=3)
    draw.rounded_rectangle((27, 27, 273, 377), radius=10, outline=accent, width=2)
    draw.rounded_rectangle((42, 294, 258, 348), radius=20, fill=accent)

    rank_font = load_font(28, True)
    suit_font = load_font(26, True)
    name_font = fit_font(draw, card["name"], 232, 58, 34, True)
    symbol_font = load_font(82, True)
    type_font = load_font(22, True)
    foot_font = load_font(16)

    draw.text((31, 33), str(card["rank"]), font=rank_font, fill=suit["color"])
    draw.text((31, 70), suit["short"], font=suit_font, fill=suit["color"])
    draw_center_text(draw, (42, 83, 258, 151), card["name"], name_font, "#111827")
    draw.ellipse((78, 151, 222, 295), fill="#ffffff", outline=accent, width=4)
    draw_center_text(draw, (78, 156, 222, 284), suit["short"], symbol_font, suit["color"])
    draw_center_text(draw, (42, 296, 258, 346), type_meta["label"], type_font, "#ffffff")
    footer = f"{suit['label']} {card['rank']} · {card['template_id']}"
    draw_center_text(draw, (28, 352, 272, 392), footer, foot_font, "#334155")
    image.save(path, format="PNG")


def save_card_back_png(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", CARD_SIZE, "#111827")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((8, 8, 292, 412), radius=22, fill="#7f1d1d", outline="#fbbf24", width=5)
    draw.rounded_rectangle((31, 31, 269, 389), radius=16, outline="#fde68a", width=2)
    draw.polygon([(58, 101), (102, 62), (150, 50), (202, 62), (242, 101), (196, 86), (104, 86)], fill="#fbbf24")
    draw.polygon([(52, 304), (98, 344), (150, 358), (204, 344), (248, 304), (202, 320), (96, 320)], fill="#fbbf24")
    title_font = load_font(54, True)
    sub_font = load_font(22)
    draw_center_text(draw, (30, 154, 270, 217), "三国杀", title_font, "#fff7ed")
    draw_center_text(draw, (30, 224, 270, 265), "Play With Me", sub_font, "#fde68a")
    image.save(path, format="PNG")


def save_general_png(path: Path, general: tuple, index: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    _general_id, name, kingdom, rules_gender, max_hp, _lord_candidate, skills, archetype = general
    kingdom_label, accent, bg = KINGDOM_META[kingdom]
    skill_names = " / ".join(SKILL_DEFINITIONS[key][0] for key in skills)
    hair = ["#1f2937", "#4b5563", "#7c2d12", "#581c87", "#0f172a"][index % 5]
    dress = ["#be123c", "#7c3aed", "#0f766e", "#b45309", "#1d4ed8"][index % 5]
    stocking = ["#111827", "#1f2937", "#3f3f46", "#27272a", "#0f172a"][index % 5]

    image = Image.new("RGB", GENERAL_SIZE, "#fff7ed")
    draw = ImageDraw.Draw(image)
    bg_rgb = hex_rgb(bg)
    for y in range(GENERAL_SIZE[1]):
        ratio = y / max(1, GENERAL_SIZE[1] - 1)
        r = int(bg_rgb[0] * (1 - ratio) + 255 * ratio)
        g = int(bg_rgb[1] * (1 - ratio) + 247 * ratio)
        b = int(bg_rgb[2] * (1 - ratio) + 237 * ratio)
        draw.line((0, y, GENERAL_SIZE[0], y), fill=(r, g, b))

    draw.rounded_rectangle((18, 18, 494, 702), radius=28, outline=accent, width=5)
    draw.ellipse((178, 86, 334, 246), fill="#f2c7a0", outline="#9a5b3f", width=2)
    draw.pieslice((132, 48, 390, 286), 185, 15, fill=hair)
    draw.polygon([(154, 194), (195, 76), (258, 52), (324, 82), (374, 214), (310, 176), (224, 176)], fill=hair)
    draw.ellipse((207, 150, 226, 166), fill="#111827")
    draw.ellipse((286, 150, 305, 166), fill="#111827")
    draw.arc((226, 172, 286, 210), 10, 170, fill="#7f1d1d", width=3)

    draw.polygon([(126, 536), (154, 366), (212, 286), (256, 304), (300, 286), (358, 366), (386, 536)], fill=dress)
    draw.polygon([(182, 350), (222, 303), (256, 318), (290, 303), (330, 350), (306, 432), (256, 456), (206, 432)], fill="#f8fafc")
    draw.polygon([(64, 530), (140, 376), (198, 334), (207, 518)], fill=dress)
    draw.polygon([(448, 530), (372, 376), (314, 334), (305, 518)], fill=dress)
    draw.polygon([(194, 502), (242, 502), (234, 654), (204, 654)], fill=stocking)
    draw.polygon([(270, 502), (318, 502), (308, 654), (278, 654)], fill=stocking)
    draw.rounded_rectangle((185, 646, 242, 682), radius=10, fill="#09090b")
    draw.rounded_rectangle((270, 646, 327, 682), radius=10, fill="#09090b")

    draw.rounded_rectangle((55, 548, 457, 675), radius=18, fill="#ffffff", outline=accent, width=2)
    name_font = fit_font(draw, name, 342, 46, 30, True)
    skill_font = fit_font(draw, skill_names, 338, 21, 15)
    meta_font = load_font(16)
    art_font = load_font(15)
    draw_center_text(draw, (72, 565, 440, 612), name, name_font, "#111827")
    draw_center_text(draw, (72, 613, 440, 642), f"{kingdom_label} · {max_hp} 体力 · {skill_names}", skill_font, accent)
    visual_label = "21+ 成年真人武将素材位"
    if archetype == "mature_adult":
        visual_label = "21+ 成熟真人武将素材位"
    draw_center_text(draw, (72, 642, 440, 661), visual_label, meta_font, "#475569")
    draw_center_text(draw, (72, 660, 440, 676), f"规则性别 {rules_gender} · PNG", art_font, "#64748b")
    image.save(path, format="PNG")


def gd_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def gd_value(value, indent: int = 0) -> str:
    if isinstance(value, str):
        return gd_string(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        if not value:
            return "[]"
        return "[" + ", ".join(gd_value(item, indent) for item in value) + "]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        inner = []
        for key, item in value.items():
            inner.append(f"{gd_string(str(key))}: {gd_value(item, indent + 1)}")
        return "{" + ", ".join(inner) + "}"
    raise TypeError(f"Unsupported value: {value!r}")


def write_card_catalog(cards: list[dict]) -> None:
    lines = [
        "extends RefCounted",
        "class_name SanguoshaCardCatalog",
        "",
        'const STANDARD_CARD_PACK_ID := "standard_108"',
        'const CARD_BACK := "res://assets/images/sanguosha/cards/card_back.png"',
        "",
        "const STANDARD_108_CARDS := [",
    ]
    for card in cards:
        lines.append("\t%s," % gd_value(card))
    lines.extend(
        [
            "]",
            "",
            "",
            "func cards(pack_id: String = STANDARD_CARD_PACK_ID) -> Array:",
            "\tif pack_id != STANDARD_CARD_PACK_ID:",
            "\t\treturn []",
            "\treturn STANDARD_108_CARDS.duplicate(true)",
            "",
            "",
            "func card_count(pack_id: String = STANDARD_CARD_PACK_ID) -> int:",
            "\treturn cards(pack_id).size()",
            "",
            "",
            "func card_back_path() -> String:",
            "\treturn CARD_BACK",
            "",
            "",
            "func card_asset_path(template_id: String) -> String:",
            "\tfor card_value in STANDARD_108_CARDS:",
            "\t\tvar card: Dictionary = card_value",
            '\t\tif String(card.get("template_id", "")) == template_id:',
            '\t\t\treturn String(card.get("asset_path", ""))',
            "\treturn CARD_BACK",
            "",
            "",
            "func counts_by_type() -> Dictionary:",
            "\tvar result := {}",
            "\tfor card_value in STANDARD_108_CARDS:",
            "\t\tvar card: Dictionary = card_value",
            '\t\tvar card_type := String(card.get("type", ""))',
            "\t\tresult[card_type] = int(result.get(card_type, 0)) + 1",
            "\treturn result",
            "",
            "",
            "func counts_by_card_key() -> Dictionary:",
            "\tvar result := {}",
            "\tfor card_value in STANDARD_108_CARDS:",
            "\t\tvar card: Dictionary = card_value",
            '\t\tvar card_key := String(card.get("card_key", ""))',
            "\t\tresult[card_key] = int(result.get(card_key, 0)) + 1",
            "\treturn result",
            "",
        ]
    )
    write_text(SCRIPT_DIR / "sanguosha_card_catalog.gd", "\n".join(lines))


def write_general_catalog() -> None:
    skills = {
        key: {
            "skill_key": key,
            "name": name,
            "timing": timing,
            "effect_key": key,
            "rules_note": note,
        }
        for key, (name, timing, note) in SKILL_DEFINITIONS.items()
    }
    generals = []
    for general in GENERALS:
        general_id, name, kingdom, rules_gender, max_hp, lord_candidate, skill_keys, archetype = general
        generals.append(
            {
                "general_id": general_id,
                "name": name,
                "kingdom": kingdom,
                "rules_gender": rules_gender,
                "visual_profile": "adult_female",
                "visual_age_group": archetype,
                "visual_age_min": 21,
                "max_hp": max_hp,
                "lord_candidate": lord_candidate,
                "skills": skill_keys,
                "pack_id": "standard_core_adult_female",
                "enabled": True,
                "asset_path": f"res://assets/images/sanguosha/generals/standard_adult_female/{general_id}.png",
                "asset_format": "png",
                "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。",
            }
        )
    lines = [
        "extends RefCounted",
        "class_name SanguoshaGeneralCatalog",
        "",
        'const STANDARD_GENERAL_PACK_ID := "standard_core_adult_female"',
        "",
        "const SKILL_DEFINITIONS := {",
    ]
    for key, value in skills.items():
        lines.append("\t%s: %s," % (gd_string(key), gd_value(value)))
    lines.extend(["}", "", "const STANDARD_GENERALS := ["])
    for general in generals:
        lines.append("\t%s," % gd_value(general))
    lines.extend(
        [
            "]",
            "",
            "",
            "func generals(pack_id: String = STANDARD_GENERAL_PACK_ID) -> Array:",
            "\tif pack_id != STANDARD_GENERAL_PACK_ID:",
            "\t\treturn []",
            "\treturn STANDARD_GENERALS.duplicate(true)",
            "",
            "",
            "func skills() -> Dictionary:",
            "\treturn SKILL_DEFINITIONS.duplicate(true)",
            "",
            "",
            "func general_count(pack_id: String = STANDARD_GENERAL_PACK_ID) -> int:",
            "\treturn generals(pack_id).size()",
            "",
            "",
            "func general_definition(general_id: String) -> Dictionary:",
            "\tfor general_value in STANDARD_GENERALS:",
            "\t\tvar general: Dictionary = general_value",
            '\t\tif String(general.get("general_id", "")) == general_id:',
            "\t\t\treturn general.duplicate(true)",
            "\treturn {}",
            "",
            "",
            "func general_asset_path(general_id: String) -> String:",
            "\tvar general := general_definition(general_id)",
            "\tif general.is_empty():",
            "\t\treturn \"\"",
            '\treturn String(general.get("asset_path", ""))',
            "",
        ]
    )
    write_text(SCRIPT_DIR / "sanguosha_general_catalog.gd", "\n".join(lines))


def write_asset_catalog() -> None:
    text = """extends RefCounted
class_name SanguoshaAssetCatalog

const CardCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_card_catalog.gd")
const GeneralCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_general_catalog.gd")

const CARD_BACK := "res://assets/images/sanguosha/cards/card_back.png"
const TABLE_BACKGROUND := "res://assets/images/werewolf/backgrounds/map_basic.png"


static func card_back_path() -> String:
	return CARD_BACK


static func card_asset_path(template_id: String) -> String:
	return CardCatalogScript.new().card_asset_path(template_id)


static func general_asset_path(general_id: String) -> String:
	return GeneralCatalogScript.new().general_asset_path(general_id)


static func table_background_path() -> String:
	return TABLE_BACKGROUND


static func lobby_background_path() -> String:
	return TABLE_BACKGROUND


static func map_background_path(_map_id: String) -> String:
	return TABLE_BACKGROUND


static func room_background_path(_room: Dictionary) -> String:
	return TABLE_BACKGROUND
"""
    write_text(SCRIPT_DIR / "sanguosha_asset_catalog.gd", text)


def validate(cards: list[dict]) -> None:
    if len(cards) != 108:
        raise RuntimeError(f"Expected 108 cards, got {len(cards)}")
    type_counts = Counter(card["type"] for card in cards)
    expected_types = {"basic": 53, "trick": 36, "equip": 19}
    if dict(type_counts) != expected_types:
        raise RuntimeError(f"Unexpected type counts: {dict(type_counts)}")
    key_counts = Counter(card["card_key"] for card in cards)
    expected_basic = {"slash": 30, "dodge": 15, "peach": 8}
    for key, count in expected_basic.items():
        if key_counts[key] != count:
            raise RuntimeError(f"Expected {count} {key}, got {key_counts[key]}")
    suit_counts = Counter(card["suit"] for card in cards)
    if set(suit_counts.values()) != {27}:
        raise RuntimeError(f"Expected 27 cards per suit, got {dict(suit_counts)}")
    if len(GENERALS) != 25:
        raise RuntimeError(f"Expected 25 generals, got {len(GENERALS)}")


def main() -> None:
    cards = card_entries()
    validate(cards)
    clean_legacy_svg_assets()
    CARD_DIR.mkdir(parents=True, exist_ok=True)
    GENERAL_DIR.mkdir(parents=True, exist_ok=True)
    for card in cards:
        save_card_png(ROOT / card["asset_path"].replace("res://", ""), card)
    save_card_back_png(CARD_BACK_PATH)
    for index, general in enumerate(GENERALS):
        general_id = general[0]
        save_general_png(GENERAL_DIR / f"{general_id}.png", general, index)
    write_card_catalog(cards)
    write_general_catalog()
    write_asset_catalog()
    print("Generated 108 PNG standard cards, 25 adult-female PNG general placeholders, and 3 catalog scripts.")


if __name__ == "__main__":
    main()
