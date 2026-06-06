extends RefCounted
class_name SanguoshaGeneralCatalog

const STANDARD_GENERAL_PACK_ID := "standard_core_adult_female"

const SKILL_DEFINITIONS := {
	"rende": {"skill_key": "rende", "name": "仁德", "timing": "play", "effect_key": "rende", "rules_note": "把手牌交给其他角色；达到规则阈值后可回复体力。"},
	"jijiang": {"skill_key": "jijiang", "name": "激将", "timing": "lord", "effect_key": "jijiang", "rules_note": "蜀势力角色可按主公请求代为打出或使用杀。"},
	"wusheng": {"skill_key": "wusheng", "name": "武圣", "timing": "conversion", "effect_key": "wusheng", "rules_note": "可将红色牌当杀使用或打出。"},
	"paoxiao": {"skill_key": "paoxiao", "name": "咆哮", "timing": "locked", "effect_key": "paoxiao", "rules_note": "出牌阶段使用杀的次数不受一次限制。"},
	"longdan": {"skill_key": "longdan", "name": "龙胆", "timing": "conversion", "effect_key": "longdan", "rules_note": "可在杀与闪之间互相转换使用或打出。"},
	"mashu": {"skill_key": "mashu", "name": "马术", "timing": "locked", "effect_key": "mashu", "rules_note": "计算你到其他角色的距离时减少一。"},
	"tieji": {"skill_key": "tieji", "name": "铁骑", "timing": "slash", "effect_key": "tieji", "rules_note": "使用杀指定目标后，可进行判定并限制目标响应。"},
	"guanxing": {"skill_key": "guanxing", "name": "观星", "timing": "phase_start", "effect_key": "guanxing", "rules_note": "准备阶段可观看牌堆顶牌并调整顺序。"},
	"kongcheng": {"skill_key": "kongcheng", "name": "空城", "timing": "locked", "effect_key": "kongcheng", "rules_note": "没有手牌时，不能成为杀或决斗的目标。"},
	"jizhi": {"skill_key": "jizhi", "name": "集智", "timing": "trick", "effect_key": "jizhi", "rules_note": "使用非延时锦囊后可摸牌。"},
	"qicai": {"skill_key": "qicai", "name": "奇才", "timing": "locked", "effect_key": "qicai", "rules_note": "使用锦囊牌无距离限制。"},
	"jianxiong": {"skill_key": "jianxiong", "name": "奸雄", "timing": "damage", "effect_key": "jianxiong", "rules_note": "受到伤害后可获得造成伤害的牌。"},
	"hujia": {"skill_key": "hujia", "name": "护驾", "timing": "lord", "effect_key": "hujia", "rules_note": "魏势力角色可按主公请求代为打出闪。"},
	"fankui": {"skill_key": "fankui", "name": "反馈", "timing": "damage", "effect_key": "fankui", "rules_note": "受到伤害后可获得伤害来源的一张牌。"},
	"guicai": {"skill_key": "guicai", "name": "鬼才", "timing": "judge", "effect_key": "guicai", "rules_note": "判定牌生效前可打出手牌替换判定结果。"},
	"ganglie": {"skill_key": "ganglie", "name": "刚烈", "timing": "damage", "effect_key": "ganglie", "rules_note": "受到伤害后可判定并反制伤害来源。"},
	"tuxi": {"skill_key": "tuxi", "name": "突袭", "timing": "draw", "effect_key": "tuxi", "rules_note": "摸牌阶段可少摸牌并获得其他角色手牌。"},
	"luoyi": {"skill_key": "luoyi", "name": "裸衣", "timing": "draw", "effect_key": "luoyi", "rules_note": "摸牌阶段可少摸牌，使本回合杀或决斗伤害增加。"},
	"tiandu": {"skill_key": "tiandu", "name": "天妒", "timing": "judge", "effect_key": "tiandu", "rules_note": "判定牌生效后可获得此判定牌。"},
	"yiji": {"skill_key": "yiji", "name": "遗计", "timing": "damage", "effect_key": "yiji", "rules_note": "受到伤害后可摸牌并分配给任意角色。"},
	"qingguo": {"skill_key": "qingguo", "name": "倾国", "timing": "conversion", "effect_key": "qingguo", "rules_note": "可将黑色手牌当闪使用或打出。"},
	"luoshen": {"skill_key": "luoshen", "name": "洛神", "timing": "phase_start", "effect_key": "luoshen", "rules_note": "准备阶段可连续判定并获得黑色判定牌。"},
	"zhiheng": {"skill_key": "zhiheng", "name": "制衡", "timing": "play", "effect_key": "zhiheng", "rules_note": "出牌阶段限一次，可弃置任意牌并摸等量牌。"},
	"jiuyuan": {"skill_key": "jiuyuan", "name": "救援", "timing": "lord", "effect_key": "jiuyuan", "rules_note": "吴势力角色对主公使用桃时可增强回复。"},
	"qixi": {"skill_key": "qixi", "name": "奇袭", "timing": "conversion", "effect_key": "qixi", "rules_note": "可将黑色牌当过河拆桥使用。"},
	"keji": {"skill_key": "keji", "name": "克己", "timing": "discard", "effect_key": "keji", "rules_note": "若本回合未使用或打出杀，可跳过弃牌阶段。"},
	"kurou": {"skill_key": "kurou", "name": "苦肉", "timing": "play", "effect_key": "kurou", "rules_note": "出牌阶段可失去体力并摸牌。"},
	"yingzi": {"skill_key": "yingzi", "name": "英姿", "timing": "draw", "effect_key": "yingzi", "rules_note": "摸牌阶段额外摸牌。"},
	"fanjian": {"skill_key": "fanjian", "name": "反间", "timing": "play", "effect_key": "fanjian", "rules_note": "令目标选择花色后获得你一张手牌，若猜错则受伤。"},
	"guose": {"skill_key": "guose", "name": "国色", "timing": "conversion", "effect_key": "guose", "rules_note": "可将方片牌当乐不思蜀使用。"},
	"liuli": {"skill_key": "liuli", "name": "流离", "timing": "slash_target", "effect_key": "liuli", "rules_note": "成为杀目标时，可弃牌转移此杀目标。"},
	"qianxun": {"skill_key": "qianxun", "name": "谦逊", "timing": "locked", "effect_key": "qianxun", "rules_note": "不能成为顺手牵羊和乐不思蜀的目标。"},
	"lianying": {"skill_key": "lianying", "name": "连营", "timing": "hand_empty", "effect_key": "lianying", "rules_note": "失去最后手牌后可摸牌。"},
	"jieyin": {"skill_key": "jieyin", "name": "结姻", "timing": "play", "effect_key": "jieyin", "rules_note": "可弃牌令自己与一名受伤男性角色各回复体力。"},
	"xiaoji": {"skill_key": "xiaoji", "name": "枭姬", "timing": "equip_lost", "effect_key": "xiaoji", "rules_note": "失去装备区牌后可摸牌。"},
	"jijiu": {"skill_key": "jijiu", "name": "急救", "timing": "conversion", "effect_key": "jijiu", "rules_note": "回合外可将红色牌当桃使用。"},
	"qingnang": {"skill_key": "qingnang", "name": "青囊", "timing": "play", "effect_key": "qingnang", "rules_note": "出牌阶段限一次，可弃一张手牌令一名角色回复体力。"},
	"wushuang": {"skill_key": "wushuang", "name": "无双", "timing": "locked", "effect_key": "wushuang", "rules_note": "杀和决斗结算时，目标需要额外响应。"},
	"lijian": {"skill_key": "lijian", "name": "离间", "timing": "play", "effect_key": "lijian", "rules_note": "可弃牌令两名男性角色视为由一方对另一方使用决斗。"},
	"biyue": {"skill_key": "biyue", "name": "闭月", "timing": "phase_end", "effect_key": "biyue", "rules_note": "结束阶段可摸牌。"},
}

const STANDARD_GENERALS := [
	{"general_id": "shu_liubei", "name": "刘备", "kingdom": "shu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": true, "skills": ["rende", "jijiang"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/shu_liubei.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "shu_guanyu", "name": "关羽", "kingdom": "shu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "mature_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["wusheng"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/shu_guanyu.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "shu_zhangfei", "name": "张飞", "kingdom": "shu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["paoxiao"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/shu_zhangfei.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "shu_zhaoyun", "name": "赵云", "kingdom": "shu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["longdan"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/shu_zhaoyun.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "shu_machao", "name": "马超", "kingdom": "shu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["mashu", "tieji"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/shu_machao.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "shu_zhugeliang", "name": "诸葛亮", "kingdom": "shu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "mature_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["guanxing", "kongcheng"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/shu_zhugeliang.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "shu_huangyueying", "name": "黄月英", "kingdom": "shu", "rules_gender": "female", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["jizhi", "qicai"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/shu_huangyueying.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wei_caocao", "name": "曹操", "kingdom": "wei", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "mature_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": true, "skills": ["jianxiong", "hujia"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wei_caocao.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wei_simayi", "name": "司马懿", "kingdom": "wei", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "mature_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["fankui", "guicai"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wei_simayi.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wei_xiahoudun", "name": "夏侯惇", "kingdom": "wei", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "mature_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["ganglie"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wei_xiahoudun.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wei_zhangliao", "name": "张辽", "kingdom": "wei", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["tuxi"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wei_zhangliao.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wei_xuchu", "name": "许褚", "kingdom": "wei", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "mature_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["luoyi"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wei_xuchu.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wei_guojia", "name": "郭嘉", "kingdom": "wei", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["tiandu", "yiji"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wei_guojia.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wei_zhenji", "name": "甄姬", "kingdom": "wei", "rules_gender": "female", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["qingguo", "luoshen"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wei_zhenji.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wu_sunquan", "name": "孙权", "kingdom": "wu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": true, "skills": ["zhiheng", "jiuyuan"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wu_sunquan.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wu_ganning", "name": "甘宁", "kingdom": "wu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["qixi"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wu_ganning.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wu_lvmeng", "name": "吕蒙", "kingdom": "wu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "mature_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["keji"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wu_lvmeng.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wu_huanggai", "name": "黄盖", "kingdom": "wu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "mature_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["kurou"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wu_huanggai.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wu_zhouyu", "name": "周瑜", "kingdom": "wu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["yingzi", "fanjian"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wu_zhouyu.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wu_daqiao", "name": "大乔", "kingdom": "wu", "rules_gender": "female", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["guose", "liuli"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wu_daqiao.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wu_luxun", "name": "陆逊", "kingdom": "wu", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["qianxun", "lianying"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wu_luxun.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "wu_sunshangxiang", "name": "孙尚香", "kingdom": "wu", "rules_gender": "female", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["jieyin", "xiaoji"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/wu_sunshangxiang.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "qun_huatuo", "name": "华佗", "kingdom": "qun", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "mature_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["jijiu", "qingnang"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/qun_huatuo.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "qun_lvbu", "name": "吕布", "kingdom": "qun", "rules_gender": "male", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 4, "lord_candidate": false, "skills": ["wushuang"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/qun_lvbu.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
	{"general_id": "qun_diaochan", "name": "貂蝉", "kingdom": "qun", "rules_gender": "female", "visual_profile": "adult_female", "visual_age_group": "young_adult", "visual_age_min": 21, "max_hp": 3, "lord_candidate": false, "skills": ["lijian", "biyue"], "pack_id": "standard_core_adult_female", "enabled": true, "asset_path": "res://assets/images/sanguosha/generals/standard_adult_female/qun_diaochan.png", "asset_format": "png", "art_direction": "21+ 成年真人女性武将，性感古风战姬写真风格，可包含丝袜、束腰、盔甲和华丽服饰；避免未成年人、校服、裸露和露骨姿势。"},
]


func generals(pack_id: String = STANDARD_GENERAL_PACK_ID) -> Array:
	if pack_id != STANDARD_GENERAL_PACK_ID:
		return []
	return STANDARD_GENERALS.duplicate(true)


func skills() -> Dictionary:
	return SKILL_DEFINITIONS.duplicate(true)


func general_count(pack_id: String = STANDARD_GENERAL_PACK_ID) -> int:
	return generals(pack_id).size()


func general_definition(general_id: String) -> Dictionary:
	for general_value in STANDARD_GENERALS:
		var general: Dictionary = general_value
		if String(general.get("general_id", "")) == general_id:
			return general.duplicate(true)
	return {}


func general_asset_path(general_id: String) -> String:
	var general := general_definition(general_id)
	if general.is_empty():
		return ""
	return String(general.get("asset_path", ""))
