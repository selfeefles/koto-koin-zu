using CSV
using DataFrames

const SCRIPT_DIR = @__DIR__

const CONFIG = (
    nodes_path = joinpath(SCRIPT_DIR, "nodes_v4_2_8.csv"),
    edges_path = joinpath(SCRIPT_DIR, "edges_v4_2_8.csv"),

    # 完全図。v3系の full_subgraph を v4.2.8 で正式な full に昇格。
    output_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_full.md"),
    full_html_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_full.html"),
    # GitHub Pagesへそのまま置ける公開用ファイル名。
    pages_full_html_path = joinpath(SCRIPT_DIR, "full.html"),
    mermaid_max_edges = 1000,
    mermaid_max_text_size = 500000,

    overview_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_overview.md"),
    former_houses_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_former_houses.md"),
    kuni_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_kuni.md"),
    higashikuni_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_higashikuni.md"),
    kitashirakawa_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_kitashirakawa.md"),
    takeda_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_takeda.md"),
    kaya_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_kaya.md"),
    asaka_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_asaka.md"),
    yamashina_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_yamashina.md"),
    nashimoto_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_nashimoto.md"),
    kanin_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_kanin.md"),
    higashifushimi_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_higashifushimi.md"),
    fushimi_path = joinpath(SCRIPT_DIR, "imperial_genealogy_v4_2_8_fushimi.md"),

    report_path = joinpath(SCRIPT_DIR, "validation_report_v4_2_8.txt"),
    direction = "TB",
    root_id = "t001",
    current_emperor_id = "t126",
)

cell_string(x)::String = ismissing(x) ? "" : String(strip(string(x)))

function safe_load_csv(path)
    isfile(path) || error("CSVファイルが見つかりません: $(abspath(path))")
    lines = String[]
    open(path, "r") do io
        for line in eachline(io)
            s = strip(line)
            isempty(s) && continue
            startswith(s, "#") && continue
            push!(lines, line)
        end
    end
    CSV.read(IOBuffer(join(lines, "\n")), DataFrame; normalizenames=false)
end

function require_columns(df, cols, filename)
    present = Set(string.(names(df)))
    missing_cols = [c for c in cols if !(c in present)]
    isempty(missing_cols) || error("$(filename) に必要な列がありません: $(join(missing_cols, ", "))")
end

function escape_html(s::AbstractString)
    t = replace(String(s), "&"=>"&amp;")
    t = replace(t, "<"=>"&lt;")
    t = replace(t, ">"=>"&gt;")
    replace(t, "\""=>"&quot;")
end


# 日本語人名の空白方針:
# - 人名内部（姓・氏・家名・宮号・幼称等を含む）には半角空白を入れない。
# - 独立した身位・称号 + 個人名の境界のみ半角空白を許容する。
# - 天皇 name の「代数 + 天皇名」の空白は別用途なので許容する。
const NAME_SPACE_TITLE_SUFFIXES = (
    "上皇后",
    "皇后",
    "皇太子",
    "皇太子妃",
    "皇嗣",
    "皇嗣妃",
    "親王妃",
    "王妃",
    "宮妃",
)

function suspicious_japanese_name_space(s::String)
    isempty(s) && return false

    chars = collect(s)
    for i in eachindex(chars)
        chars[i] == ' ' || continue
        i == firstindex(chars) && continue
        i == lastindex(chars) && continue

        left_char = chars[i - 1]
        right_char = chars[i + 1]
        japanese_char(c) = occursin(r"[一-龯々〆ヵヶぁ-んァ-ヶー]", string(c))
        (japanese_char(left_char) && japanese_char(right_char)) || continue

        left_text = String(chars[firstindex(chars):(i - 1)])
        any(endswith(left_text, suffix) for suffix in NAME_SPACE_TITLE_SUFFIXES) && continue

        return true
    end
    return false
end


const DISALLOWED_ANNOTATION_REGISTER_PATTERNS = [
    r"\bof\b",
    r"主軸",
    r"次世代",
    r"収録対象",
    r"収録方針",
    r"TODO",
    r"要確認",
    r"暫定",
]

function suspicious_annotation_register(s::String)
    isempty(s) && return false
    return any(occursin(pattern, s) for pattern in DISALLOWED_ANNOTATION_REGISTER_PATTERNS)
end


function redundant_life_year_annotation(text::String, birth_year::String, death_year::String)
    isempty(text) && return false

    if !isempty(birth_year)
        occursin("$(birth_year)年誕生", text) && return true
        occursin("$(birth_year)年生", text) && return true
    end

    if !isempty(death_year)
        for suffix in ("年薨去", "年崩御", "年死去", "年没")
            occursin("$(death_year)$(suffix)", text) && return true
        end
    end

    if !isempty(birth_year) && !isempty(death_year)
        for sep in ("–", "-", "〜", "～")
            occursin("$(birth_year)$(sep)$(death_year)", text) && return true
        end
    end

    return false
end


function emperor_node_id(id::String)
    occursin(r"^t\d{3}(?:t\d+)?$", id) || occursin(r"^tn\d{3}$", id)
end

function alias_component_count(alias::String)
    isempty(alias) && return 0
    return length(split(alias, '・'))
end


const DEPRECATED_EMPEROR_ALIAS_FORMS = Dict(
    "t013" => "若足彦尊",
    "t021" => "大泊瀬幼児尊",
    "t030" => "訳語田渟中倉太玉敷尊",
    "t092" => "熈仁親王",
)

const REQUIRED_NON_EMPEROR_ALIASES = Dict(
    "p_shikitsuhiko" => "師木津日子命",
    "p_wakasako" => "若沼毛二俣王・若野毛二俣王",
    "p_ichinobe" => "市辺之忍歯王",
    "p_tashiraka" => "手白髪郎女",
    "p_oshisaka" => "忍坂日子人太子・麻呂古王",
    "p_okisomimi" => "常津彦命",
    "n_hahatsuhime" => "意祁都比売命",
    "p_ohoji" => "大郎子",
    "p_hikoushino" => "汗斯王",
    "p_chinu" => "知奴王",
)

const REQUIRED_1947_NAME_ALIAS_FORMS = Dict(
    "fushimi_025" => ("伏見博明", "伏見宮博明王"),
    "kuni_004" => ("久邇朝融", "久邇宮朝融王"),
    "kuni_005" => ("久邇邦昭", "邦昭王"),
    "kuni_007" => ("久邇朝建", "朝建王"),
    "kuni_010" => ("久邇朝宏", "朝宏王"),
    "higashikuni_001" => ("東久邇稔彦", "東久邇宮稔彦王"),
    "higashikuni_002" => ("東久邇盛厚", "盛厚王"),
    "higashikuni_003" => ("東久邇信彦", "信彦王"),
    "higashikuni_014" => ("多羅間俊彦", "俊彦王"),
    "kitashirakawa_004" => ("北白川道久", "北白川宮道久王"),
    "takeda_002" => ("竹田恒徳", "竹田宮恒徳王"),
    "takeda_003" => ("竹田恒正", "恒正王"),
    "takeda_004" => ("竹田恒治", "恒治王"),
    "kaya_002" => ("賀陽恒憲", "賀陽宮恒憲王"),
    "kaya_003" => ("賀陽邦寿", "邦寿王"),
    "kaya_004" => ("賀陽治憲", "治憲王"),
    "kaya_005" => ("賀陽章憲", "章憲王"),
    "kaya_006" => ("賀陽文憲", "文憲王"),
    "kaya_007" => ("賀陽宗憲", "宗憲王"),
    "kaya_008" => ("賀陽健憲", "健憲王"),
    "asaka_001" => ("朝香鳩彦", "朝香宮鳩彦王"),
    "asaka_002" => ("朝香孚彦", "孚彦王"),
    "asaka_003" => ("朝香誠彦", "誠彦王"),
    "yamashina_003" => ("山階武彦", "山階宮武彦王"),
    "nashimoto_002" => ("梨本守正", "梨本宮守正王"),
    "kanin_007" => ("閑院春仁", "閑院宮春仁王"),
    "p_toshiko" => ("東久邇聡子", "泰宮聡子内親王"),
    "p_fusako_meiji" => ("北白川房子", "周宮房子内親王"),
    "p_shigeko" => ("東久邇成子", "照宮成子内親王"),
)

const REQUIRED_PRE1947_CIVIL_DESCENT_NAME_ALIAS_FORMS = Dict(
    "higashifushimi_002" => ("東伏見慈洽", "邦英王・東伏見邦英"),
)

const REQUIRED_PRE1947_HOUSE_ALIASES = Dict(
    "kuni_001" => "青蓮院宮",
    "kitashirakawa_001" => "輪王寺宮公現親王",
    "higashifushimi_001" => "小松宮依仁親王",
    "komatsu_001" => "仁和寺宮嘉彰親王",
)

const REQUIRED_HIGASHIFUSHIMI_SUCCESSION_NOTES = Dict(
    "higashifushimi_002" => "邦彦王第三男子・1931年臣籍降下・東伏見宮家祭祀継承",
    "higashifushimi_003" => "慈洽第二男子・青蓮院門跡門主",
    "higashifushimi_004" => "慈晃男子・男系男子子孫あり",
)

const REQUIRED_CURRENT_IMPERIAL_NAME_ALIAS_FORMS = Dict(
    "p_shigeko" => ("東久邇成子", "照宮成子内親王"),
    "p_fumihito" => ("秋篠宮文仁親王", ""),
    "n_kiko" => ("文仁親王妃 紀子", "川嶋紀子"),
    "p_yoshihito" => ("桂宮宜仁親王", ""),
    "p_norihito" => ("高円宮憲仁親王", ""),
    "n_hisako" => ("憲仁親王妃 久子", "鳥取久子"),
)

const REQUIRED_CURRENT_IMPERIAL_DISPLAY_NOTES = Dict(
    "p_fumihito" => "上皇第二皇子・皇嗣",
    "n_kiko" => "皇嗣妃",
)

# v4.2.8 宮号・宮家名表記原則:
# 原則として、宮家当主・本人に付与された宮号は name に残し、
# 単にその宮家に属する親王・王には宮家名を冠さない。
# 1947年皇籍離脱者は離脱後の姓+名を name とする。
# alias は離脱直前の皇族名とし、宮家当主には宮家名を付け、単に宮家に属する人物には宮家名を付けない。
# 下記はこの原則に基づく個別 canonical name。
const REQUIRED_HOUSE_NAME_FORMS = Dict(
    "fushimi_024" => "博義王",
    "kuni_011" => "多嘉王",
    "kuni_012" => "賀彦王",
    "higashikuni_013" => "師正王",
    "kitashirakawa_003" => "北白川宮永久王",
    # 戦後皇室側は宮号の付与関係を個人ごとに扱う。
    "p_tomohito" => "寛仁親王",
    "p_yoshihito" => "桂宮宜仁親王",
    "p_norihito" => "高円宮憲仁親王",
)

# v4.2.8 1947年皇籍離脱後の旧宮家当主表記:
# 皇籍在籍中に宮家当主であった人物は「○○宮第N代」。
# 皇籍離脱後に家・祭祀の継承者として当主が移った人物は「旧○○宮第N代」。
# この代数は皇族としての身位ではなく、旧宮家の家系・祭祀継承上の通算代数として扱う。
const REQUIRED_POSTWAR_HOUSE_SUCCESSION_NOTES = Dict(
    "asaka_002" => "鳩彦王第一男子・1947年皇籍離脱・旧朝香宮第2代",
    "asaka_003" => "孚彦王第一男子・1947年皇籍離脱・旧朝香宮第3代",
    "kuni_005" => "朝融王第一男子・1947年皇籍離脱・旧久邇宮第4代",
    "higashikuni_003" => "盛厚王第一男子・1947年皇籍離脱・旧東久邇宮第2代",
    "higashikuni_004" => "東久邇信彦第一男子・旧東久邇宮第3代",
    "takeda_003" => "恒徳王第一男子・1947年皇籍離脱・旧竹田宮第3代",
    "kaya_003" => "恒憲王第一男子・1947年皇籍離脱・旧賀陽宮第3代・子女なし",
    "kaya_004" => "恒憲王第二男子・1947年皇籍離脱・旧賀陽宮第4代",
    "kaya_009" => "賀陽章憲第一男子・旧賀陽宮第5代",
)

const REQUIRED_FEMALE_NAME_ALIAS_FORMS = Dict(
    "n_sadako" => ("貞明皇后", "九条節子"),
    "n_setsuko" => ("雍仁親王妃 勢津子", "松平勢津子"),
    "n_kikuko" => ("宣仁親王妃 喜久子", "徳川喜久子"),
    "n_yuriko" => ("崇仁親王妃 百合子", "高木百合子"),
    "n_hanako" => ("正仁親王妃 華子", "津軽華子"),
    "n_michiko" => ("上皇后 美智子", "正田美智子"),
    "n_masako" => ("皇后 雅子", "小和田雅子"),
    "n_kiko" => ("文仁親王妃 紀子", "川嶋紀子"),
    "n_nobuko" => ("寛仁親王妃 信子", "麻生信子"),
    "n_hisako" => ("憲仁親王妃 久子", "鳥取久子"),
    "p_kazuko" => ("鷹司和子", "孝宮和子内親王"),
    "p_atsuko" => ("池田厚子", "順宮厚子内親王"),
    "p_takako" => ("島津貴子", "清宮貴子内親王"),
    "p_sayako" => ("黒田清子", "紀宮清子内親王"),
    "p_mako" => ("小室眞子", "眞子内親王"),
    "p_noriko" => ("千家典子", "典子女王"),
    "p_ayako" => ("守谷絢子", "絢子女王"),
    "p_yasuko_mikasa" => ("近衞甯子", "甯子内親王"),
    "p_masako_mikasa" => ("千容子", "容子内親王"),
    "p_masako_meiji" => ("恒久王妃 昌子内親王", "常宮昌子内親王"),
    "p_nobuko_meiji" => ("鳩彦王妃 允子内親王", "富美宮允子内親王"),
    "p_toshiko" => ("東久邇聡子", "泰宮聡子内親王"),
    "p_fusako_meiji" => ("北白川房子", "周宮房子内親王"),
    "p_shigeko" => ("東久邇成子", "照宮成子内親王"),
    "kuni_003" => ("香淳皇后", "良子女王"),
)


function suspicious_note_typography(text::String)
    occursin('(', text) || occursin(')', text)
end

# v4.2.8 表記規則:
# 「○○親王妃 紀子」「○○王妃 昌子内親王」のように、
# 身位を表す「親王妃／王妃」と後続する人物名の間には半角空白を1字置く。
# name / alias および婚姻等関係節点の表示文で機械検査する。
function missing_space_after_consort_rank(text::String)
    occursin(r"(?:親王妃|王妃)[一-龯々〆ヵヶぁ-んァ-ヶ]", text)
end

function suspicious_old_rank_wording(text::String)
    occursin(r"(?:親王|王)第[一二三四五六七八九十百]+王子", text) ||
    occursin(r"天皇の第[一二三四五六七八九十百]+皇[子女]", text) ||
    occursin(r"(?:親王|王)の第[一二三四五六七八九十百]+[男女]子", text) ||
    occursin("第一王男子", text)
end


function has_exact_edge(edges, from_id::String, to_id::String, relation::String)
    for row in eachrow(edges)
        cell_string(row.from) == from_id || continue
        cell_string(row.to) == to_id || continue
        cell_string(row.relation) == relation || continue
        return true
    end
    return false
end


const REQUIRED_HISTORICAL_NOTE_FORMS = Dict(
    "t113" => "閑院宮初代直仁親王の父",
)


const REQUIRED_OLD_HOUSE_ADOPTION_EDGES = [
    ("nashimoto_001", "yamashina_002", "adoption"),
]

const REQUIRED_NON_BLOODLINE_EDGES = [
    ("t108", "fushimi_013", "yushi"),
    ("t112", "fushimi_014", "yushi"),
    ("t113", "fushimi_015", "yushi"),
    ("t115", "fushimi_016", "yushi"),
    ("t115", "fushimi_018", "yushi"),
    ("t118", "fushimi_019", "yushi"),
    ("t119", "fushimi_020", "yushi"),
    ("t120", "fushimi_021", "yushi"),
    ("t121", "fushimi_022", "yushi"),
    ("fushimi_021", "fushimi_022", "yushi"),
    ("t119", "yamashina_001", "yushi"),
    ("t121", "yamashina_001", "yushi"),
    ("t120", "kuni_001", "yushi"),
    ("t120", "komatsu_001", "yushi"),
    ("t120", "kitashirakawa_001", "yushi"),
    ("t121", "kacho_001", "yushi"),
    ("t121", "kitashirakawa_005", "yushi"),
    ("t121", "kanin_006", "yushi"),
    ("t122", "higashifushimi_001", "yushi"),
    ("yamashina_001", "higashifushimi_001", "adoption"),
    ("komatsu_001", "higashifushimi_001", "adoption"),
    ("higashifushimi_001", "higashifushimi_002", "yushi"),
]


# v4.2.8 橙色補助血統の正式整理:
# - 橙色は、青・紫では表現されない歴代天皇由来の補完的直系血統経路。
# - 今回変わったのは橙色の意味ではなく、探索範囲を臣籍・公家等まで拡張した点。
# - 皇室・皇族側の橙経路は太実線、臣籍・公家等の区間は太破線。
# - 橙候補は無数にあるため、青・紫未通過の歴代天皇を新たに示せ、かつ史料上明確に追える経路を優先収録する。
# - 婚姻等関係節点では、選択した橙経路本筋側だけを太線とし、反対側配偶者は通常細線。
# - 臣籍女性が正式な后妃として皇室側へ入る地点では本人を実線枠へ戻し、本人→婚姻等関係節点を橙太実線とする。
#   これは皇族身分の取得を意味せず、図上の「皇室側への再流入」を示す。
const BLOODLINE_ORANGE_SCOPE_POLICY = "branch_to_former_subject_and_rejoin_at_union"

# 用語仕様（v4.2.8）:
# CSV内部の type=marriage / spouse_to_union / union_to_child は後方互換のため維持するが、
# 意味論上は「婚姻等関係節点」を表す。婚姻、皇后・妃・側室その他の関係を
# 一つの節点にまとめ、子がある場合はその節点から子へ接続する。子がない場合も
# 二人の関係を表示するために使用でき、個々の関係が制度上同一であることを意味しない。

# 最初の臣籍降下人物。incoming edge は実線橙、outgoing から破線橙。
const FORMER_SUBJECT_TRANSITION_NODE_IDS = Set([
    "c_omimifune",
    "c_ariwara_narihira",
    "c_minamoto_yoshiari",
    "c_konoe_tsunehira",
    "c_shirakawa_nobusane",
    "c_minamoto_tsunemoto",
])

# 天皇の実子だが皇族として公認されず、出生時点から臣籍側で扱われた落胤への境界。
# 通常の臣籍降下人物と異なり、天皇 -> 婚姻等関係節点 -> 本人 の境界区間自体を橙太破線とする。
const ORANGE_DASHED_IMPERIAL_TO_SUBJECT_BOUNDARY_EDGES = Set([
    ("t070", "u_goreizei_masumori_daughter"),
])

# 臣籍出身だが、正式な后妃として皇室側へ再流入した人物。
# lineage_scope は non_imperial のままとし、皇族化を意味させない。
const IMPERIAL_CONSORT_REENTRY_NODE_IDS = Set([
    "n_fujiwara_senshi",
    "n_konoe_sakiko",
    "n_fujiwara_anshi",
    "n_sadako",
    "n_taira_shigeko",
    "n_saionji_kisshi",
])

# 橙経路本筋ではない、婚姻等関係節点反対側配偶者の接続。通常細線とする。
const ORANGE_ROUTE_THIN_SPOUSE_EDGES = Set([
    ("c_fujiwara_tadahira", "u_tadahira_akiko"),
    ("n_fujiwara_moriko", "u_morosuke_moriko"),
    ("c_konoe_iemoto", "u_kameyama_princess_iemoto"),
    ("c_tachibana_shimadamaro", "u_mifune_daughter_shimadamaro"),
    ("c_fujiwara_nakamasa", "u_sumikiyo_daughter_nakamasa"),
    ("c_fujiwara_kaneie", "u_kaneie_tokihime"),
    ("c_fujiwara_yasunori", "u_ariwara_miko_yasunori"),
    ("c_fujiwara_tsunesuke", "u_kiyotsura_daughter_tsunesuke"),
    ("n_minamoto_kiyoto_daughter", "u_yasutada_kiyoto_daughter"),
    ("n_minamoto_nin_daughter", "u_kunimasa_minamoto_nin_daughter"),
    ("c_fujiwara_munetada", "u_yukifusa_daughter_munetada"),
    ("c_fujiwara_sueyuki", "u_muneno_daughter_sueyuki"),
    ("c_mochiie_ieyuki", "u_sadayoshi_daughter_ieyuki"),
    ("c_tokudaiji_sanemori", "u_motochika_daughter_sanemori"),
    ("n_takakura_nagatoyo_daughter", "u_kinari_takakura_daughter"),
    ("n_hosokawa_takamoto_daughter", "u_taneie_hosokawa"),
    ("c_hirohashi_kanesato", "u_toyoko_kanesato"),
    ("c_hirohashi_morimitsu", "u_tsunamitsu_daughter_morimitsu"),
    ("c_higuchi_nobutaka", "u_kanekatsu_daughter_nobutaka"),
    ("c_nijo_harutaka", "u_nobuko_harutaka"),
    ("n_noma_ikuko", "u_michitaka_ikuko"),
    ("c_fujiwara_tamefusa", "u_yorikuni_daughter_tamefusa"),
    ("c_taira_tokinobu", "u_yuko_tokinobu"),
    ("c_fujiwara_kiyotsuna", "u_tameyuki_daughter_kiyotsuna"),
    ("c_minamoto_tameyoshi", "u_tadakiyo_daughter_tameyoshi"),
    ("c_ichijo_yoshiyasu", "u_bomon_yoshiyasu"),
    ("c_saionji_kintsune", "u_masako_kintsune"),
    ("n_shijo_sadako", "u_saneuji_sadako"),
])

const IMPERIAL_CONSORT_REENTRY_EDGES = Set([
    ("n_fujiwara_anshi", "u_murakami_anshi"),
    ("n_fujiwara_senshi", "u_enyu_senshi"),
    ("n_konoe_sakiko", "u_goyozei_sakiko"),
    ("n_sadako", "u_taisho_sadako"),
    ("n_taira_shigeko", "u_goshirakawa_shigeko"),
    ("n_saionji_kisshi", "u_gosaga_kisshi"),
])

# lineage_scope監査で許容する、史料確認済みの臣籍降下境界。
const ALLOWED_IMPERIAL_TO_GRANTED_CLAN_EDGES = Set([
    ("p_ikebe", "c_omimifune"),
    ("t055", "c_minamoto_yoshiari"),
    ("p_kazan_kiyohito", "c_shirakawa_nobusane"),
    ("p_sadazumi", "c_minamoto_tsunemoto"),
])

const ALLOWED_IMPERIAL_UNION_TO_GRANTED_CLAN_CHILDREN = Set([
    ("u_abo_ito", "c_ariwara_narihira"),
])

# imperial の実父を持つが、出生時から皇族として公認されず臣籍側で扱われた実子。
# 婚姻等関係節点を経由する場合の lineage_scope 監査済み落胤例外。
const ALLOWED_IMPERIAL_UNION_TO_NON_IMPERIAL_CHILDREN = Set([
    ("u_goreizei_masumori_daughter", "c_takashina_tameyuki"),
])

function validate_data(nodes, edges)
    house_spouse_subgraph_audit = audit_house_spouse_subgraph_membership(nodes, edges)
    for row in house_spouse_subgraph_audit
        if row.level == "error"
            println("[ERROR][subgraph] $(row.id) $(row.name): $(row.issue)")
        elseif row.level == "warning"
            println("[WARN][subgraph] $(row.id) $(row.name): $(row.issue)")
        end
    end
    errors = String[]
    warnings = String[]

    require_columns(
        nodes,
        ["id","name","alias","type","sex","lineage_scope","birth_year","death_year","traditional_life_years","date_quality","date_quality_detail","date_note","display_note","note"],
        CONFIG.nodes_path,
    )
    require_columns(
        edges,
        ["from","to","relation","style_override","label"],
        CONFIG.edges_path,
    )

    for row in eachrow(nodes)
        id = cell_string(row.id)
        emperor_node_id(id) || continue
        alias = cell_string(row.alias)
        isempty(alias) && push!(errors, "$(id) の歴代天皇 alias が空欄です")
        alias_component_count(alias) > 3 &&
            push!(warnings, "$(id) の alias が4件以上あります。代表的別称への絞り込みを推奨: $(alias)")
    end

    for (from_id, to_id, relation) in REQUIRED_NON_BLOODLINE_EDGES
        has_exact_edge(edges, from_id, to_id, relation) || push!(
            errors,
            "非血縁関係の監査済み edge がありません: $(from_id) -> $(to_id) [$(relation)]",
        )
    end

    for (from_id, to_id, relation) in REQUIRED_OLD_HOUSE_ADOPTION_EDGES
        has_exact_edge(edges, from_id, to_id, relation) || push!(
            errors,
            "旧宮家監査済み adoption edge がありません: $(from_id) -> $(to_id) [$(relation)]",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_HISTORICAL_NOTE_FORMS, id) || continue
        actual_note = cell_string(row.note)
        actual_note == REQUIRED_HISTORICAL_NOTE_FORMS[id] || push!(
            errors,
            "$(id) の歴史系譜監査済み note が標準形と一致しません: $(actual_note)",
        )
    end

    required_relationship_node = "u_kogen_ikagashikome"
    required_relationship_node in [cell_string(x) for x in nodes.id] || push!(
        errors,
        "伊香色謎命と孝元天皇の婚姻等関係節点 u_kogen_ikagashikome がありません。",
    )
    has_exact_edge(edges, "t008", required_relationship_node, "spouse_to_union") || push!(
        errors,
        "孝元天皇→u_kogen_ikagashikome の spouse_to_union がありません。",
    )
    has_exact_edge(edges, "n_ikagashikome", required_relationship_node, "spouse_to_union") || push!(
        errors,
        "伊香色謎命→u_kogen_ikagashikome の spouse_to_union がありません。",
    )

    for row in eachrow(nodes)
        id = cell_string(row.id)
        for col in ("display_note", "note")
            text = cell_string(row[Symbol(col)])
            suspicious_note_typography(text) && push!(
                warnings,
                "$(id) の $(col) に半角括弧があります: $(text)",
            )
            suspicious_old_rank_wording(text) && push!(
                errors,
                "$(id) の $(col) に旧式の子順位表現があります: $(text)",
            )
        end
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        id == "p_morisada" || continue
        display_note = cell_string(row.display_note)
        occursin("高倉天皇皇子", display_note) || push!(
            errors,
            "p_morisada の display_note で父が高倉天皇として明示されていません: $(display_note)",
        )
    end

    # v4.2.8 身位語と後続人物名の間の半角空白を検査する。
    # 典拠名を原文保持する date_note は対象外。
    for row in eachrow(nodes)
        id = cell_string(row.id)
        typ = cell_string(row.type)
        for field in (:name, :alias)
            text = cell_string(getproperty(row, field))
            missing_space_after_consort_rank(text) && push!(errors, "$(id): $(field) で『親王妃／王妃』と後続人物名の間に半角空白がありません: $(text)")
        end
        if typ == "marriage"
            for field in (:display_note, :note)
                text = cell_string(getproperty(row, field))
                missing_space_after_consort_rank(text) && push!(errors, "$(id): $(field) で『親王妃／王妃』と後続人物名の間に半角空白がありません: $(text)")
            end
        end
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_PRE1947_CIVIL_DESCENT_NAME_ALIAS_FORMS, id) || continue
        expected_name, expected_alias = REQUIRED_PRE1947_CIVIL_DESCENT_NAME_ALIAS_FORMS[id]
        actual_name = cell_string(row.name)
        actual_alias = cell_string(row.alias)
        actual_name == expected_name || push!(errors,
            "$(id) の1947年以前臣籍降下者 canonical name が標準形と一致しません: $(actual_name)",
        )
        actual_alias == expected_alias || push!(errors,
            "$(id) の1947年以前臣籍降下者 alias が標準形と一致しません: $(actual_alias)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_HIGASHIFUSHIMI_SUCCESSION_NOTES, id) || continue
        expected = REQUIRED_HIGASHIFUSHIMI_SUCCESSION_NOTES[id]
        actual = cell_string(row.display_note)
        actual == expected || push!(errors,
            "$(id) の東伏見宮祭祀継承 display_note が標準形と一致しません: $(actual)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_CURRENT_IMPERIAL_NAME_ALIAS_FORMS, id) || continue
        expected_name, expected_alias = REQUIRED_CURRENT_IMPERIAL_NAME_ALIAS_FORMS[id]
        actual_name = cell_string(row.name)
        actual_alias = cell_string(row.alias)
        actual_name == expected_name || push!(errors,
            "$(id) の現皇室周辺 canonical name が標準形と一致しません: $(actual_name)",
        )
        actual_alias == expected_alias || push!(errors,
            "$(id) の現皇室周辺 alias が標準形と一致しません: $(actual_alias)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_CURRENT_IMPERIAL_DISPLAY_NOTES, id) || continue
        expected = REQUIRED_CURRENT_IMPERIAL_DISPLAY_NOTES[id]
        actual = cell_string(row.display_note)
        actual == expected || push!(errors,
            "$(id) の現皇室周辺 display_note が標準形と一致しません: $(actual)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_HOUSE_NAME_FORMS, id) || continue
        expected = REQUIRED_HOUSE_NAME_FORMS[id]
        actual = cell_string(row.name)
        actual == expected || push!(errors,
            "$(id) の宮号・宮家名を含む canonical name が個別監査結果と一致しません: $(actual)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_POSTWAR_HOUSE_SUCCESSION_NOTES, id) || continue
        expected = REQUIRED_POSTWAR_HOUSE_SUCCESSION_NOTES[id]
        actual = cell_string(row.display_note)
        actual == expected || push!(errors,
            "$(id) の1947年皇籍離脱後の旧宮家当主注記が監査結果と一致しません: $(actual)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_FEMALE_NAME_ALIAS_FORMS, id) || continue
        expected_name, expected_alias = REQUIRED_FEMALE_NAME_ALIAS_FORMS[id]
        actual_name = cell_string(row.name)
        actual_alias = cell_string(row.alias)
        actual_name == expected_name || push!(
            errors,
            "$(id) の女性人物 canonical name が標準形と一致しません: $(actual_name)",
        )
        actual_alias == expected_alias || push!(
            errors,
            "$(id) の女性人物 alias が標準形と一致しません: $(actual_alias)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_PRE1947_HOUSE_ALIASES, id) || continue
        alias = cell_string(row.alias)
        alias == REQUIRED_PRE1947_HOUSE_ALIASES[id] || push!(
            errors,
            "$(id) の1947年以前宮家人物aliasが再監査結果と一致しません: $(alias)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_1947_NAME_ALIAS_FORMS, id) || continue
        expected_name, expected_alias = REQUIRED_1947_NAME_ALIAS_FORMS[id]
        actual_name = cell_string(row.name)
        actual_alias = cell_string(row.alias)
        actual_name == expected_name || push!(
            errors,
            "$(id) の1947年前後の canonical name が標準形と一致しません: $(actual_name)",
        )
        actual_alias == expected_alias || push!(
            errors,
            "$(id) の1947年前後の alias が標準形と一致しません: $(actual_alias)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(REQUIRED_NON_EMPEROR_ALIASES, id) || continue
        alias = cell_string(row.alias)
        alias == REQUIRED_NON_EMPEROR_ALIASES[id] || push!(
            errors,
            "$(id) の非天皇人物aliasが再監査結果と一致しません: $(alias)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        haskey(DEPRECATED_EMPEROR_ALIAS_FORMS, id) || continue
        alias = cell_string(row.alias)
        alias == DEPRECATED_EMPEROR_ALIAS_FORMS[id] || continue
        push!(
            errors,
            "$(id) の alias が再監査前の旧表記へ戻っています: $(alias)",
        )
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        for col in ("name", "alias", "display_note", "note")
            text = cell_string(row[Symbol(col)])
            suspicious_japanese_name_space(text) || continue
            push!(
                errors,
                "$(id) の $(col) に人名内部とみられる半角空白があります: $(text)",
            )
        end
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        for col in ("display_note", "note")
            text = cell_string(row[Symbol(col)])
            suspicious_annotation_register(text) || continue
            push!(
                errors,
                "$(id) の $(col) に内部作業語・収録方針的な表現があります: $(text)",
            )
        end
    end

    for row in eachrow(nodes)
        id = cell_string(row.id)
        birth_year = cell_string(row.birth_year)
        death_year = cell_string(row.death_year)
        for col in ("display_note", "note")
            text = cell_string(row[Symbol(col)])
            redundant_life_year_annotation(text, birth_year, death_year) || continue
            push!(
                errors,
                "$(id) の $(col) に birth_year / death_year と重複する生没年表現があります: $(text)",
            )
        end
    end

    ids = [cell_string(x) for x in nodes.id]
    idset = Set(ids)
    length(ids) == length(idset) ||
        push!(errors, "$(basename(CONFIG.nodes_path)) に重複IDがあります。")

    allowed_types = Set([
        "tenno",
        "female_tenno",
        "prince",
        "princess",
        "civil_prince",
        "civil_princess",
        "imperial_descendant",
        "marriage",
    ])
    allowed_sex = Set(["", "male", "female"])
    allowed_rel = Set([
        "biological_parent",
        "spouse_to_union",
        "union_to_child",
        "yushi",
        "adoption",
        "layout_hint",
    ])
    allowed_override = Set([
        "",
        "main_blue",
        "female_purple",
        "bloodline_orange",
        "bloodline_orange_dashed",
        "modern_inflow_green",
        "default",
        "yushi",
    ])
    allowed_lineage_scope = Set([
        "",
        "imperial",
        "non_imperial",
        "granted_clan",
        "claimed",
        "unknown",
    ])

    allowed_date_quality = Set([
        "",
        "A_standard",
        "B_partial_or_disputed",
        "C_secondary_genealogy",
        "T_traditional",
        "U_undated",
    ])

    allowed_date_quality_detail = Set([
        "birth_unrecorded",
        "death_unrecorded",
        "disputed_birth",
        "disputed_death",
        "source_mixed",
        "value_corrected",
        "legendary_or_mythic",
        "genealogical_tradition",
        "chronicle_activity_only",
        "historical_period_known",
        "source_conflict_uncertain",
        "external_source_contact",
        "nihon_shoki_based",
        "kesshi_hachidai",
        "chronology_conversion",
        "uncertain_birth",
        "disputed_death_t",
        "historicity_debated",
        "external_source_contact_t",
        "legendary_era",
    ])

    node_type = Dict{String,String}()
    node_sex = Dict{String,String}()
    node_scope = Dict{String,String}()

    # --------------------------------------------------------
    # ノード単体の整合性
    # --------------------------------------------------------
    for (i, row) in enumerate(eachrow(nodes))
        rowno = i + 1
        id = cell_string(row.id)
        typ = cell_string(row.type)
        sex = cell_string(row.sex)
        scope = cell_string(row.lineage_scope)
        quality = cell_string(row.date_quality)
        quality_detail = cell_string(row.date_quality_detail)
        detail_tags = isempty(quality_detail) ? String[] : split(quality_detail, ";")
        birth = cell_string(row.birth_year)
        death = cell_string(row.death_year)
        traditional = cell_string(row.traditional_life_years)

        isempty(id) &&
            push!(errors, "$(basename(CONFIG.nodes_path)) $(rowno)行目: id が空です。")

        !(typ in allowed_types) &&
            push!(errors, "$(basename(CONFIG.nodes_path)) $(rowno)行目: 未知の type=$(typ)")

        !(sex in allowed_sex) &&
            push!(errors, "$(basename(CONFIG.nodes_path)) $(rowno)行目: 未知の sex=$(sex)")

        !(scope in allowed_lineage_scope) &&
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: 未知の lineage_scope=$(scope)",
            )

        !(quality in allowed_date_quality) &&
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: 未知の date_quality=$(quality)",
            )

        for tag in detail_tags
            !(tag in allowed_date_quality_detail) &&
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: 未知の date_quality_detail tag=$(tag)",
                )
        end
        length(detail_tags) != length(unique(detail_tags)) &&
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: date_quality_detail に重複tagがあります。",
            )

        # birth_year / death_year は実年の整数文字列または空欄だけを許す。
        # 不明年は空欄とし、表示時に ? を補う。
        for (field_name, value) in (("birth_year", birth), ("death_year", death))
            if !isempty(value) && isnothing(match(r"^\d+$", value))
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(field_name)=$(value) は整数年または空欄でなければなりません。",
                )
            end
        end

        # traditional_life_years は「左–右」の伝承紀年文字列。
        if !isempty(traditional) &&
           isnothing(match(r"^(?:\?|(?:前)?\d+\??)–(?:\?|(?:前)?\d+\??(?:/(?:前)?\d+\??)*)$", traditional))
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: traditional_life_years=$(traditional) の書式を確認してください。",
            )
        end

        isempty(id) && continue

        node_type[id] = typ
        node_sex[id] = sex
        node_scope[id] = scope

        if typ == "marriage"
            !isempty(sex) &&
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: 婚姻等関係節点 $(id) の sex は空欄でなければなりません。",
                )
            !isempty(scope) &&
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: 婚姻等関係節点 $(id) の lineage_scope は空欄でなければなりません。",
                )
            !isempty(quality) &&
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: 婚姻等関係節点 $(id) の date_quality は空欄でなければなりません。",
                )
            !isempty(quality_detail) &&
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: 婚姻等関係節点 $(id) の date_quality_detail は空欄でなければなりません。",
                )
            continue
        end

        # 人物ノードではlineage_scopeとdate_qualityを必須とする。
        isempty(scope) &&
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: 人物 $(id) の lineage_scope が空です。",
            )

        isempty(quality) &&
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: 人物 $(id) の date_quality が空です。",
            )

        if quality in ("B_partial_or_disputed", "U_undated", "T_traditional")
            isempty(detail_tags) &&
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(quality) 人物 $(id) の date_quality_detail が空です。",
                )
        elseif !isempty(detail_tags)
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: B/U/T以外の人物 $(id) に date_quality_detail が設定されています。",
            )
        end

        b_only_tags = Set([
            "birth_unrecorded", "death_unrecorded", "disputed_birth",
            "disputed_death", "source_mixed", "value_corrected",
        ])
        u_only_tags = Set([
            "legendary_or_mythic", "genealogical_tradition",
            "chronicle_activity_only", "historical_period_known",
            "source_conflict_uncertain", "external_source_contact",
        ])
        t_only_tags = Set([
            "nihon_shoki_based", "kesshi_hachidai", "chronology_conversion",
            "uncertain_birth", "disputed_death_t", "historicity_debated",
            "external_source_contact_t", "legendary_era",
        ])
        if quality == "B_partial_or_disputed" &&
           any(tag -> tag in union(u_only_tags, t_only_tags), detail_tags)
            push!(errors, "$(basename(CONFIG.nodes_path)) $(rowno)行目: B人物 $(id) にB以外の専用tagがあります。")
        elseif quality == "U_undated" &&
               any(tag -> tag in union(b_only_tags, t_only_tags), detail_tags)
            push!(errors, "$(basename(CONFIG.nodes_path)) $(rowno)行目: U人物 $(id) にU以外の専用tagがあります。")
        elseif quality == "T_traditional" &&
               any(tag -> tag in union(b_only_tags, u_only_tags), detail_tags)
            push!(errors, "$(basename(CONFIG.nodes_path)) $(rowno)行目: T人物 $(id) にT以外の専用tagがあります。")
        end

        # detail tag と実データの整合
        "birth_unrecorded" in detail_tags && !isempty(birth) &&
            push!(errors, "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(id) は birth_unrecorded ですが birth_year が入っています。")
        "death_unrecorded" in detail_tags && !isempty(death) &&
            push!(errors, "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(id) は death_unrecorded ですが death_year が入っています。")

        has_normal = !isempty(birth) || !isempty(death)
        has_traditional = !isempty(traditional)

        if quality == "T_traditional" && (!has_traditional || has_normal)
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(id) は date_quality=T_traditional なので traditional_life_yearsのみを持つ必要があります。",
            )
        elseif quality == "U_undated" && (has_normal || has_traditional)
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(id) は date_quality=U_undated ですが年代欄に値があります。",
            )
        elseif quality in ("A_standard", "B_partial_or_disputed", "C_secondary_genealogy")
            if !has_normal || has_traditional
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(id) の date_quality=$(quality) は通常年代を持ち、traditional_life_yearsを持たない必要があります。",
                )
            end
        end

        scope == "unknown" &&
            push!(
                warnings,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: 人物 $(id) の lineage_scope は unknown です。判定確定後に更新してください。",
            )

        # type と sex の対応
        expected_sex = if typ in ("tenno", "prince", "civil_prince")
            "male"
        elseif typ in ("female_tenno", "princess", "civil_princess")
            "female"
        else
            ""
        end

        !isempty(expected_sex) && sex != expected_sex &&
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(id) は type=$(typ) なので sex=$(expected_sex) でなければなりません。現在=$(sex)",
            )

        typ == "imperial_descendant" && !(sex in ("male", "female")) &&
            push!(
                errors,
                "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(id) は type=imperial_descendant なので sex は male または female でなければなりません。現在=$(sex)",
            )

        # type と lineage_scope の対応
        if typ in ("tenno", "female_tenno", "prince", "princess", "imperial_descendant")
            scope != "imperial" &&
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(id) は type=$(typ) なので lineage_scope=imperial でなければなりません。現在=$(scope)",
                )
        elseif typ in ("civil_prince", "civil_princess")
            !(scope in ("non_imperial", "granted_clan", "claimed")) &&
                push!(
                    errors,
                    "$(basename(CONFIG.nodes_path)) $(rowno)行目: $(id) は type=$(typ) なので lineage_scope は non_imperial / granted_clan / claimed のいずれかでなければなりません。現在=$(scope)",
                )
        end
    end

    # --------------------------------------------------------
    # エッジ構造とlineage_scope継承の整合性
    # --------------------------------------------------------
    seen_edges = Set{Tuple{String,String,String}}()

    for (i, row) in enumerate(eachrow(edges))
        rowno = i + 1
        from = cell_string(row.from)
        to = cell_string(row.to)
        relation = cell_string(row.relation)
        override = cell_string(row.style_override)

        !(from in idset) &&
            push!(errors, "$(basename(CONFIG.edges_path)) $(rowno)行目: 未定義 from=$(from)")
        !(to in idset) &&
            push!(errors, "$(basename(CONFIG.edges_path)) $(rowno)行目: 未定義 to=$(to)")
        !(relation in allowed_rel) &&
            push!(errors, "$(basename(CONFIG.edges_path)) $(rowno)行目: 未知の relation=$(relation)")
        !(override in allowed_override) &&
            push!(errors, "$(basename(CONFIG.edges_path)) $(rowno)行目: 未知の style_override=$(override)")
        from == to &&
            push!(errors, "$(basename(CONFIG.edges_path)) $(rowno)行目: 自己参照 $(from)")

        edge_key = (from, to, relation)
        edge_key in seen_edges &&
            push!(
                errors,
                "$(basename(CONFIG.edges_path)) $(rowno)行目: 重複エッジ $(from) → $(to), relation=$(relation)",
            )
        push!(seen_edges, edge_key)

        # 以降は両端ノードが存在するときだけ確認。
        !(from in idset && to in idset) && continue

        from_type = get(node_type, from, "")
        to_type = get(node_type, to, "")
        from_sex = get(node_sex, from, "")
        from_scope = get(node_scope, from, "")
        to_scope = get(node_scope, to, "")

        if relation == "biological_parent"
            from_type == "marriage" &&
                push!(
                    errors,
                    "$(basename(CONFIG.edges_path)) $(rowno)行目: biological_parent の from=$(from) は人物でなければなりません。",
                )
            to_type == "marriage" &&
                push!(
                    errors,
                    "$(basename(CONFIG.edges_path)) $(rowno)行目: biological_parent の to=$(to) は人物でなければなりません。",
                )

            # 父から実子へのlineage_scopeは原則として継承される。
            if from_sex == "male" && from_type != "marriage" && to_type != "marriage"
                if from_scope == "imperial" && to_scope != "imperial"
                    if to_scope == "non_imperial" && (from, to) in ORANGE_DASHED_IMPERIAL_TO_SUBJECT_BOUNDARY_EDGES
                        # v4.2.8: 後冷泉天皇→婚姻等関係節点→高階為行のように、実子であっても
                        # 皇族として公認されず出生時点から臣籍側で扱われた監査済み落胤境界。
                        # lineage_scope=non_imperial を維持して許容する。
                    elseif to_scope == "granted_clan" && (from, to) in ALLOWED_IMPERIAL_TO_GRANTED_CLAN_EDGES
                        # 明示済みの臣籍降下境界なので許容する。
                    else
                        push!(
                            errors,
                            "$(basename(CONFIG.edges_path)) $(rowno)行目: imperialの父 $(from) の実子 $(to) は lineage_scope=imperial でなければなりません。現在=$(to_scope)",
                        )
                    end
                elseif from_scope == "non_imperial" && to_scope == "imperial"
                    push!(
                        errors,
                        "$(basename(CONFIG.edges_path)) $(rowno)行目: non_imperialの父 $(from) から imperialの実子 $(to) への接続があります。lineage_scopeまたは親子関係を確認してください。",
                    )
                elseif from_scope in ("granted_clan", "claimed") && to_scope == "imperial"
                    push!(
                        errors,
                        "$(basename(CONFIG.edges_path)) $(rowno)行目: $(from_scope)の父 $(from) から imperialの実子 $(to) への接続があります。lineage_scopeまたは親子関係を確認してください。",
                    )
                elseif from_scope == "unknown" || to_scope == "unknown"
                    push!(
                        warnings,
                        "$(basename(CONFIG.edges_path)) $(rowno)行目: 父系継承 $(from) → $(to) に lineage_scope=unknown が含まれます。",
                    )
                end
            end

        elseif relation == "spouse_to_union"
            from_type == "marriage" &&
                push!(
                    errors,
                    "$(basename(CONFIG.edges_path)) $(rowno)行目: spouse_to_union の from=$(from) は人物でなければなりません。",
                )
            to_type != "marriage" &&
                push!(
                    errors,
                    "$(basename(CONFIG.edges_path)) $(rowno)行目: spouse_to_union の to=$(to) は婚姻等関係節点でなければなりません。",
                )

        elseif relation == "union_to_child"
            from_type != "marriage" &&
                push!(
                    errors,
                    "$(basename(CONFIG.edges_path)) $(rowno)行目: union_to_child の from=$(from) は婚姻等関係節点でなければなりません。",
                )
            to_type == "marriage" &&
                push!(
                    errors,
                    "$(basename(CONFIG.edges_path)) $(rowno)行目: union_to_child の to=$(to) は人物でなければなりません。",
                )

        elseif relation in ("yushi", "adoption")
            (from_type == "marriage" || to_type == "marriage") &&
                push!(
                    errors,
                    "$(basename(CONFIG.edges_path)) $(rowno)行目: $(relation) は人物同士の関係でなければなりません。",
                )
        end
    end


    # --------------------------------------------------------
    # v4.2.8 臣籍降下後再流入線の整合性
    # --------------------------------------------------------
    former_subject_ids = FORMER_SUBJECT_ROUTE_NODE_IDS
    former_subject_union_ids = FORMER_SUBJECT_ROUTE_UNION_IDS

    for (i, row) in enumerate(eachrow(edges))
        cell_string(row.style_override) == "bloodline_orange_dashed" || continue
        from = cell_string(row.from)
        to = cell_string(row.to)

        # 后妃再流入人物（例: 貞明皇后）は臣籍経路の終端になり得るが、
        # FORMER_SUBJECT_ROUTE_NODE_IDS には入れない（破線枠を付けないため）。
        # 監査上のみ、IMPERIAL_CONSORT_REENTRY_NODE_IDS を許容する。
        from_ok = from in former_subject_ids || from in former_subject_union_ids || from in IMPERIAL_CONSORT_REENTRY_NODE_IDS
        to_ok = to in former_subject_ids || to in former_subject_union_ids || to in IMPERIAL_CONSORT_REENTRY_NODE_IDS
        boundary_ok = (from, to) in ORANGE_DASHED_IMPERIAL_TO_SUBJECT_BOUNDARY_EDGES

        # 再流入時は、臣籍側人物 -> 婚姻等関係節点 までを破線とし、
        # 婚姻等関係節点 -> 皇族の子は既存の青線等に戻す。
        # ただし後冷泉天皇 -> 婚姻等関係節点 -> 高階為行は、実子であっても皇族として公認されず
        # 出生時点から高階氏側で扱われたため、天皇側から婚姻等関係節点への最初の1本と
        # 婚姻等関係節点から為行への1本を破線とする。
        ((from_ok && to_ok) || boundary_ok) || push!(
            errors,
            "臣籍再流入線監査: $(from) -> $(to) は監査済み臣籍経路、または監査済み落胤境界でなければなりません。",
        )
    end

    for id in former_subject_ids
        id in idset || push!(errors, "臣籍再流入線監査: 破線枠対象ノード $(id) がありません。")
        id in idset || continue
        scope = get(node_scope, id, "")
        !(scope in ("granted_clan", "non_imperial")) && push!(
            errors,
            "臣籍再流入線監査: 破線枠対象 $(id) の lineage_scope=$(scope) は granted_clan / non_imperial でなければなりません。",
        )
    end

    # v4.2.8 橙経路の婚姻等関係節点・后妃再流入監査
    edge_style_by_pair = Dict{Tuple{String,String},String}()
    for row in eachrow(edges)
        edge_style_by_pair[(cell_string(row.from), cell_string(row.to))] = cell_string(row.style_override)
    end
    for pair in ORANGE_ROUTE_THIN_SPOUSE_EDGES
        get(edge_style_by_pair, pair, "__missing__") == "" || push!(errors,
            "橙経路監査: 反対側配偶者 $(pair[1]) -> $(pair[2]) は通常細線（style_override空欄）でなければなりません。")
    end
    for pair in IMPERIAL_CONSORT_REENTRY_EDGES
        get(edge_style_by_pair, pair, "__missing__") == "bloodline_orange" || push!(errors,
            "橙経路監査: 后妃再流入 $(pair[1]) -> $(pair[2]) は bloodline_orange 太実線でなければなりません。")
    end

    # v4.2.8 追加・継続経路の要所。文徳・亀山・清和・後冷泉各天皇が橙経路に入り、
    # 臣籍区間へ移った後は太破線、既存太線との合流点では既存色を優先する。
    required_orange_edges = Dict(
        ("t055", "t056") => "bloodline_orange",
        ("t063", "t065") => "bloodline_orange",
        ("t054", "t055") => "bloodline_orange",
        ("t055", "c_minamoto_yoshiari") => "bloodline_orange",
        ("c_minamoto_yoshiari", "n_minamoto_akiko") => "bloodline_orange_dashed",
        ("u_gosaga_kisshi", "t090") => "bloodline_orange",
        ("t090", "p_kameyama_princess") => "bloodline_orange",
        ("p_kameyama_princess", "u_kameyama_princess_iemoto") => "bloodline_orange",
        ("u_kameyama_princess_iemoto", "c_konoe_tsunehira") => "bloodline_orange",
        ("c_konoe_tsunehira", "c_konoe_mototsugu") => "bloodline_orange_dashed",
        ("c_konoe_masaie", "c_konoe_hisamichi") => "bloodline_orange_dashed",
        ("c_konoe_hisamichi", "u_ishiko_hisamichi") => "bloodline_orange_dashed",
        ("t056", "p_sadazumi") => "bloodline_orange",
        ("p_sadazumi", "c_minamoto_tsunemoto") => "bloodline_orange",
        ("c_minamoto_tsunemoto", "c_minamoto_mitsunaka") => "bloodline_orange_dashed",
        ("c_minamoto_yorikuni", "n_minamoto_yorikuni_daughter") => "bloodline_orange_dashed",
        ("u_yuko_tokinobu", "n_taira_shigeko") => "bloodline_orange_dashed",
        ("n_taira_shigeko", "u_goshirakawa_shigeko") => "bloodline_orange",
        ("t069", "t070") => "bloodline_orange",
        ("t070", "u_goreizei_masumori_daughter") => "bloodline_orange_dashed",
        ("u_goreizei_masumori_daughter", "c_takashina_tameyuki") => "bloodline_orange_dashed",
        ("c_takashina_tameyuki", "n_takashina_tameyuki_daughter") => "bloodline_orange_dashed",
        ("n_takashina_tameyuki_daughter", "u_tameyuki_daughter_kiyotsuna") => "bloodline_orange_dashed",
        ("u_tameyuki_daughter_kiyotsuna", "c_fujiwara_tadakiyo") => "bloodline_orange_dashed",
        ("c_fujiwara_tadakiyo", "n_fujiwara_tadakiyo_daughter") => "bloodline_orange_dashed",
        ("u_tadakiyo_daughter_tameyoshi", "c_minamoto_yoshitomo") => "bloodline_orange_dashed",
        ("c_minamoto_yoshitomo", "n_bomon_hime") => "bloodline_orange_dashed",
        ("u_bomon_yoshiyasu", "n_ichijo_masako") => "bloodline_orange_dashed",
        ("u_masako_kintsune", "c_saionji_saneuji") => "bloodline_orange_dashed",
        ("u_saneuji_sadako", "n_saionji_kisshi") => "bloodline_orange_dashed",
        ("n_saionji_kisshi", "u_gosaga_kisshi") => "bloodline_orange",
    )
    for (pair, expected_style) in required_orange_edges
        get(edge_style_by_pair, pair, "__missing__") == expected_style || push!(errors,
            "橙経路監査: $(pair[1]) -> $(pair[2]) は $(expected_style) でなければなりません。")
    end

    # --------------------------------------------------------
    # 婚姻等関係節点単位の集約検査
    # --------------------------------------------------------
    spouses_by_union = Dict{String,Vector{String}}()
    children_by_union = Dict{String,Vector{String}}()

    for row in eachrow(edges)
        from = cell_string(row.from)
        to = cell_string(row.to)
        relation = cell_string(row.relation)

        if relation == "spouse_to_union" && to in idset
            push!(get!(spouses_by_union, to, String[]), from)
        elseif relation == "union_to_child" && from in idset
            push!(get!(children_by_union, from, String[]), to)
        end
    end

    for row in eachrow(nodes)
        union_id = cell_string(row.id)
        cell_string(row.type) == "marriage" || continue

        spouses = get(spouses_by_union, union_id, String[])
        children = get(children_by_union, union_id, String[])

        valid_spouses = [id for id in spouses if id in idset]
        valid_children = [id for id in children if id in idset]

        male_spouses = [
            id for id in valid_spouses
            if get(node_sex, id, "") == "male"
        ]
        female_spouses = [
            id for id in valid_spouses
            if get(node_sex, id, "") == "female"
        ]
        unknown_sex_spouses = [
            id for id in valid_spouses
            if !(get(node_sex, id, "") in ("male", "female"))
        ]

        isempty(valid_spouses) &&
            push!(
                errors,
                "婚姻等関係節点監査: $(union_id) に spouse_to_union が1本もありません。",
            )

        length(valid_spouses) == 1 &&
            push!(
                warnings,
                "婚姻等関係節点監査: $(union_id) の配偶者が1人だけ登録されています。未登録側が意図的か確認してください。",
            )

        length(valid_spouses) > 2 &&
            push!(
                errors,
                "婚姻等関係節点監査: $(union_id) に配偶者が $(length(valid_spouses)) 人接続されています。通常は最大2人です。",
            )

        length(male_spouses) > 1 &&
            push!(
                errors,
                "婚姻等関係節点監査: $(union_id) に男性配偶者が複数接続されています: $(join(male_spouses, ", "))",
            )

        length(female_spouses) > 1 &&
            push!(
                errors,
                "婚姻等関係節点監査: $(union_id) に女性配偶者が複数接続されています: $(join(female_spouses, ", "))",
            )

        !isempty(unknown_sex_spouses) &&
            push!(
                errors,
                "婚姻等関係節点監査: $(union_id) の配偶者に sex 未確定人物があります: $(join(unknown_sex_spouses, ", "))",
            )

        if length(valid_spouses) == 2 &&
           !(length(male_spouses) == 1 && length(female_spouses) == 1)
            push!(
                errors,
                "婚姻等関係節点監査: $(union_id) の配偶者2人は male 1人・female 1人でなければなりません。",
            )
        end

        # 子がいない婚姻等関係節点は許容する。
        isempty(valid_children) && continue

        # 子がいる婚姻等関係節点には、少なくとも一人の配偶者が必要。
        isempty(valid_spouses) &&
            push!(
                errors,
                "婚姻等関係節点監査: $(union_id) から子が接続されていますが、配偶者が登録されていません。",
            )

        # 男性配偶者を父としてlineage_scope継承を検査する。
        if length(male_spouses) == 1
            father = only(male_spouses)
            father_scope = get(node_scope, father, "")

            for child in valid_children
                child_scope = get(node_scope, child, "")

                if father_scope == "imperial" && child_scope != "imperial"
                    if child_scope == "non_imperial" && (union_id, child) in ALLOWED_IMPERIAL_UNION_TO_NON_IMPERIAL_CHILDREN
                        # v4.2.8: 後冷泉天皇＋増守の娘→高階為行のように、
                        # 実子であっても皇族として公認されず出生時点から臣籍側で扱われた
                        # 監査済み落胤境界。lineage_scope=non_imperial を維持して許容する。
                    elseif child_scope == "granted_clan" && (union_id, child) in ALLOWED_IMPERIAL_UNION_TO_GRANTED_CLAN_CHILDREN
                        # 明示済みの臣籍降下境界なので許容する。
                    else
                        push!(
                            errors,
                            "婚姻等関係節点監査: imperialの父 $(father) を持つ婚姻等関係節点 $(union_id) の実子 $(child) は lineage_scope=imperial でなければなりません。現在=$(child_scope)",
                        )
                    end
                elseif father_scope in ("non_imperial", "granted_clan", "claimed") &&
                       child_scope == "imperial"
                    push!(
                        errors,
                        "婚姻等関係節点監査: $(father_scope)の父 $(father) を持つ婚姻等関係節点 $(union_id) から imperialの実子 $(child) へ接続しています。lineage_scopeまたは父母子関係を確認してください。",
                    )
                elseif father_scope == "unknown" || child_scope == "unknown"
                    push!(
                        warnings,
                        "婚姻等関係節点監査: 父系継承 $(father) → $(union_id) → $(child) に lineage_scope=unknown が含まれます。",
                    )
                end
            end
        elseif isempty(male_spouses)
            push!(
                warnings,
                "婚姻等関係節点監査: 子を持つ婚姻等関係節点 $(union_id) に男性配偶者が登録されていないため、父系lineage_scopeを検査できません。",
            )
        end
    end

    # --------------------------------------------------------
    # 婚姻等関係節点と直接親子線を横断した構造監査（v4.2.8）
    # --------------------------------------------------------
    direct_parents_by_child = Dict{String,Set{String}}()
    unions_by_child = Dict{String,Vector{String}}()
    unions_by_person = Dict{String,Vector{String}}()

    for row in eachrow(edges)
        from = cell_string(row.from)
        to = cell_string(row.to)
        relation = cell_string(row.relation)

        if relation == "biological_parent" && from in idset && to in idset
            push!(get!(direct_parents_by_child, to, Set{String}()), from)
        elseif relation == "union_to_child" && from in idset && to in idset
            push!(get!(unions_by_child, to, String[]), from)
        elseif relation == "spouse_to_union" && from in idset && to in idset
            push!(get!(unions_by_person, from, String[]), to)
        end
    end

    # 同一人物が複数婚姻等関係節点に属すること自体は、再婚・複数配偶者等があり得るため
    # エラーにも警告にもしない。validation_report側で情報として集計する。
    #
    # ただし、同一の子が「異なる親組合せ」の婚姻等関係節点から生まれたことになっていれば
    # 系譜構造上の矛盾としてエラーにする。
    for (child, union_ids) in unions_by_child
        parent_sets = Set{Tuple}()

        for union_id in union_ids
            parents = sort(unique(get(spouses_by_union, union_id, String[])))
            push!(parent_sets, Tuple(parents))
        end

        length(parent_sets) > 1 &&
            push!(
                errors,
                "婚姻等関係節点横断監査: 子 $(child) が異なる親組合せの婚姻等関係節点から接続されています: $(join(sort(unique(union_ids)), ", "))",
            )

        direct_parents = get(direct_parents_by_child, child, Set{String}())

        for union_id in union_ids
            union_parents = Set(get(spouses_by_union, union_id, String[]))

            duplicated = intersect(direct_parents, union_parents)
            !isempty(duplicated) &&
                push!(
                    warnings,
                    "婚姻等関係節点横断監査: 子 $(child) の親 $(join(sort(collect(duplicated)), ", ")) が、婚姻等関係節点 $(union_id) 経由と biological_parent の両方で二重表現されています。",
                )

            outside = setdiff(direct_parents, union_parents)
            !isempty(outside) &&
                push!(
                    warnings,
                    "婚姻等関係節点横断監査: 子 $(child) に、婚姻等関係節点 $(union_id) の配偶者集合外の直接親子線があります: $(join(sort(collect(outside)), ", "))。意図的表現か確認してください。",
                )
        end
    end

    return errors, warnings
end

function build_graph(nodes, edges)
    node_type = Dict(cell_string(r.id)=>cell_string(r.type) for r in eachrow(nodes))
    node_sex  = Dict(cell_string(r.id)=>cell_string(r.sex) for r in eachrow(nodes))
    adj = Dict{String,Vector{Tuple{String,Int}}}()
    for (i,r) in enumerate(eachrow(edges))
        rel=cell_string(r.relation)
        if rel in ("biological_parent","spouse_to_union","union_to_child")
            f=cell_string(r.from); t=cell_string(r.to)
            push!(get!(adj,f,Tuple{String,Int}[]),(t,i))
        end
    end
    node_type,node_sex,adj
end

function find_paths(adj, start, target; forbid_female=false, node_sex=Dict{String,String}())
    paths = Vector{Vector{Int}}()
    function dfs(cur, used, edgepath)
        if cur==target
            push!(paths, copy(edgepath)); return
        end
        for (nxt,ei) in get(adj,cur,Tuple{String,Int}[])
            nxt in used && continue
            if forbid_female && get(node_sex,nxt,"")=="female"
                continue
            end
            push!(used,nxt); push!(edgepath,ei)
            dfs(nxt,used,edgepath)
            pop!(edgepath); delete!(used,nxt)
        end
    end
    dfs(start,Set([start]),Int[])
    paths
end

function find_paths_with_nodes(
    adj,
    start::String,
    target::String;
    can_enter::Function = (_ -> true),
)
    paths = NamedTuple{
        (:node_path, :edge_path),
        Tuple{Vector{String},Vector{Int}},
    }[]

    function dfs(cur, used, node_path, edge_path)
        if cur == target
            push!(paths, (
                node_path = copy(node_path),
                edge_path = copy(edge_path),
            ))
            return
        end

        for (next_node, edge_index) in get(adj, cur, Tuple{String,Int}[])
            next_node in used && continue
            can_enter(next_node) || continue

            push!(used, next_node)
            push!(node_path, next_node)
            push!(edge_path, edge_index)

            dfs(next_node, used, node_path, edge_path)

            pop!(edge_path)
            pop!(node_path)
            delete!(used, next_node)
        end
    end

    dfs(start, Set([start]), String[start], Int[])
    return paths
end

# 皇族と判断できるが、父系祖先が史料上不詳のため
# 神武天皇までの純父系経路をデータとして構築できない人物。
# lineage_scope=imperial は維持し、一般的な「祖先ノード不足」警告から除外する。
const IMPERIAL_PATRILINEAGE_UNRESOLVED = Dict(
    "p_nukata" => "額田王は『日本書紀』に鏡王の娘とみえるが、父・鏡王の系譜は不詳。姫王の称から皇族とみる説明があるためimperialを維持する。",
)

function audit_lineage_scope(nodes, edges)
    errors = String[]
    warnings = String[]

    node_type, node_sex, adj = build_graph(nodes, edges)
    node_scope = Dict(
        cell_string(row.id) => cell_string(row.lineage_scope)
        for row in eachrow(nodes)
    )

    # imperial女性について、神武天皇から本人までの
    # 皇室・皇族内の純父系経路が存在するかを確認する。
    for row in eachrow(nodes)
        id = cell_string(row.id)
        sex = cell_string(row.sex)
        scope = cell_string(row.lineage_scope)

        sex == "female" || continue

        upstream_paths = find_paths_with_nodes(
            adj,
            CONFIG.root_id,
            id;
            can_enter = next_id -> (
                get(node_type, next_id, "") == "marriage" ||
                (
                    get(node_scope, next_id, "") == "imperial" &&
                    (
                        next_id == id ||
                        get(node_sex, next_id, "") == "male"
                    )
                )
            ),
        )

        if scope == "imperial" && isempty(upstream_paths)
            if haskey(IMPERIAL_PATRILINEAGE_UNRESOLVED, id)
                # 史料上の父系祖先未詳を監査済み。lineage_scopeは変更しない。
            else
                push!(
                    warnings,
                    "lineage_scope監査: imperial女性 $(id) へ神武天皇から皇室・皇族内の純父系経路がありません。祖先ノード・父子エッジ・lineage_scopeの不足を確認してください。",
                )
            end
        elseif scope in ("non_imperial", "granted_clan", "claimed") && !isempty(upstream_paths)
            push!(
                errors,
                "lineage_scope監査: $(scope)女性 $(id) に、神武天皇から皇室・皇族内の純父系経路が存在します。lineage_scopeの誤指定を確認してください。",
            )
        end
    end

    # 父系祖先未詳の監査済み例外自体もデータ整合を確認する。
    for (id, reason) in IMPERIAL_PATRILINEAGE_UNRESOLVED
        if !haskey(node_scope, id)
            push!(errors, "lineage_scope監査: 父系祖先未詳の例外 $(id) がnodesにありません。")
            continue
        end
        get(node_scope, id, "") == "imperial" || push!(
            errors,
            "lineage_scope監査: 父系祖先未詳の例外 $(id) は lineage_scope=imperial でなければなりません。",
        )
        get(node_sex, id, "") == "female" || push!(
            errors,
            "lineage_scope監査: 父系祖先未詳の例外 $(id) は female でなければなりません。",
        )
    end

    # main_blue上の人物はすべてimperialでなければならない。
    main_paths = find_paths_with_nodes(
        adj,
        CONFIG.root_id,
        CONFIG.current_emperor_id;
        can_enter = id -> get(node_sex, id, "") != "female",
    )

    if length(main_paths) == 1
        for id in only(main_paths).node_path
            get(node_type, id, "") == "marriage" && continue
            get(node_scope, id, "") != "imperial" &&
                push!(
                    errors,
                    "lineage_scope監査: main_blue上の人物 $(id) が lineage_scope=$(get(node_scope, id, "")) です。imperialでなければなりません。",
                )
        end
    end

    return errors, warnings
end

function determine_styles(nodes, edges)
    node_type, node_sex, adj = build_graph(nodes, edges)
    node_scope = Dict(
        cell_string(row.id) => cell_string(row.lineage_scope)
        for row in eachrow(nodes)
    )

    route_warnings = String[]

    # --------------------------------------------------------
    # main_blue:
    # 神武天皇から今上天皇へ至る、女性人物を通らない唯一の経路
    # --------------------------------------------------------
    main_paths = find_paths_with_nodes(
        adj,
        CONFIG.root_id,
        CONFIG.current_emperor_id;
        can_enter = id -> get(node_sex, id, "") != "female",
    )

    length(main_paths) == 1 ||
        error("main_blue候補経路は1本である必要があります。検出=$(length(main_paths))")

    main_path = only(main_paths)
    blue_edges = Set(main_path.edge_path)
    blue_nodes = Set(main_path.node_path)

    # --------------------------------------------------------
    # female_purple:
    #
    # 次の条件をすべて満たす女性を「男系女子」として抽出する。
    #
    # 1. 神武天皇からその女性本人まで、
    #    中間の人物がすべて男性である血縁経路が存在する。
    # 2. その女性本人から今上天皇まで、
    #    以後に別の女性人物を介さない血縁経路が存在する。
    # 3. 養子・猶子は血縁経路に含めない。
    #
    # 紫にする範囲は、
    # 上流側で男系を遡ってmain_blueへ接続する歴代天皇から、
    # 下流側でmain_blueへ再接続する地点までのうち、
    # main_blueと重複しない線とする。
    # --------------------------------------------------------
    purple_edges = Set{Int}()

    female_routes = NamedTuple{
        (:female_id, :anchor_id, :rejoin_id, :node_path, :edge_path, :purple_edge_path),
        Tuple{String,String,String,Vector{String},Vector{Int},Vector{Int}},
    }[]

    female_ids = sort([
        cell_string(row.id)
        for row in eachrow(nodes)
        if cell_string(row.sex) == "female" &&
           cell_string(row.lineage_scope) == "imperial"
    ])

    for female_id in female_ids
        # 神武天皇 → 男系男子のみ → 当該女性
        upstream_paths = find_paths_with_nodes(
            adj,
            CONFIG.root_id,
            female_id;
            can_enter = id -> (
                get(node_type, id, "") == "marriage" ||
                (
                    get(node_scope, id, "") == "imperial" &&
                    (
                        id == female_id ||
                        get(node_sex, id, "") == "male"
                    )
                )
            ),
        )

        isempty(upstream_paths) && continue

        # 当該女性 → 男子のみ → 今上天皇
        downstream_paths = find_paths_with_nodes(
            adj,
            female_id,
            CONFIG.current_emperor_id;
            can_enter = id -> (
                get(node_type, id, "") == "marriage" ||
                get(node_sex, id, "") == "male"
            ),
        )

        isempty(downstream_paths) && continue

        candidates = NamedTuple[]

        for upstream in upstream_paths
            # 上流接続点は、当該女性へ至る経路上で最後に現れる
            # main_blue上の「歴代天皇」とする。
            anchor_indices = [
                i for (i, id) in enumerate(upstream.node_path)
                if id in blue_nodes && get(node_type, id, "") == "tenno"
            ]
            isempty(anchor_indices) && continue
            anchor_index = last(anchor_indices)
            anchor_id = upstream.node_path[anchor_index]

            for downstream in downstream_paths
                # 女性本人より下流で最初にmain_blueへ再接続する地点。
                rejoin_indices = [
                    i for (i, id) in enumerate(downstream.node_path)
                    if i > 1 && id in blue_nodes
                ]
                isempty(rejoin_indices) && continue
                rejoin_index = first(rejoin_indices)
                rejoin_id = downstream.node_path[rejoin_index]

                upstream_segment_nodes = upstream.node_path[anchor_index:end]
                upstream_segment_edges = upstream.edge_path[anchor_index:end]

                downstream_segment_nodes = downstream.node_path[1:rejoin_index]
                downstream_segment_edges = downstream.edge_path[1:rejoin_index-1]

                combined_nodes = vcat(
                    upstream_segment_nodes,
                    downstream_segment_nodes[2:end],
                )
                combined_edges = vcat(
                    upstream_segment_edges,
                    downstream_segment_edges,
                )

                alternate_edges = [
                    edge_index
                    for edge_index in combined_edges
                    if !(edge_index in blue_edges)
                ]

                isempty(alternate_edges) && continue

                push!(candidates, (
                    female_id = female_id,
                    anchor_id = anchor_id,
                    rejoin_id = rejoin_id,
                    node_path = combined_nodes,
                    edge_path = combined_edges,
                    purple_edge_path = alternate_edges,
                ))
            end
        end

        isempty(candidates) && continue

        # 同一女性に複数候補がある場合は、
        # まず紫区間が最短、次に全区間が最短の経路を代表にする。
        sort!(
            candidates;
            by = route -> (
                length(route.purple_edge_path),
                length(route.edge_path),
                join(route.node_path, "|"),
            ),
        )

        selected = first(candidates)
        push!(female_routes, selected)
        union!(purple_edges, selected.purple_edge_path)

        if length(candidates) > 1
            push!(
                route_warnings,
                "男系女子 $(female_id) には有効経路が $(length(candidates)) 本あります。最短の紫区間を代表経路として採用しました。",
            )
        end
    end

    # --------------------------------------------------------
    # 最終スタイル
    #
    # bloodline_orange:
    # main_blue / female_purple では表現されない、歴代天皇から
    # 現皇統へ系譜上流入する別の血縁経路を示す補助線。
    # 同一天皇から複数の流入経路がある場合も省略せず表示する。
    # main_blue / female_purple と共有するエッジでは既存色を優先し、
    # orange は共有部へ合流する直前まで style_override で明示する。
    #
    # modern_inflow_green:
    # 明治天皇以降の皇室本流の男系女子を介して、
    # 旧宮家へ流入した近代の血縁強化線。
    # 竹田宮・北白川宮・朝香宮・東久邇宮を主対象とし、
    # 緑の太破線で表示する。
    #
    # style_overrideがある場合だけ自動判定を上書きする。
    # --------------------------------------------------------
    styles = String[]

    for (i, row) in enumerate(eachrow(edges))
        override = cell_string(row.style_override)
        relation = cell_string(row.relation)

        if !isempty(override)
            push!(styles, override)
        elseif relation in ("yushi", "adoption")
            push!(styles, "yushi")
        elseif relation == "layout_hint"
            push!(styles, "layout_hint")
        elseif i in blue_edges
            push!(styles, "main_blue")
        elseif i in purple_edges
            push!(styles, "female_purple")
        else
            push!(styles, "default")
        end
    end

    return styles, female_routes, route_warnings
end

function node_class(typ, sex="")
    typ_s = String(typ)
    sex_s = String(sex)

    if typ_s == "imperial_descendant"
        return sex_s == "female" ? "princesses" : "princes"
    end

    return Dict(
        "tenno"=>"tennos","female_tenno"=>"femaleTennos",
        "prince"=>"princes","princess"=>"princesses",
        "civil_prince"=>"princes","civil_princess"=>"civilPrincesses",
        "marriage"=>"marriageNode"
    )[typ_s]
end

const FORMER_SUBJECT_ROUTE_NODE_IDS = Set([
    "c_omimifune",
    "n_omimifune_daughter",
    "c_tachibana_shimadamaro",
    "c_tachibana_tsunenushi",
    "c_tachibana_yasukio",
    "c_tachibana_yoshimoto",
    "c_tachibana_sumikiyo",
    "n_tachibana_sumikiyo_daughter",
    "c_fujiwara_nakamasa",
    "n_fujiwara_tokihime",
    "c_fujiwara_kaneie",
    "n_fujiwara_senshi",
    "c_ariwara_narihira",
    "n_ariwara_miko",
    "c_fujiwara_yasunori",
    "c_fujiwara_kiyotsura",
    "n_fujiwara_kiyotsura_daughter",
    "c_fujiwara_tsunesuke",
    "c_fujiwara_yasutada",
    "n_minamoto_kiyoto_daughter",
    "c_fujiwara_kunimasa",
    "n_minamoto_nin_daughter",
    "c_fujiwara_kunitsune",
    "c_fujiwara_yukifusa",
    "n_fujiwara_yukifusa_daughter",
    "c_fujiwara_munetada",
    "c_fujiwara_muneno",
    "n_fujiwara_muneno_daughter",
    "c_fujiwara_sueyuki",
    "c_fujiwara_sadayoshi",
    "n_fujiwara_sadayoshi_daughter",
    "c_mochiie_ieyuki",
    "c_mochiie_sada",
    "c_mochiie_motomori",
    "c_mochiie_motoyo",
    "c_mochiie_motokane",
    "c_mochiie_motokiyo",
    "c_mochiie_motochika",
    "n_mochiie_motochika_daughter",
    "c_tokudaiji_sanemori",
    "c_tokudaiji_kinari",
    "n_takakura_nagatoyo_daughter",
    "c_tokudaiji_saneatsu",
    "n_tokudaiji_ishiko",
    "c_konoe_hisamichi",
    "c_konoe_taneie",
    "n_hosokawa_takamoto_daughter",
    "c_konoe_sakihisa",
    "n_konoe_sakiko",
    "c_minamoto_yoshiari",
    "n_minamoto_akiko",
    "c_fujiwara_tadahira",
    "c_fujiwara_morosuke",
    "n_fujiwara_moriko",
    "n_fujiwara_anshi",
    "c_konoe_iemoto",
    "c_konoe_tsunehira",
    "c_konoe_mototsugu",
    "c_konoe_michitsugu",
    "c_konoe_kanetsugu",
    "c_konoe_tadatsugu",
    "c_konoe_fusatsugu",
    "c_konoe_masaie",
    "c_shirakawa_nobusane",
    "c_shirakawa_yasusuke",
    "c_shirakawa_akiyasu",
    "c_shirakawa_akihiro",
    "c_shirakawa_nakasuke",
    "c_shirakawa_narisuke",
    "c_shirakawa_sukemitsu",
    "c_shirakawa_sukekuni",
    "c_shirakawa_nariaki",
    "c_shirakawa_sukekiyo",
    "c_shirakawa_sukehide",
    "c_shirakawa_akikuni",
    "c_shirakawa_suketada",
    "n_shirakawa_toyoko",
    "c_hirohashi_kanesato",
    "c_hirohashi_tsunamitsu",
    "n_hirohashi_tsunamitsu_daughter",
    "c_hirohashi_morimitsu",
    "c_hirohashi_kanehide",
    "c_hirohashi_kunimitsu",
    "c_hirohashi_kanekatsu",
    "n_hirohashi_kanekatsu_daughter",
    "c_higuchi_nobutaka",
    "c_higuchi_nobuyasu",
    "c_higuchi_yasuhiro",
    "c_higuchi_motoyasu",
    "n_higuchi_nobuko",
    "c_nijo_harutaka",
    "c_kujo_hisatada",
    "c_kujo_michitaka",
    "n_noma_ikuko",
    "c_minamoto_tsunemoto",
    "c_minamoto_mitsunaka",
    "c_minamoto_yorimitsu",
    "c_minamoto_yorikuni",
    "n_minamoto_yorikuni_daughter",
    "c_fujiwara_tamefusa",
    "c_fujiwara_akitaka",
    "c_fujiwara_akiyori",
    "n_fujiwara_yuko",
    "c_taira_tokinobu",
    "c_takashina_tameyuki",
    "n_takashina_tameyuki_daughter",
    "c_fujiwara_kiyotsuna",
    "c_fujiwara_tadakiyo",
    "n_fujiwara_tadakiyo_daughter",
    "c_minamoto_tameyoshi",
    "c_minamoto_yoshitomo",
    "n_bomon_hime",
    "c_ichijo_yoshiyasu",
    "n_ichijo_masako",
    "c_saionji_kintsune",
    "c_saionji_saneuji",
    "n_shijo_sadako",
    "n_saionji_kisshi",
])

const FORMER_SUBJECT_ROUTE_UNION_IDS = Set([
    "u_goreizei_masumori_daughter",
    "u_mifune_daughter_shimadamaro",
    "u_sumikiyo_daughter_nakamasa",
    "u_kaneie_tokihime",
    "u_ariwara_miko_yasunori",
    "u_kiyotsura_daughter_tsunesuke",
    "u_yasutada_kiyoto_daughter",
    "u_kunimasa_minamoto_nin_daughter",
    "u_yukifusa_daughter_munetada",
    "u_muneno_daughter_sueyuki",
    "u_sadayoshi_daughter_ieyuki",
    "u_motochika_daughter_sanemori",
    "u_kinari_takakura_daughter",
    "u_ishiko_hisamichi",
    "u_taneie_hosokawa",
    # 臣籍側の最終人物から皇室へ再流入する婚姻等関係節点。
    # spouse_to_union の臣籍側edgeまでは bloodline_orange_dashed とし、
    # union_to_child 以後は既存の main_blue 等へ戻す。
    "u_enyu_senshi",
    "u_goyozei_sakiko",
    "u_tadahira_akiko",
    "u_morosuke_moriko",
    "u_murakami_anshi",
    "u_kameyama_princess_iemoto",
    "u_toyoko_kanesato",
    "u_tsunamitsu_daughter_morimitsu",
    "u_kanekatsu_daughter_nobutaka",
    "u_nobuko_harutaka",
    "u_michitaka_ikuko",
    "u_yorikuni_daughter_tamefusa",
    "u_yuko_tokinobu",
    "u_goshirakawa_shigeko",
    "u_tameyuki_daughter_kiyotsuna",
    "u_tadakiyo_daughter_tameyoshi",
    "u_bomon_yoshiyasu",
    "u_masako_kintsune",
    "u_saneuji_sadako",
    "u_gosaga_kisshi",
])

const POSTWAR_FORMER_IMPERIAL_PREFIXES = (
    "fushimi_", "kuni_", "higashikuni_", "kitashirakawa_", "takeda_",
    "kaya_", "asaka_", "yamashina_", "nashimoto_", "kanin_", "higashifushimi_",
)

# 1947年10月14日の11宮家皇籍離脱に伴い皇籍を離れた女性皇族。
# もともとの女性皇族（紫枠）という意味は維持し、枠線だけを破線化する。
# これにより、紫色の実線枠＝皇族として表示、紫色の破線枠＝1947年皇籍離脱対象、
# という既存の視覚言語を壊さず身分上の変化を示す。
const POSTWAR_FORMER_IMPERIAL_FEMALE_NODE_IDS = Set([
    "p_toshiko",       # 東久邇聡子（出生時：泰宮聡子内親王、のち稔彦王妃）
    "p_fusako_meiji",  # 北白川房子（出生時：周宮房子内親王、のち成久王妃）
    "p_shigeko",       # 東久邇成子（出生時：照宮成子内親王、のち盛厚王妃）
])

# 婚姻により皇族の身分を離れた内親王・女王。
# 皇族であったことを示す紫枠は維持し、婚姻後の身分を破線で示す。
# name は婚姻後の最終名、alias は皇族であった時の名とする。
# 1947年以前に臣籍降下した人物のうち、収録方針上の監査済み例外。
# 皇族として出生した履歴を持つ一方、臣籍降下後の身分を示すため破線枠とする。
const PRE1947_FORMER_IMPERIAL_NODE_IDS = Set([
    "higashifushimi_002",
])

const MARRIAGE_FORMER_IMPERIAL_FEMALE_NODE_IDS = Set([
    "p_kazuko", "p_atsuko", "p_takako", "p_sayako",
    "p_mako", "p_noriko", "p_ayako",
    "p_yasuko_mikasa", "p_masako_mikasa",
])

function is_former_imperial_status_node(row)::Bool
    id = cell_string(row.id)

    # 明治・昭和天皇皇女のうち、11宮家の一員として1947年10月14日に
    # 皇籍を離れた女性皇族。IDは p_ 系なので宮家接頭辞判定より先に扱う。
    id in POSTWAR_FORMER_IMPERIAL_FEMALE_NODE_IDS && return true
    id in MARRIAGE_FORMER_IMPERIAL_FEMALE_NODE_IDS && return true
    id in PRE1947_FORMER_IMPERIAL_NODE_IDS && return true

    any(startswith(id, prefix) for prefix in POSTWAR_FORMER_IMPERIAL_PREFIXES) || return false

    typ = cell_string(row.type)
    display_note = cell_string(row.display_note)
    note = cell_string(row.note)

    # 1947年10月14日に皇籍離脱した本人、またはその後の皇胤。
    # 皇族身分を示す枠と誤読されないよう、臣籍側橙経路人物と同じ破線枠にする。
    # 女性皇族は princesses class の紫色 stroke を保ったまま破線化される。
    return typ == "imperial_descendant" ||
           occursin("1947年皇籍離脱", display_note) ||
           occursin("1947年皇籍離脱", note)
end

function emit_special_node_styles!(io, selected_node_rows)
    selected_ids = Set(cell_string(row.id) for row in selected_node_rows)
    subject_route_ids = setdiff(intersect(FORMER_SUBJECT_ROUTE_NODE_IDS, selected_ids), IMPERIAL_CONSORT_REENTRY_NODE_IDS)
    former_imperial_status_ids = Set(
        cell_string(row.id) for row in selected_node_rows
        if is_former_imperial_status_node(row)
    )
    target_ids = sort!(collect(union(subject_route_ids, former_imperial_status_ids)))
    for id in target_ids
        println(io, "    style $(id) stroke-dasharray: 6 4")
    end
end

function edge_line(f,t,rel,label)
    lab=escape_html(label)
    if rel == "layout_hint"
        return "    $(f) ~~~ $(t)"
    elseif rel in ("yushi","adoption")
        isempty(lab) ? "    $(f) -.-> $(t)" : "    $(f) -. \"$(lab)\" .-> $(t)"
    else
        isempty(lab) ? "    $(f) --> $(t)" : "    $(f) -- \"$(lab)\" --> $(t)"
    end
end

const DIAGRAM_PROFILES = (
    full = (
        title = "皇統皇胤図 完全図",
        path = CONFIG.output_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    overview = (
        title = "皇統皇胤図 全体図",
        path = CONFIG.overview_path,
        show_alias = false,
        show_note = false,
        show_life_years = false,
        direction = CONFIG.direction,
        use_subgraphs = false,
    ),
    former_houses = (
        title = "皇統皇胤図 宮家系統総覧",
        path = CONFIG.former_houses_path,
        show_alias = false,
        show_note = false,
        show_life_years = false,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    kuni = (
        title = "久邇宮詳細図",
        path = CONFIG.kuni_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    higashikuni = (
        title = "東久邇宮詳細図",
        path = CONFIG.higashikuni_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    kitashirakawa = (
        title = "北白川宮詳細図",
        path = CONFIG.kitashirakawa_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    takeda = (
        title = "竹田宮詳細図",
        path = CONFIG.takeda_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    kaya = (
        title = "賀陽宮詳細図",
        path = CONFIG.kaya_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    asaka = (
        title = "朝香宮詳細図",
        path = CONFIG.asaka_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    yamashina = (
        title = "山階宮詳細図",
        path = CONFIG.yamashina_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    nashimoto = (
        title = "梨本宮詳細図",
        path = CONFIG.nashimoto_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    kanin = (
        title = "閑院宮詳細図",
        path = CONFIG.kanin_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    higashifushimi = (
        title = "東伏見宮詳細図",
        path = CONFIG.higashifushimi_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
    fushimi = (
        title = "伏見宮詳細図",
        path = CONFIG.fushimi_path,
        show_alias = true,
        show_note = true,
        show_life_years = true,
        direction = CONFIG.direction,
        use_subgraphs = true,
    ),
)

function add_edge_neighbors!(
    selected::Set{String},
    edges,
    seeds::Set{String};
    depth::Int=1,
)
    frontier = copy(seeds)

    for _ in 1:depth
        next_frontier = Set{String}()

        for row in eachrow(edges)
            from_id = cell_string(row.from)
            to_id = cell_string(row.to)

            if from_id in frontier && !(to_id in selected)
                push!(selected, to_id)
                push!(next_frontier, to_id)
            end

            if to_id in frontier && !(from_id in selected)
                push!(selected, from_id)
                push!(next_frontier, from_id)
            end
        end

        isempty(next_frontier) && break
        frontier = next_frontier
    end

    return selected
end

function add_marriage_context!(selected::Set{String}, nodes, edges)
    node_type = Dict(
        cell_string(row.id) => cell_string(row.type)
        for row in eachrow(nodes)
    )

    changed = true
    while changed
        changed = false

        # 選択済みの子が婚姻等関係節点から生まれている場合、婚姻等関係節点を追加する。
        for row in eachrow(edges)
            relation = cell_string(row.relation)
            from_id = cell_string(row.from)
            to_id = cell_string(row.to)

            if relation == "union_to_child" &&
               to_id in selected &&
               !(from_id in selected)
                push!(selected, from_id)
                changed = true
            end
        end

        # 選択済みの婚姻等関係節点について、その配偶者を追加する。
        for row in eachrow(edges)
            relation = cell_string(row.relation)
            from_id = cell_string(row.from)
            to_id = cell_string(row.to)

            if relation == "spouse_to_union" &&
               to_id in selected &&
               !(from_id in selected)
                push!(selected, from_id)
                changed = true
            end
        end

        # 婚姻等関係節点だけが孤立しないよう、選択済み配偶者から婚姻等関係節点も補う。
        for row in eachrow(edges)
            relation = cell_string(row.relation)
            from_id = cell_string(row.from)
            to_id = cell_string(row.to)

            if relation == "spouse_to_union" &&
               from_id in selected &&
               get(node_type, to_id, "") == "marriage" &&
               !(to_id in selected)
                # 子が選択済みの婚姻等関係節点だけを採用し、不要な配偶関係の拡散を防ぐ。
                has_selected_child = any(
                    cell_string(e.from) == to_id &&
                    cell_string(e.relation) == "union_to_child" &&
                    cell_string(e.to) in selected
                    for e in eachrow(edges)
                )

                if has_selected_child
                    push!(selected, to_id)
                    changed = true
                end
            end
        end
    end

    return selected
end

function add_modern_imperial_family!(
    selected::Set{String},
    nodes,
    edges;
    root_id::String="t124",
)
    # overview の近現代部分は「グラフ距離」ではなく家族単位で表示する。
    #
    # 昭和天皇を起点として、
    #   1. 男系男子本人
    #   2. その配偶者
    #   3. その全ての子
    # を表示し、男子について同じ処理を再帰する。
    #
    # これにより、
    #   昭和天皇 → 上皇・常陸宮・内親王4名
    #   上皇     → 今上天皇・秋篠宮・紀宮
    #   今上天皇 → 敬宮
    #   秋篠宮   → 眞子・佳子・悠仁
    # が対称的に overview に含まれる。
    #
    # 女性皇族の婚姻先・子孫へは、この規則からは展開しない。

    node_sex = Dict(
        cell_string(row.id) => cell_string(row.sex)
        for row in eachrow(nodes)
    )
    node_scope = Dict(
        cell_string(row.id) => cell_string(row.lineage_scope)
        for row in eachrow(nodes)
    )

    push!(selected, root_id)

    frontier = Set([root_id])
    processed = Set{String}()

    while !isempty(frontier)
        person_id = pop!(frontier)
        person_id in processed && continue
        push!(processed, person_id)

        # 男系男子本人から出る婚姻等関係節点を探す。
        unions = Set{String}()
        for row in eachrow(edges)
            if cell_string(row.relation) == "spouse_to_union" &&
               cell_string(row.from) == person_id
                push!(unions, cell_string(row.to))
            end
        end

        for union_id in unions
            push!(selected, union_id)

            # 配偶者を含める。
            for row in eachrow(edges)
                if cell_string(row.relation) == "spouse_to_union" &&
                   cell_string(row.to) == union_id
                    push!(selected, cell_string(row.from))
                end
            end

            # 子は男女とも全員含める。
            for row in eachrow(edges)
                if cell_string(row.relation) != "union_to_child" ||
                   cell_string(row.from) != union_id
                    continue
                end

                child_id = cell_string(row.to)
                push!(selected, child_id)

                # 男系男子だけ次世代の家族展開を続ける。
                if get(node_sex, child_id, "") == "male" &&
                   get(node_scope, child_id, "") == "imperial"
                    push!(frontier, child_id)
                end
            end
        end
    end

    return selected
end

function add_overview_patrilineal_bridges!(
    selected::Set{String},
    nodes,
    edges,
)
    # overview では歴代天皇を広く表示するが、
    # 天皇どうしの間に「非天皇の父系中間人物」がいると、
    # その人物が抽出されずに天皇ノードだけが浮いて見えることがある。
    #
    # 例:
    #   40 天武天皇 → 舎人親王 → 47 淳仁天皇
    #   82 後鳥羽天皇 → 守貞親王 → 86 後堀河天皇 → 87 四条天皇
    #
    # そこで overview に表示される天皇について、
    # 父が非天皇ノードなら、既に表示されている直近の祖先へ至るまでの
    # 必要な父系中間ノードを自動的に補う。

    node_type = Dict(
        cell_string(row.id) => cell_string(row.type)
        for row in eachrow(nodes)
    )
    node_sex = Dict(
        cell_string(row.id) => cell_string(row.sex)
        for row in eachrow(nodes)
    )
    node_scope = Dict(
        cell_string(row.id) => cell_string(row.lineage_scope)
        for row in eachrow(nodes)
    )

    # biological_parent による父系親を引けるようにする。
    child_to_fathers = Dict{String, Vector{String}}()
    for row in eachrow(edges)
        if cell_string(row.relation) != "biological_parent"
            continue
        end

        from_id = cell_string(row.from)
        to_id = cell_string(row.to)

        if get(node_sex, from_id, "") == "male" &&
           get(node_scope, from_id, "") == "imperial"
            push!(get!(child_to_fathers, to_id, String[]), from_id)
        end
    end

    emperor_ids = [
        id for id in selected
        if get(node_type, id, "") in ("tenno", "female_tenno")
    ]

    for emperor_id in emperor_ids
        current_id = emperor_id
        bridge_nodes = String[]
        visited = Set{String}()

        while true
            current_id in visited && break
            push!(visited, current_id)

            fathers = get(child_to_fathers, current_id, String[])
            isempty(fathers) && break

            # ふつうは1人のはずだが、複数あれば先頭を使う。
            father_id = fathers[1]

            if father_id in selected
                # すでに表示済みの祖先へ接続できたので、
                # そこまでの中間ノードだけを追加する。
                for id in bridge_nodes
                    push!(selected, id)
                end
                break
            end

            # 父が非天皇なら bridge 候補として保持し、さらに上へ遡る。
            # 父が天皇でも未選択なら、その上流に選択済み祖先がある場合に備えて
            # 中間ノードとして保持してよい。
            push!(bridge_nodes, father_id)
            current_id = father_id
        end
    end

    return selected
end

function select_profile_nodes(profile_name::Symbol, nodes, edges, styles)
    all_ids = Set(cell_string(row.id) for row in eachrow(nodes))
    profile_name == :full && return all_ids

    selected = Set{String}()

    if profile_name == :overview
        # 歴代天皇・北朝天皇。
        for row in eachrow(nodes)
            typ = cell_string(row.type)
            id = cell_string(row.id)
            if typ in ("tenno", "female_tenno")
                push!(selected, id)
            end
        end

        # 青線・紫線・養子猶子線に関係する全ノード。
        for (i, row) in enumerate(eachrow(edges))
            if styles[i] in ("main_blue", "female_purple", "bloodline_orange", "bloodline_orange_dashed", "yushi")
                push!(selected, cell_string(row.from))
                push!(selected, cell_string(row.to))
            end
        end

        # 主要宮家の分岐点。
        union!(
            selected,
            Set([
                "fushimi_020",
                "kuni_001",
                "higashikuni_001",
                "kitashirakawa_001",
                "takeda_001",
                "kaya_001",
                "asaka_001",
                "yamashina_001",
                "nashimoto_002",
                "kanin_006",
                "higashifushimi_001",
            ]),
        )

        # 近現代皇室はグラフ距離ではなく家族単位で表示する。
        #
        # 昭和天皇を起点に、男系男子について
        # 「本人＋配偶者＋全ての子」を再帰的に展開する。
        # 女性皇族の婚姻先・子孫には展開しない。
        add_modern_imperial_family!(selected, nodes, edges; root_id="t124")

        # 歴代天皇の表示に必要な父系中間人物を自動補完する。
        add_overview_patrilineal_bridges!(selected, nodes, edges)

    elseif profile_name == :former_houses
        for row in eachrow(nodes)
            id = cell_string(row.id)
            if startswith(id, "fushimi_") ||
               startswith(id, "kuni_") ||
               startswith(id, "higashikuni_") ||
               startswith(id, "kitashirakawa_") ||
               startswith(id, "takeda_") ||
               startswith(id, "kaya_") ||
               startswith(id, "asaka_") ||
               startswith(id, "yamashina_") ||
               startswith(id, "nashimoto_") ||
               id in ("kanin_006", "kanin_007") ||
               startswith(id, "higashifushimi_")
                push!(selected, id)
            end
        end

        union!(
            selected,
            Set([
                "tn003",
                "t102",
                "t122",
                "t124",
                "p_toshiko",
                "p_shigeko",
                "p_masako_meiji",
                "u_tsunehisa_masako",
                "p_fusako_meiji",
                "u_naruhisa_fusako",
                "p_nobuko_meiji",
                "u_yasuhiko_nobuko",
            ]),
        )

    elseif profile_name == :kuni
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "kuni_") && push!(selected, id)
        end

        union!(
            selected,
            Set([
                "fushimi_020",
                "t124",
                "u_showa_nagako",
                "higashikuni_001",
            ]),
        )

    elseif profile_name == :higashikuni
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "higashikuni_") && push!(selected, id)
        end

        union!(
            selected,
            Set([
                "kuni_001",
                "t122",
                "t124",
                "p_toshiko",
                "p_shigeko",
                "u_naruhiko_toshiko",
                "u_morihiro_shigeko",
            ]),
        )

    elseif profile_name == :kitashirakawa
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "kitashirakawa_") && push!(selected, id)
        end

        union!(
            selected,
            Set([
                "fushimi_020",
                "t122",
                "p_fusako_meiji",
                "u_naruhisa_fusako",
                "takeda_001",
            ]),
        )

    elseif profile_name == :takeda
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "takeda_") && push!(selected, id)
        end

        union!(
            selected,
            Set([
                "kitashirakawa_001",
                "t122",
                "p_masako_meiji",
                "u_tsunehisa_masako",
            ]),
        )

    elseif profile_name == :kaya
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "kaya_") && push!(selected, id)
        end
        push!(selected, "kuni_001")

    elseif profile_name == :asaka
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "asaka_") && push!(selected, id)
        end

        union!(
            selected,
            Set([
                "kuni_001",
                "t122",
                "p_nobuko_meiji",
                "u_yasuhiko_nobuko",
            ]),
        )

    elseif profile_name == :yamashina
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "yamashina_") && push!(selected, id)
        end
        push!(selected, "fushimi_020")

    elseif profile_name == :nashimoto
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "nashimoto_") && push!(selected, id)
        end
        push!(selected, "kuni_001")

    elseif profile_name == :kanin
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "kanin_") && push!(selected, id)
        end

        # 古い閑院宮系の起点（東山天皇）と、
        # 明治期再興系統の実父（伏見宮邦家親王）を両方表示する。
        union!(selected, Set(["t113", "t119", "fushimi_020"]))

    elseif profile_name == :higashifushimi
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "higashifushimi_") && push!(selected, id)
        end
        push!(selected, "fushimi_020")

    elseif profile_name == :fushimi
        for row in eachrow(nodes)
            id = cell_string(row.id)
            startswith(id, "fushimi_") && push!(selected, id)
        end

        # 起点の崇光天皇、伏見宮から皇位へ出た後花園天皇、
        # 途中で伏見宮を継承した貞行親王の実父・桃園天皇、
        # および梨本宮初代への分岐を表示する。
        union!(
            selected,
            Set([
                "tn003",
                "t102",
                "t116",
                "nashimoto_001",
                "shogoin_001",
                "komatsu_001",
                "kacho_001",
            ]),
        )

    else
        error("未対応の図プロファイルです: $(profile_name)")
    end

    intersect!(selected, all_ids)
    add_marriage_context!(selected, nodes, edges)
    return selected
end


const REMAINING_ROYAL_OUTER_IDS = Set([
    "n_sadako",
    "t124", "kuni_003",
    "p_yasuhito", "n_setsuko",
    "p_nobuhito", "n_kikuko",
    "p_takahito", "n_yuriko",
    "p_yasuko_mikasa", "c_konoe_tadateru", "u_yasuko_tadateru",
    "p_masako_mikasa", "c_sen_soshitsu", "u_masako_soshitsu",
    "p_masahito_02", "n_hanako",
    "p_kazuko", "p_atsuko", "p_takako",
    "c_takatsukasa_toshimichi", "u_kazuko_toshimichi",
    "c_ikeda_takamasa", "u_atsuko_takamasa",
    "c_shimazu_hisanaga", "u_takako_hisanaga",
    "t125", "n_michiko",
    "t126", "n_masako", "p_aiko",
    "p_fumihito", "n_kiko", "p_mako", "p_kako", "p_hisahito", "p_sayako",
    "c_komuro_kei", "u_mako_kei", "c_kuroda_yoshiki", "u_sayako_yoshiki",
    "p_tomohito", "n_nobuko", "p_akiko", "p_yoko",
    "p_yoshihito",
    "p_norihito", "n_hisako", "p_tsuguko", "p_noriko", "p_ayako",
    "c_senge_kunimaro", "u_noriko_kunimaro", "c_moriya_kei", "u_ayako_kei",
    "u_taisho_sadako",
    "u_showa_nagako",
    "u_chichibu_setsuko",
    "u_takamatsu_kikuko",
    "u_mikasa_yuriko",
    "u_hitachi_hanako",
    "u_joko_michiko",
    "u_naruhito_masako",
    "u_akishino_kiko",
    "u_tomohito_nobuko",
    "u_norihito_hisako",
])

const HIGASHIKUNI_SUBGRAPH_CONTEXT_IDS = Set([
    "p_shigeko",
    "u_morihiro_shigeko",
    "n_yoshiko_terao",
    "u_morihiro_yoshiko",
])

const HOUSE_SPOUSE_SUBGRAPH_CONTEXT = Dict(
    "p_toshiko" => ("sg_full_higashikuni", "東久邇宮系"),
    "u_naruhiko_toshiko" => ("sg_full_higashikuni", "東久邇宮系"),
    "p_masako_meiji" => ("sg_full_takeda", "竹田宮系"),
    "u_tsunehisa_masako" => ("sg_full_takeda", "竹田宮系"),
    "p_nobuko_meiji" => ("sg_full_asaka", "朝香宮系"),
    "u_yasuhiko_nobuko" => ("sg_full_asaka", "朝香宮系"),
    "p_fusako_meiji" => ("sg_full_kitashirakawa", "北白川宮系"),
    "u_naruhisa_fusako" => ("sg_full_kitashirakawa", "北白川宮系"),
    "p_fukuko_reigen" => ("sg_full_fushimi", "伏見宮系"),
    "u_kuninaga_fukuko" => ("sg_full_fushimi", "伏見宮系"),
)

const REMAINING_ROYAL_INNER_GROUPS = Dict(
    "n_sadako" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "u_taisho_sadako" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "t124" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "kuni_003" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "u_showa_nagako" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "t125" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "n_michiko" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "u_joko_michiko" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "t126" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "n_masako" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "u_naruhito_masako" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "p_aiko" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "p_sayako" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "c_kuroda_yoshiki" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "u_sayako_yoshiki" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "p_kazuko" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "c_takatsukasa_toshimichi" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "u_kazuko_toshimichi" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "p_atsuko" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "c_ikeda_takamasa" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "u_atsuko_takamasa" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "p_takako" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "c_shimazu_hisanaga" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),
    "u_takako_hisanaga" => ("sg_remaining_mainline", "昭和天皇・上皇・今上天皇系"),

    "p_yasuhito" => ("sg_remaining_chichibu", "秩父宮系"),
    "n_setsuko" => ("sg_remaining_chichibu", "秩父宮系"),
    "u_chichibu_setsuko" => ("sg_remaining_chichibu", "秩父宮系"),

    "p_nobuhito" => ("sg_remaining_takamatsu", "高松宮系"),
    "n_kikuko" => ("sg_remaining_takamatsu", "高松宮系"),
    "u_takamatsu_kikuko" => ("sg_remaining_takamatsu", "高松宮系"),

    "p_takahito" => ("sg_remaining_mikasa", "三笠宮系"),
    "n_yuriko" => ("sg_remaining_mikasa", "三笠宮系"),
    "u_mikasa_yuriko" => ("sg_remaining_mikasa", "三笠宮系"),
    "p_yasuko_mikasa" => ("sg_remaining_mikasa", "三笠宮系"),
    "c_konoe_tadateru" => ("sg_remaining_mikasa", "三笠宮系"),
    "u_yasuko_tadateru" => ("sg_remaining_mikasa", "三笠宮系"),
    "p_masako_mikasa" => ("sg_remaining_mikasa", "三笠宮系"),
    "c_sen_soshitsu" => ("sg_remaining_mikasa", "三笠宮系"),
    "u_masako_soshitsu" => ("sg_remaining_mikasa", "三笠宮系"),
    "p_tomohito" => ("sg_remaining_mikasa", "三笠宮系"),
    "n_nobuko" => ("sg_remaining_mikasa", "三笠宮系"),
    "u_tomohito_nobuko" => ("sg_remaining_mikasa", "三笠宮系"),
    "p_akiko" => ("sg_remaining_mikasa", "三笠宮系"),
    "p_yoko" => ("sg_remaining_mikasa", "三笠宮系"),

    "p_yoshihito" => ("sg_remaining_katsura", "桂宮系"),

    "p_norihito" => ("sg_remaining_takamado", "高円宮系"),
    "n_hisako" => ("sg_remaining_takamado", "高円宮系"),
    "u_norihito_hisako" => ("sg_remaining_takamado", "高円宮系"),
    "p_tsuguko" => ("sg_remaining_takamado", "高円宮系"),
    "p_noriko" => ("sg_remaining_takamado", "高円宮系"),
    "c_senge_kunimaro" => ("sg_remaining_takamado", "高円宮系"),
    "u_noriko_kunimaro" => ("sg_remaining_takamado", "高円宮系"),
    "p_ayako" => ("sg_remaining_takamado", "高円宮系"),
    "c_moriya_kei" => ("sg_remaining_takamado", "高円宮系"),
    "u_ayako_kei" => ("sg_remaining_takamado", "高円宮系"),

    "p_masahito_02" => ("sg_remaining_hitachi", "常陸宮系"),
    "n_hanako" => ("sg_remaining_hitachi", "常陸宮系"),
    "u_hitachi_hanako" => ("sg_remaining_hitachi", "常陸宮系"),

    "p_fumihito" => ("sg_remaining_akishino", "秋篠宮系"),
    "n_kiko" => ("sg_remaining_akishino", "秋篠宮系"),
    "u_akishino_kiko" => ("sg_remaining_akishino", "秋篠宮系"),
    "p_mako" => ("sg_remaining_akishino", "秋篠宮系"),
    "c_komuro_kei" => ("sg_remaining_akishino", "秋篠宮系"),
    "u_mako_kei" => ("sg_remaining_akishino", "秋篠宮系"),
    "p_kako" => ("sg_remaining_akishino", "秋篠宮系"),
    "p_hisahito" => ("sg_remaining_akishino", "秋篠宮系"),

)

function remaining_royal_inner_group(id::String)
    return get(REMAINING_ROYAL_INNER_GROUPS, id, ("", ""))
end

function profile_subgraph(profile_name::Symbol, id::String)
    if profile_name == :full
        # full はデータを省略せず、視覚的な「所属」だけを付与する。
        #
        # 現在は、旧宮家系の枝分かれ subgraph に加え、
        # 1947年10月14日の11宮家皇籍離脱後も皇室に残った系統を外枠でひとまとめにする。
        #
        # この外枠には、後年に婚姻等で皇籍を離れた内親王・女王も含める。
        # 1947年以前に東久邇宮家へ婚姻し、同家とともに1947年に皇籍離脱した
        # 成子内親王、および盛厚の再婚相手・寺尾佳子と両婚姻等関係節点は、
        # 血統・家系展開の連続性を優先して東久邇宮系に置く。
        id in HIGASHIKUNI_SUBGRAPH_CONTEXT_IDS &&
            return ("sg_full_higashikuni", "東久邇宮系")

        # 宮家妃とその婚姻等関係節点は、fullでは婚姻先の宮家枠を優先する。
        # これは視覚上の所属であり、出自や血縁情報を書き換えるものではない。
        if haskey(HOUSE_SPOUSE_SUBGRAPH_CONTEXT, id)
            return HOUSE_SPOUSE_SUBGRAPH_CONTEXT[id]
        end

        id in REMAINING_ROYAL_OUTER_IDS &&
            return (
                "sg_remaining_royal_outer",
                "1947年10月14日の11宮家皇籍離脱後も皇室に残った系統<br/>※後年に婚姻等で皇籍を離れた内親王・女王と、その関係表示に必要な婚姻相手を含む",
            )
        startswith(id, "tn") && return ("sg_full_north", "北朝系")
        startswith(id, "fushimi_") && return ("sg_full_fushimi", "伏見宮系")
        startswith(id, "kuni_") && return ("sg_full_kuni", "久邇宮系")
        startswith(id, "higashikuni_") && return ("sg_full_higashikuni", "東久邇宮系")
        startswith(id, "kitashirakawa_") && return ("sg_full_kitashirakawa", "北白川宮系")
        startswith(id, "takeda_") && return ("sg_full_takeda", "竹田宮系")
        startswith(id, "kaya_") && return ("sg_full_kaya", "賀陽宮系")
        startswith(id, "asaka_") && return ("sg_full_asaka", "朝香宮系")
        startswith(id, "yamashina_") && return ("sg_full_yamashina", "山階宮系")
        startswith(id, "nashimoto_") && return ("sg_full_nashimoto", "梨本宮系")
        startswith(id, "kanin_") && return ("sg_full_kanin", "閑院宮系")
        startswith(id, "higashifushimi_") && return ("sg_full_higashifushimi", "東伏見宮系")
        startswith(id, "shogoin_") && return ("sg_full_shogoin", "聖護院宮系")
        startswith(id, "komatsu_") && return ("sg_full_komatsu", "小松宮系")
        startswith(id, "kacho_") && return ("sg_full_kacho", "華頂宮系")
        return ("", "")
    elseif profile_name == :former_houses
        startswith(id, "fushimi_") && return ("sg_fushimi", "伏見宮系")
        startswith(id, "kuni_") && return ("sg_kuni", "久邇宮系")
        startswith(id, "higashikuni_") && return ("sg_higashikuni", "東久邇宮系")
        startswith(id, "kitashirakawa_") && return ("sg_kitashirakawa", "北白川宮系")
        startswith(id, "takeda_") && return ("sg_takeda", "竹田宮系")
        startswith(id, "kaya_") && return ("sg_kaya", "賀陽宮系")
        startswith(id, "asaka_") && return ("sg_asaka", "朝香宮系")
        startswith(id, "yamashina_") && return ("sg_yamashina", "山階宮系")
        startswith(id, "nashimoto_") && return ("sg_nashimoto", "梨本宮系")
        id in ("kanin_006", "kanin_007") && return ("sg_kanin", "閑院宮系")
        startswith(id, "higashifushimi_") && return ("sg_higashifushimi", "東伏見宮系")
        return ("", "")
    elseif profile_name == :kuni
        startswith(id, "kuni_") && return ("sg_kuni", "久邇宮系")
        id == "higashikuni_001" && return ("sg_higashikuni_branch", "東久邇宮への分岐")
        return ("", "")
    elseif profile_name == :higashikuni
        startswith(id, "higashikuni_") && return ("sg_higashikuni", "東久邇宮系")
        id == "kuni_001" && return ("sg_kuni_origin", "久邇宮からの分岐")
        return ("", "")
    elseif profile_name == :kitashirakawa
        startswith(id, "kitashirakawa_") && return ("sg_kitashirakawa", "北白川宮系")
        id in ("p_fusako_meiji", "u_naruhisa_fusako") &&
            return ("sg_meiji_marriage_kitashirakawa", "明治天皇皇女との婚姻")
        id == "takeda_001" && return ("sg_takeda_branch", "竹田宮への分岐")
        return ("", "")
    elseif profile_name == :takeda
        startswith(id, "takeda_") && return ("sg_takeda", "竹田宮系")
        id == "kitashirakawa_001" && return ("sg_kitashirakawa_origin", "北白川宮からの分岐")
        return ("", "")
    elseif profile_name == :kaya
        startswith(id, "kaya_") && return ("sg_kaya", "賀陽宮系")
        id == "kuni_001" && return ("sg_kuni_origin_kaya", "久邇宮からの分岐")
        return ("", "")
    elseif profile_name == :asaka
        startswith(id, "asaka_") && return ("sg_asaka", "朝香宮系")
        id == "kuni_001" && return ("sg_kuni_origin_asaka", "久邇宮からの分岐")
        return ("", "")
    elseif profile_name == :yamashina
        startswith(id, "yamashina_") && return ("sg_yamashina", "山階宮系")
        id == "fushimi_020" && return ("sg_fushimi_origin_yamashina", "伏見宮からの分岐")
        return ("", "")
    elseif profile_name == :nashimoto
        startswith(id, "nashimoto_") && return ("sg_nashimoto", "梨本宮系")
        id == "kuni_001" && return ("sg_kuni_origin_nashimoto", "久邇宮からの分岐")
        return ("", "")
    elseif profile_name == :kanin
        startswith(id, "kanin_") && return ("sg_kanin", "閑院宮系")
        id == "t113" && return ("sg_higashiyama_origin", "東山天皇からの創設")
        id == "fushimi_020" && return ("sg_fushimi_origin_kanin", "伏見宮から第6代を継承")
        return ("", "")
    elseif profile_name == :higashifushimi
        startswith(id, "higashifushimi_") && return ("sg_higashifushimi", "東伏見宮系")
        id == "fushimi_020" && return ("sg_fushimi_origin_higashifushimi", "伏見宮からの分岐")
        return ("", "")
    elseif profile_name == :fushimi
        startswith(id, "fushimi_") && return ("sg_fushimi", "伏見宮系")
        id == "tn003" && return ("sg_suko_origin", "崇光天皇からの分岐")
        id == "t116" && return ("sg_momozono_origin", "桃園天皇から貞行親王")
        id == "nashimoto_001" && return ("sg_nashimoto_branch", "梨本宮への分岐")
        id == "shogoin_001" && return ("sg_shogoin_branch", "聖護院宮への分岐")
        id == "komatsu_001" && return ("sg_komatsu_branch", "小松宮への分岐")
        id == "kacho_001" && return ("sg_kacho_branch", "華頂宮への分岐")
        return ("", "")
    end

    return ("", "")
end

function life_years_string(row)
    birth = cell_string(row.birth_year)
    death = cell_string(row.death_year)

    if !isempty(birth) || !isempty(death)
        isempty(birth) && return "?–$(death)"
        isempty(death) && return "$(birth)–"
        return "$(birth)–$(death)"
    end

    traditional = cell_string(row.traditional_life_years)
    isempty(traditional) && return ""
    return "$(traditional)（伝承紀年）"
end

function node_mermaid_line(row, profile)
    id = cell_string(row.id)
    typ = cell_string(row.type)

    if typ == "marriage"
        return "    $(id)(( )):::marriageNode"
    end

    parts = [escape_html(cell_string(row.name))]

    if profile.show_alias
        alias = cell_string(row.alias)
        !isempty(alias) && push!(parts, "(" * escape_html(alias) * ")")
    end

    if profile.show_life_years
        life_years = life_years_string(row)
        !isempty(life_years) && push!(parts, escape_html(life_years))
    end

    if profile.show_note
        display_note = cell_string(row.display_note)
        !isempty(display_note) && push!(parts, "※" * escape_html(display_note))
    end

    return "    $(id)[\"$(join(parts, "<br>"))\"]:::$(node_class(typ, cell_string(row.sex)))"
end


function audit_house_spouse_subgraph_membership(nodes, edges)
    rows = NamedTuple[]
    node_by_id = Dict(cell_string(row.id) => row for row in eachrow(nodes))

    # full 上の明示的な「宮家妃＋婚姻等関係節点」所属を監査する。
    for (id, group) in HOUSE_SPOUSE_SUBGRAPH_CONTEXT
        if !haskey(node_by_id, id)
            push!(rows, (
                level = "error",
                id = id,
                name = "",
                assigned_subgraph = group[2],
                issue = "HOUSE_SPOUSE_SUBGRAPH_CONTEXT に存在しないノードID",
            ))
            continue
        end

        row = node_by_id[id]
        typ = cell_string(row.type)

        if typ == "marriage"
            spouse_edges = filter(
                e -> cell_string(e.relation) == "spouse_to_union" &&
                     cell_string(e.to) == id,
                eachrow(edges),
            )
            if length(spouse_edges) != 2
                push!(rows, (
                    level = "warning",
                    id = id,
                    name = cell_string(row.name),
                    assigned_subgraph = group[2],
                    issue = "婚姻等関係節点の配偶者数が2ではない",
                ))
            else
                push!(rows, (
                    level = "ok",
                    id = id,
                    name = cell_string(row.name),
                    assigned_subgraph = group[2],
                    issue = "婚姻等関係節点を婚姻先宮家subgraphに配置",
                ))
            end
        else
            push!(rows, (
                level = "ok",
                id = id,
                name = cell_string(row.name),
                assigned_subgraph = group[2],
                issue = "宮家妃を婚姻先宮家subgraphに配置",
            ))
        end
    end

    return rows
end

function subgraph_style(profile_name::Symbol, group_id::String)
    if profile_name == :full && group_id == "sg_remaining_royal_outer"
        return "fill:#fff8d9,stroke:#c8ab52,stroke-width:2px,color:#333333;"
    end

    # 1947年10月14日の11宮家皇籍離脱後も皇室に残った系統の内側グループ。
    if profile_name == :full && startswith(group_id, "sg_remaining_") &&
       group_id != "sg_remaining_royal_outer"
        return "fill:#e8e8e8,fill-opacity:0.55,stroke:#a8a8a8,stroke-width:1.5px,color:#333333;"
    end

    # full の北朝系および各宮家系は Mermaid/VS Code/単独HTMLのテーマ差に
    # 依存させず、VS Code Light+ で見ていた従来の薄い灰色半透明背景へ固定する。
    if profile_name == :full && startswith(group_id, "sg_full_")
        return "fill:#e8e8e8,fill-opacity:0.55,stroke:#a8a8a8,stroke-width:1.5px,color:#333333;"
    end

    return ""
end

function write_profile_nodes!(
    io,
    profile_name::Symbol,
    profile,
    selected_node_rows,
)
    if !profile.use_subgraphs
        for row in selected_node_rows
            println(io, node_mermaid_line(row, profile))
        end
        return
    end

    # full の現皇室外枠だけは、
    # 外枠の内部にレイアウト専用の透明な宮系subgraphを入れ子にする。
    if profile_name == :full
        outer_group = (
            "sg_remaining_royal_outer",
            "1947年10月14日の11宮家皇籍離脱後も皇室に残った系統<br/>※後年に婚姻等で皇籍を離れた内親王・女王と、その関係表示に必要な婚姻相手を含む",
        )

        outside_rows = Any[]
        normal_grouped_rows = Dict{Tuple{String,String}, Vector{Any}}()
        normal_group_order = Tuple{String,String}[]
        outer_direct_rows = Any[]
        inner_grouped_rows = Dict{Tuple{String,String}, Vector{Any}}()
        inner_group_order = Tuple{String,String}[]

        for row in selected_node_rows
            id = cell_string(row.id)
            group = profile_subgraph(profile_name, id)

            if group == outer_group
                inner = remaining_royal_inner_group(id)
                if isempty(inner[1])
                    push!(outer_direct_rows, row)
                else
                    if !haskey(inner_grouped_rows, inner)
                        inner_grouped_rows[inner] = Any[]
                        push!(inner_group_order, inner)
                    end
                    push!(inner_grouped_rows[inner], row)
                end
            elseif isempty(group[1])
                push!(outside_rows, row)
            else
                if !haskey(normal_grouped_rows, group)
                    normal_grouped_rows[group] = Any[]
                    push!(normal_group_order, group)
                end
                push!(normal_grouped_rows[group], row)
            end
        end

        for row in outside_rows
            println(io, node_mermaid_line(row, profile))
        end

        # 黄枠以外の通常subgraph
        for (group_id, group_label) in normal_group_order
            println(io, "    subgraph $(group_id)[\"$(group_label)\"]")
            println(io, "        direction TB")
            for row in normal_grouped_rows[(group_id, group_label)]
                println(io, "    " * node_mermaid_line(row, profile))
            end
            println(io, "    end")
            style_rule = subgraph_style(profile_name, group_id)
            !isempty(style_rule) && println(io, "    style $(group_id) $(style_rule)")
        end

        # 1947年10月14日の11宮家皇籍離脱後も皇室に残った系統：黄色の大外枠
        if !isempty(outer_direct_rows) || !isempty(inner_group_order)
            println(io, "    subgraph $(outer_group[1])[\"$(outer_group[2])\"]")
            println(io, "        direction TB")

            # 宮系に属さない人物・婚姻等関係節点は外枠直下
            for row in outer_direct_rows
                println(io, "    " * node_mermaid_line(row, profile))
            end

            # 宮系は透明subgraphで配置だけをまとめる
            for (inner_id, inner_label) in inner_group_order
                println(io, "        subgraph $(inner_id)[\"$(inner_label)\"]")
                println(io, "            direction TB")
                for row in inner_grouped_rows[(inner_id, inner_label)]
                    println(io, "        " * node_mermaid_line(row, profile))
                end
                println(io, "        end")
                style_rule = subgraph_style(profile_name, inner_id)
                !isempty(style_rule) && println(io, "        style $(inner_id) $(style_rule)")
            end

            println(io, "    end")
            style_rule = subgraph_style(profile_name, outer_group[1])
            !isempty(style_rule) && println(io, "    style $(outer_group[1]) $(style_rule)")
        end
        return
    end

    # それ以外のプロファイルは従来どおり1階層subgraph。
    outside_rows = Any[]
    grouped_rows = Dict{Tuple{String,String}, Vector{Any}}()
    group_order = Tuple{String,String}[]

    for row in selected_node_rows
        id = cell_string(row.id)
        group = profile_subgraph(profile_name, id)

        if isempty(group[1])
            push!(outside_rows, row)
        else
            if !haskey(grouped_rows, group)
                grouped_rows[group] = Any[]
                push!(group_order, group)
            end
            push!(grouped_rows[group], row)
        end
    end

    for row in outside_rows
        println(io, node_mermaid_line(row, profile))
    end

    for (group_id, group_label) in group_order
        println(io, "    subgraph $(group_id)[\"$(group_label)\"]")
        println(io, "        direction TB")

        for row in grouped_rows[(group_id, group_label)]
            line = node_mermaid_line(row, profile)
            println(io, "    " * line)
        end

        println(io, "    end")
        style_rule = subgraph_style(profile_name, group_id)
        !isempty(style_rule) && println(io, "    style $(group_id) $(style_rule)")
    end
end

function emit_public_legend!(io, profile_name::Symbol)
    profile_name == :full || return

    println(io)
    # 公開用凡例。背景は透明、全体のみ角丸枠で囲い、各説明ノード枠は表示しない。
    println(io, "    subgraph public_legend[\"凡例\"]")
    println(io, "        direction LR")
    println(io, "        subgraph legend_lines[\"系譜線\"]")
    println(io, "            direction TB")
    println(io, "            lg_blue[\"━━▶ 青太線：神武天皇から今上天皇に至る男系男子の系譜経路\"]")
    println(io, "            lg_purple[\"━━▶ 紫太線：男系でつながる皇族女性を経由し、現皇統へ至る系譜経路\"]")
    println(io, "            lg_orange[\"━━▶ 橙太実線：青・紫では表れない補完系譜の皇室・皇親側区間\"]")
    println(io, "            lg_orange_dash[\"┅┅▶ 橙太破線：臣籍等を経由する補完系譜区間\"]")
    println(io, "            lg_green[\"┅┅▶ 緑太破線：明治天皇以降の皇女を介して旧宮家へつながる近代系譜\"]")
    println(io, "            lg_yushi[\"┅┅▶ 灰破線：養子・猶子・実親子とは別に扱われた親子関係等\"]")
    println(io, "            lg_default[\"──▶ 灰細線：その他の系譜上の親子関係\"]")
    println(io, "        end")
    println(io, "        subgraph legend_symbols[\"人物・記号\"]")
    println(io, "            direction TB")
    println(io, "            lg_union[\"● 婚姻等関係節点：婚姻・后妃・側室等の関係を結節によって示す節点\"]")
    println(io, "            lg_postwar[\"破線枠：臣籍の人物・皇籍離脱後の人物\"]")
    println(io, "            lg_purple_border[\"紫枠：女性天皇・皇族女性など、本図で皇室・皇親側として扱う女性\"]")
    println(io, "            lg_red_border[\"赤枠：皇室外から系譜に入る女性（后妃等）\"]")
    println(io, "            lg_traditional[\"（伝承紀年）：記紀等に基づく伝承上の年代\"]")
    println(io, "            lg_unknown[\"?：年代不詳または確定できないもの\"]")
    println(io, "        end")
    println(io, "    end")

    println(io, "    style public_legend fill:transparent,stroke:#888888,stroke-width:1.5px,rx:12px,ry:12px")
    println(io, "    style legend_lines fill:transparent,stroke:transparent,stroke-width:0px")
    println(io, "    style legend_symbols fill:transparent,stroke:transparent,stroke-width:0px")
    println(io, "    style lg_blue fill:transparent,stroke:transparent,stroke-width:0px,color:#0055a5")
    println(io, "    style lg_purple fill:transparent,stroke:transparent,stroke-width:0px,color:#7a378b")
    println(io, "    style lg_orange fill:transparent,stroke:transparent,stroke-width:0px,color:#d97706")
    println(io, "    style lg_orange_dash fill:transparent,stroke:transparent,stroke-width:0px,color:#d97706")
    println(io, "    style lg_green fill:transparent,stroke:transparent,stroke-width:0px,color:#2f855a")
    println(io, "    style lg_yushi fill:transparent,stroke:transparent,stroke-width:0px,color:#555555")
    println(io, "    style lg_default fill:transparent,stroke:transparent,stroke-width:0px,color:#444444")
    println(io, "    style lg_union fill:transparent,stroke:transparent,stroke-width:0px,color:#222222")
    println(io, "    style lg_postwar fill:transparent,stroke:transparent,stroke-width:0px,color:#222222")
    println(io, "    style lg_purple_border fill:transparent,stroke:transparent,stroke-width:0px,color:#7a378b")
    println(io, "    style lg_red_border fill:transparent,stroke:transparent,stroke-width:0px,color:#d9383a")
    println(io, "    style lg_traditional fill:transparent,stroke:transparent,stroke-width:0px,color:#444444")
    println(io, "    style lg_unknown fill:transparent,stroke:transparent,stroke-width:0px,color:#444444")
end

function generate_profile(
    profile_name::Symbol,
    profile,
    nodes,
    edges,
    styles,
)
    selected_ids = select_profile_nodes(profile_name, nodes, edges, styles)

    selected_node_rows = [
        row for row in eachrow(nodes)
        if cell_string(row.id) in selected_ids
    ]

    selected_edge_indices = [
        i for (i, row) in enumerate(eachrow(edges))
        if cell_string(row.from) in selected_ids &&
           cell_string(row.to) in selected_ids
    ]

    io = IOBuffer()
    println(io, "```mermaid")
    println(io, "%% $(profile.title)")
    println(io, "%%{init: {'theme':'default','themeCSS':'.node foreignObject div, .node div, .node span, .label { white-space: normal !important; text-align: center; line-height: 1.4; }','flowchart':{'htmlLabels':true,'useMaxWidth':true}}}%%")
    println(io, "flowchart $(profile.direction)")
    println(io, "    classDef tennos fill:#ffffff,fill-opacity:0.8,stroke:#111111,stroke-width:6px,font-weight:bold;")
    println(io, "    classDef femaleTennos fill:#ffffff,fill-opacity:0.8,stroke:#7a378b,stroke-width:6px,font-weight:bold;")
    println(io, "    classDef princes fill:#ffffff,fill-opacity:0.8,stroke:#111111,stroke-width:1.5px;")
    println(io, "    classDef princesses fill:#ffffff,fill-opacity:0.8,stroke:#7a378b,stroke-width:1.5px,font-weight:bold;")
    println(io, "    classDef civilPrincesses fill:#ffffff,fill-opacity:0.8,stroke:#d9383a,stroke-width:1.5px,font-weight:bold;")
    println(io, "    classDef marriageNode fill:#444444,stroke:#444444;")

    write_profile_nodes!(
        io,
        profile_name,
        profile,
        selected_node_rows,
    )
    emit_special_node_styles!(io, selected_node_rows)

    groups = Dict(
        "main_blue" => Int[],
        "female_purple" => Int[],
        "bloodline_orange" => Int[],
        "bloodline_orange_dashed" => Int[],
        "modern_inflow_green" => Int[],
        "yushi" => Int[],
        "default" => Int[],
        "layout_hint" => Int[],
    )

    for (local_index, global_index) in enumerate(selected_edge_indices)
        row = edges[global_index, :]
        println(
            io,
            edge_line(
                cell_string(row.from),
                cell_string(row.to),
                cell_string(row.relation),
                cell_string(row.label),
            ),
        )

        push!(groups[styles[global_index]], local_index - 1)
    end

    !isempty(groups["main_blue"]) &&
        println(io, "    linkStyle $(join(groups["main_blue"], ",")) stroke:#0055a5,stroke-width:3.5px;")
    !isempty(groups["female_purple"]) &&
        println(io, "    linkStyle $(join(groups["female_purple"], ",")) stroke:#7a378b,stroke-width:3.5px;")
    !isempty(groups["bloodline_orange"]) &&
        println(io, "    linkStyle $(join(groups["bloodline_orange"], ",")) stroke:#d97706,stroke-width:3.5px;")
    !isempty(groups["bloodline_orange_dashed"]) &&
        println(io, "    linkStyle $(join(groups["bloodline_orange_dashed"], ",")) stroke:#d97706,stroke-width:3.5px,stroke-dasharray:8 4;")
    !isempty(groups["modern_inflow_green"]) &&
        println(io, "    linkStyle $(join(groups["modern_inflow_green"], ",")) stroke:#2f855a,stroke-width:4px,stroke-dasharray:8 4;")
    !isempty(groups["yushi"]) &&
        println(io, "    linkStyle $(join(groups["yushi"], ",")) stroke:#888888,stroke-width:2px,stroke-dasharray:5 5;")
    !isempty(groups["default"]) &&
        println(io, "    linkStyle $(join(groups["default"], ",")) stroke:#666666,stroke-width:1.5px;")

    emit_public_legend!(io, profile_name)

    println(io, "```")

    open(profile.path, "w") do file
        write(file, take!(io))
    end

    return (
        nodes = length(selected_node_rows),
        edges = length(selected_edge_indices),
        path = profile.path,
    )
end

function extract_mermaid_source(markdown_path::String)
    text = read(markdown_path, String)
    m = match(r"```mermaid\s*\n(.*?)\n```"s, text)
    m === nothing && error("Mermaidコードブロックを抽出できません: $(markdown_path)")
    return String(m.captures[1])
end

function html_escape_mermaid_source(text::AbstractString)
    return replace(
        text,
        "&" => "&amp;",
        "<" => "&lt;",
        ">" => "&gt;",
    )
end

function write_mermaid_html(markdown_path::String, html_path::String, title::String)
    source = extract_mermaid_source(markdown_path)
    escaped_source = html_escape_mermaid_source(source)

    html = """<!doctype html>
<html lang=\"ja\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>$(title)</title>
  <style>
    html, body { margin: 0; padding: 0; background: #ffffff; color: #222222; overflow: hidden; }
    body { font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", \"Yu Gothic UI\", \"Meiryo\", sans-serif; }
    .toolbar {
      position: relative; z-index: 20;
      display: flex; flex-wrap: wrap; gap: 6px 10px; align-items: center;
      min-height: 42px; padding: 7px 10px; border-bottom: 1px solid #dddddd;
      background: rgba(255,255,255,0.97); box-sizing: border-box;
      font-size: 13px; user-select: none;
    }
    .toolbar button {
      min-width: 32px; padding: 4px 9px; border: 1px solid #bbbbbb; border-radius: 4px;
      background: #ffffff; color: #222222; cursor: pointer; font: inherit;
    }
    .toolbar button:hover { background: #f2f2f2; }
    .toolbar .sep { width: 1px; height: 22px; background: #dddddd; margin: 0 2px; }
    #zoomLabel { min-width: 48px; text-align: center; font-variant-numeric: tabular-nums; }
    #status.error { color: #b00020; font-weight: 600; }

    /* Mermaid描画条件はVS Code Previewに合わせ、描画後のSVG表示寸法だけ原寸固定する。 */
    .viewport {
      position: relative; overflow: auto;
      width: 100vw; height: calc(100vh - 48px);
      background: #ffffff; cursor: auto;
    }
    .viewport.pan-ready { cursor: grab; }
    .viewport.dragging { cursor: grabbing; }
    .mermaid, .mermaid * {
      user-select: text;
      -webkit-user-select: text;
    }
    .viewport.dragging .mermaid, .viewport.dragging .mermaid * {
      user-select: none !important;
      -webkit-user-select: none !important;
    }
    #panMode.active {
      background: #e9eef8;
      border-color: #7f96bd;
      font-weight: 600;
    }
    .stage { position: relative; display: block; margin: 0; padding: 0; }
    .diagram-wrap { position: absolute; left: 0; top: 0; padding: 24px; box-sizing: content-box; transform-origin: 0 0; }
    .mermaid { display: inline-block; width: auto !important; min-width: 0 !important; }
    .mermaid svg {
      display: block;
      width: auto !important;
      max-width: none !important;
      min-width: 0 !important;
      height: auto !important;
      overflow: visible;
    }
  </style>
</head>
<body>
  <div class=\"toolbar\">
    <strong>$(title)</strong>
    <a href="./index.html" style="color:#334155;text-decoration:none;">← トップ</a>
    <span class=\"sep\"></span>
    <button id=\"zoomOut\" title=\"縮小\">−</button>
    <span id=\"zoomLabel\">100%</span>
    <button id=\"zoomIn\" title=\"拡大\">＋</button>
    <button id=\"zoom100\" title=\"100%\">100%</button>
    <button id=\"fitWidth\" title=\"横幅に合わせる（必要なときだけ）\">横幅</button>
    <button id=\"fitAll\" title=\"全体を表示\">全体</button>
    <span class=\"sep\"></span>
    <button id=\"panMode\" type=\"button\" aria-pressed=\"false\" title=\"ONのとき左ドラッグで図を移動。OFFでは文字選択\">パン: OFF</button>
    <span>左ドラッグ=文字選択 / Alt+左ドラッグ・中ボタン=移動 / Alt+ホイール=拡大縮小 / Shift+ホイール=左右</span>
    <span id=\"status\">描画中…</span>
  </div>
  <div id=\"viewport\" class=\"viewport\">
    <div id=\"stage\" class=\"stage\">
      <div id=\"diagramWrap\" class=\"diagram-wrap\">
        <div class=\"mermaid\">$(escaped_source)</div>
      </div>
    </div>
  </div>
  <script type=\"module\">
    const status = document.getElementById('status');
    const viewport = document.getElementById('viewport');
    const stage = document.getElementById('stage');
    const diagramWrap = document.getElementById('diagramWrap');
    const zoomLabel = document.getElementById('zoomLabel');
    const panButton = document.getElementById('panMode');
    if (!panButton) {
      throw new Error('パン切替ボタン #panMode がHTMLにありません。');
    }

    let scale = 1.0;
    let baseWidth = 0;
    let baseHeight = 0;
    let panMode = false;
        const padding = 48;

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    function updateStageSize() {
      stage.style.width = Math.ceil(baseWidth * scale + padding) + 'px';
      stage.style.height = Math.ceil(baseHeight * scale + padding) + 'px';
      diagramWrap.style.transform = `scale(\${scale})`;
      zoomLabel.textContent = Math.round(scale * 100) + '%';
    }

    function setScale(nextScale, anchorX = viewport.clientWidth / 2, anchorY = viewport.clientHeight / 2) {
      if (!baseWidth || !baseHeight) return;
      nextScale = clamp(nextScale, 0.05, 4.0);
      const oldScale = scale;
      const contentX = (viewport.scrollLeft + anchorX) / oldScale;
      const contentY = (viewport.scrollTop + anchorY) / oldScale;
      scale = nextScale;
      updateStageSize();
      viewport.scrollLeft = contentX * scale - anchorX;
      viewport.scrollTop = contentY * scale - anchorY;
    }

    function fitWidth() {
      const available = Math.max(1, viewport.clientWidth - padding);
      setScale(Math.min(1, available / baseWidth), 0, 0);
      viewport.scrollLeft = 0;
    }

    function fitAll() {
      const sx = Math.max(0.05, (viewport.clientWidth - padding) / baseWidth);
      const sy = Math.max(0.05, (viewport.clientHeight - padding) / baseHeight);
      setScale(Math.min(1, sx, sy), 0, 0);
      viewport.scrollLeft = 0;
      viewport.scrollTop = 0;
    }

    function syncPanCursor() {
      viewport.classList.toggle('pan-ready', panMode);
      panButton.classList.toggle('active', panMode);
      panButton.textContent = panMode ? 'パン: ON' : 'パン: OFF';
      panButton.setAttribute('aria-pressed', panMode ? 'true' : 'false');
    }

    panButton.addEventListener('click', () => {
      panMode = !panMode;
      syncPanCursor();
      if (!panMode) window.getSelection()?.removeAllRanges();
    });

    document.getElementById('zoomIn').addEventListener('click', () => setScale(scale * 1.2));
    document.getElementById('zoomOut').addEventListener('click', () => setScale(scale / 1.2));
    document.getElementById('zoom100').addEventListener('click', () => setScale(1.0));
    document.getElementById('fitWidth').addEventListener('click', fitWidth);
    document.getElementById('fitAll').addEventListener('click', fitAll);

    viewport.addEventListener('wheel', (e) => {
      if (e.altKey) {
        e.preventDefault();
        const rect = viewport.getBoundingClientRect();
        const ax = e.clientX - rect.left;
        const ay = e.clientY - rect.top;
        setScale(scale * (e.deltaY < 0 ? 1.12 : 1 / 1.12), ax, ay);
      } else if (e.shiftKey) {
        e.preventDefault();
        viewport.scrollLeft += e.deltaY;
      }
    }, { passive: false });

    let dragging = false, dragPointerId = null, lastX = 0, lastY = 0;
    viewport.addEventListener('pointerdown', (e) => {
      const useMiddleButton = e.button === 1;
      const useLeftPan = e.button === 0 && (panMode || e.altKey);
      if (!(useMiddleButton || useLeftPan)) return;

      e.preventDefault();
      window.getSelection()?.removeAllRanges();
      dragging = true;
      dragPointerId = e.pointerId;
      lastX = e.clientX; lastY = e.clientY;
      viewport.setPointerCapture(e.pointerId);
      viewport.classList.add('dragging');
    });
    viewport.addEventListener('pointermove', (e) => {
      if (!dragging || e.pointerId !== dragPointerId) return;
      e.preventDefault();
      viewport.scrollLeft -= e.clientX - lastX;
      viewport.scrollTop -= e.clientY - lastY;
      lastX = e.clientX; lastY = e.clientY;
    });
    function finishDragging(e) {
      if (!dragging) return;
      if (e && dragPointerId !== null && e.pointerId !== dragPointerId) return;
      dragging = false;
      dragPointerId = null;
      viewport.classList.remove('dragging');
      syncPanCursor();
    }
    viewport.addEventListener('pointerup', finishDragging);
    viewport.addEventListener('pointercancel', finishDragging);

    syncPanCursor();

    try {
      // VS Code標準Markdown Previewと同じMermaid 11.12.0を固定使用する。
      // theme / themeVariables / flowchart設定はHTML側から上書きせず、
      // Mermaidソース内の %%{init: ...}%% をそのまま尊重する。
      // HTML側ではsecure設定である上限値だけを引き上げる。
      const { default: mermaid } = await import('https://cdn.jsdelivr.net/npm/mermaid@11.12.0/dist/mermaid.esm.min.mjs');
      mermaid.initialize({
        startOnLoad: false,
        maxEdges: $(CONFIG.mermaid_max_edges),
        maxTextSize: $(CONFIG.mermaid_max_text_size),
        securityLevel: 'strict'
      });
      await mermaid.run({ querySelector: '.mermaid' });

      const svg = document.querySelector('.mermaid svg');
      if (!svg) throw new Error('Mermaid SVG が生成されませんでした。');

      /* MermaidがVS Code相当条件で算出したviewBoxを使い、表示寸法だけ原寸固定する。 */
      const vb = svg.viewBox && svg.viewBox.baseVal;
      if (vb && vb.width > 0 && vb.height > 0) {
        baseWidth = vb.width;
        baseHeight = vb.height;
        svg.setAttribute('width', String(baseWidth));
        svg.setAttribute('height', String(baseHeight));
      } else {
        const box = svg.getBBox();
        baseWidth = box.width;
        baseHeight = box.height;
        svg.setAttribute('width', String(baseWidth));
        svg.setAttribute('height', String(baseHeight));
      }
      svg.style.width = baseWidth + 'px';
      svg.style.height = baseHeight + 'px';
      svg.style.maxWidth = 'none';

      updateStageSize();
      status.textContent = `描画完了 / 原寸 \${Math.round(baseWidth)} × \${Math.round(baseHeight)} px`;
    } catch (error) {
      console.error(error);
      status.textContent = '描画エラー: ' + (error?.message ?? error);
      status.classList.add('error');
    }
  </script>
</body>
</html>
"""

    open(html_path, "w") do io
        write(io, html)
    end
end

function generate_html_views(results)
    write_mermaid_html(
        results[:full].path,
        CONFIG.full_html_path,
        "皇統皇胤図 v4.2.8 完全図",
    )
    # GitHub Pages用。リポジトリ直下の full.html をこのファイルで上書きできる。
    cp(CONFIG.full_html_path, CONFIG.pages_full_html_path; force=true)

    return (
        full = CONFIG.full_html_path,
        pages_full = CONFIG.pages_full_html_path,
    )
end

function generate_all_diagrams(nodes, edges, styles)
    results = Dict{Symbol, NamedTuple}()

    for profile_name in propertynames(DIAGRAM_PROFILES)
        profile = getproperty(DIAGRAM_PROFILES, profile_name)
        results[profile_name] = generate_profile(
            profile_name,
            profile,
            nodes,
            edges,
            styles,
        )
    end

    return results
end

function write_report(errors, warnings, styles, nodes, edges, female_routes)
    node_name = Dict(cell_string(r.id) => cell_string(r.name) for r in eachrow(nodes))
    node_note = Dict(cell_string(r.id) => cell_string(r.note) for r in eachrow(nodes))
    node_sex  = Dict(cell_string(r.id) => cell_string(r.sex) for r in eachrow(nodes))
    node_scope = Dict(cell_string(r.id) => cell_string(r.lineage_scope) for r in eachrow(nodes))

    function display_node(id::String)
        name = get(node_name, id, "")
        note = get(node_note, id, "")
        sex = get(node_sex, id, "")

        if !isempty(name)
            sex_mark = sex == "female" ? "【男系女子】" : ""
            return "$(sex_mark)$(name) [$(id)]"
        elseif !isempty(note)
            return "$(note) [$(id)]"
        else
            return id
        end
    end

    function relation_arrow(edge_index::Int)
        relation = cell_string(edges[edge_index, :relation])

        if relation == "spouse_to_union"
            return " ─婚姻等→ "
        elseif relation == "union_to_child"
            return " ─実子→ "
        elseif relation == "biological_parent"
            return " → "
        elseif relation == "yushi"
            return " -.猶子.→ "
        elseif relation == "adoption"
            return " -.養子.→ "
        elseif relation == "layout_hint"
            return " ~~配置誘導~~ "
        else
            return " → "
        end
    end

    function format_path(route)
        io = IOBuffer()
        print(io, display_node(route.node_path[1]))

        for i in eachindex(route.edge_path)
            print(io, relation_arrow(route.edge_path[i]))
            print(io, display_node(route.node_path[i + 1]))
        end

        return String(take!(io))
    end

    open(CONFIG.report_path, "w") do io
        println(io, "皇統皇胤図データ検査レポート v4.2.8（公開基盤版・婚姻等関係節点監査）")
        println(io, "================================")
        println(io)

        println(io, "エラー: $(length(errors)) 件")
        for (i, message) in enumerate(errors)
            println(io, "  E$(lpad(i, 3, '0')): $(message)")
        end

        println(io)
        println(io, "警告: $(length(warnings)) 件")
        for (i, message) in enumerate(warnings)
            println(io, "  W$(lpad(i, 3, '0')): $(message)")
        end

        println(io)
        println(io, "生没年 第2段階")
        println(io, "--------------------------------")
        println(io, "今回追加: 17人物")
        println(io, "対象: 霊元天皇～大正天皇、明治天皇皇女4名、貞明皇后。")
        println(io)
        println(io, "生没年 第2段階続き")
        println(io, "--------------------------------")
        println(io, "今回追加: 13人物")
        println(io, "対象: 福子内親王、伏見宮邦永～邦家、閑院宮直仁～愛仁。")
        println(io)
        println(io, "生没年 第3段階A")
        println(io, "--------------------------------")
        println(io, "今回追加: 15人物")
        println(io, "伏見宮系列の生年未入力: 0人物")
        println(io, "対象: 栄仁親王～貞致親王、貞教親王、貞愛親王。")
        println(io)
        println(io, "生没年 第3段階B")
        println(io, "--------------------------------")
        println(io, "今回追加: 13人物")
        println(io, "t100～t123の生年未入力: 0人物")
        println(io, "対象: 後小松～後西天皇、および誠仁親王。")
        println(io)
        println(io, "生没年 第3段階C")
        println(io, "--------------------------------")
        println(io, "今回追加: 15人物")
        println(io, "t090～t123の生年未入力: 0人物")
        println(io, "北朝天皇の生年未入力: 0人物")
        println(io, "後亀山天皇は生年1350年説に疑問符が付くため、birth_yearは?としました。")
        println(io)
        println(io, "生没年 第3段階D")
        println(io, "--------------------------------")
        println(io, "今回追加: 11人物")
        println(io, "t080～t123の生年未入力: 0人物")
        println(io, "対象: 高倉～後深草天皇、および守貞親王。")
        println(io)
        println(io, "生没年 第3段階E")
        println(io, "--------------------------------")
        println(io, "今回追加: 8人物")
        println(io, "t072～t123の生年未入力: 0人物")
        println(io, "対象: 白河～六条天皇。")
        println(io)
        println(io, "生没年 第3段階F")
        println(io, "--------------------------------")
        println(io, "今回追加: 6人物")
        println(io, "t066～t123の生年未入力: 0人物")
        println(io, "対象: 一条～後三条天皇。")
        println(io)
        println(io, "生没年 第3段階G")
        println(io, "--------------------------------")
        println(io, "今回追加: 6人物")
        println(io, "t060～t123の生年未入力: 0人物")
        println(io, "対象: 醍醐～花山天皇。")
        println(io)
        println(io, "生没年 第4段階（一括補完）")
        println(io, "--------------------------------")
        println(io, "今回追加: 21人物")
        println(io, "t041～t123の対象天皇・重祚ノードの生年空欄: 0人物")
        println(io, "生没年情報入力済み総数: 210/374人物")
        println(io, "舎人親王は生年676年説に疑問符が付くため ?–735 と表示します。")
        println(io, "光仁天皇は和暦年基準の慣用表記709–781を採用し、現代暦換算782年説をdate_noteに保持します。")
        println(io)
        println(io, "生没年 第5段階（飛鳥期一括補完）")
        println(io, "--------------------------------")
        println(io, "今回追加: 11人物")
        println(io, "生没年情報入力済み総数: 221/374人物")
        println(io, "t029以降の対象皇統ノードのbirth_year空欄: 0人物")
        println(io, "不確実・不詳の生年はbirth_yearを空欄とし、候補年や異説をdate_noteへ保持します。人物枠では空欄を ? として表示します。")
        println(io, "暦年基準は和暦年に対応する西暦年へ統一し、持統天皇を645–702へ修正しました。")
        println(io)
        println(io, "古代伝承紀年")
        println(io, "--------------------------------")
        traditional_ids = sort([
            cell_string(row.id)
            for row in eachrow(nodes)
            if cell_string(row.type) != "marriage" &&
               !isempty(cell_string(row.traditional_life_years))
        ])
        println(io, "traditional_life_years入力: $(length(traditional_ids))人物")
        println(io, "対象ID: $(join(traditional_ids, ", "))")
        println(io, "伝承紀年はbirth_year/death_yearから分離し、人物枠では（伝承紀年）を明示します。")
        println(io, "これにより記紀紀年を史実上の生没年と誤認しない構造にしました。")
        println(io)
        println(io, "古代非天皇人物 年代整理（v3.52から継続）")
        println(io, "--------------------------------")
        ancient_non_emperor_ids = Set([
            "p_jingu", "p_yamatotakeru", "p_wakasako", "p_ohoji", "p_oshi",
            "p_hikoushino", "p_furuhime", "p_ichinobe", "p_kasuga_oiratsume",
            "p_tashiraka", "p_tachibana_nakatsuhime",
        ])
        dated_count = count(
            row -> cell_string(row.id) in ancient_non_emperor_ids &&
                   (!isempty(cell_string(row.birth_year)) ||
                    !isempty(cell_string(row.death_year)) ||
                    !isempty(cell_string(row.traditional_life_years))),
            eachrow(nodes),
        )
        noted_count = count(
            row -> cell_string(row.id) in ancient_non_emperor_ids &&
                   !isempty(cell_string(row.date_note)),
            eachrow(nodes),
        )
        println(io, "v3.52重点整理対象: $(length(ancient_non_emperor_ids))人物")
        println(io, "伝承紀年または通常年代あり: $(dated_count)人物")
        println(io, "date_noteによる時代・史料上の位置づけあり: $(noted_count)人物")
        println(io, "神功皇后170–269は伝承紀年として維持し、史料が生没年を支持しない人物には数値を置きません。")
        println(io)

        println(io, "古代系譜・伝承年次整理（v3.53から継続）")
        println(io, "--------------------------------")
        ancient_lineage_ids = Set([
            "p_hikoimasu", "p_tanbamichinushi", "p_hibasuhime",
            "p_yamashiro", "p_kaname", "p_okinaga", "p_jingu",
            "p_yasakairihiko", "p_yasakairihime", "p_iokiirihiko",
            "p_hondamawaka", "p_nakatsuhime",
        ])
        lineage_noted_count = count(
            row -> cell_string(row.id) in ancient_lineage_ids &&
                   !isempty(cell_string(row.date_note)),
            eachrow(nodes),
        )
        lineage_traditional_count = count(
            row -> cell_string(row.id) in ancient_lineage_ids &&
                   !isempty(cell_string(row.traditional_life_years)),
            eachrow(nodes),
        )
        println(io, "重点整理対象: $(length(ancient_lineage_ids))人物")
        println(io, "date_note入力済み: $(lineage_noted_count)人物")
        println(io, "traditional_life_yearsあり: $(lineage_traditional_count)人物")
        println(io, "日葉酢媛命は『日本書紀』垂仁32年没を伝承紀年へ換算し ?–3 としました。")
        println(io, "p_yamashiro の人物名を『古事記』開化天皇段に従い「山代之大筒木真若王」へ修正しました。")
        println(io, "神功皇后父系は、『古事記』の詳細系譜と『日本書紀』の世代数が一致しないことをdate_noteへ明記しました。")
        println(io, "八坂入彦命→八坂入媛→五百城入彦皇子→品陀真若王→仲姫命の橙線系譜も、生没年不詳を維持したまま記紀上の位置づけを補完しました。")
        println(io)

        println(io, "古代人物 date_note 一括整理（v3.54から継続）")
        println(io, "--------------------------------")
        v354_batch_ids = Set([
            "n_ahiratsuhime", "p_tagishimimi", "n_isuzuhime", "p_hikoyai",
            "p_kamuyai_mimi", "n_isuzuyori", "n_nunasoko", "p_okisomimi",
            "p_shikitsuhiko", "p_amatoyotsuhime", "p_takeshihiko",
            "n_yosotarashi", "p_ameoshitarashi", "p_oshihime",
            "p_okibi_morosusume", "n_hosohime", "n_utsushikome",
            "p_ohiko", "p_mimakihime", "n_ikagashikome", "n_hahatsuhime",
            "p_iwatsukuwake", "p_iwakiwake", "p_iwakoriwake", "p_mawakake",
            "p_akahachikimi", "p_obachikimi", "p_futajinoirihime",
            "p_sakurai", "p_kibihime", "p_ishihime", "p_oshisaka",
            "p_nukatehime", "p_chinu", "p_kusakabe", "p_shiki",
        ])
        v354_noted = count(
            row -> cell_string(row.id) in v354_batch_ids &&
                   !isempty(cell_string(row.date_note)),
            eachrow(nodes),
        )
        v354_normal_dated = count(
            row -> cell_string(row.id) in v354_batch_ids &&
                   (!isempty(cell_string(row.birth_year)) ||
                    !isempty(cell_string(row.death_year))),
            eachrow(nodes),
        )
        println(io, "重点整理対象: $(length(v354_batch_ids))人物")
        println(io, "date_note入力済み: $(v354_noted)人物")
        println(io, "通常年代あり: $(v354_normal_dated)人物")
        println(io, "吉備姫王 ?–643、糠手姫皇女 ?–664、草壁皇子 662–689、志貴皇子 ?–716 を通常年代側へ追加しました。")
        println(io, "大彦命は稲荷山古墳鉄剣銘の「意富比垝」との比定可能性を、同一人物と断定せず考古資料との接点としてdate_noteへ記録しました。")
        println(io, "欠史八代周辺の人物は、無理な絶対年代化を行わず、記紀系譜・異伝・生没年不詳をdate_noteへ整理しました。")
        println(io, "継体天皇母系の『上宮記』逸文系譜は、独立年代が乏しい人物を系譜伝承上の人物として明示しました。")
        println(io)

        println(io, "人物 date_note 全件整理（v3.55から継続）")
        println(io, "--------------------------------")
        person_rows = [
            row for row in eachrow(nodes)
            if cell_string(row.type) != "marriage"
        ]
        date_note_blank_ids = [
            cell_string(row.id)
            for row in person_rows
            if isempty(cell_string(row.date_note))
        ]
        normal_dated_persons = count(
            row -> !isempty(cell_string(row.birth_year)) ||
                   !isempty(cell_string(row.death_year)),
            person_rows,
        )
        traditional_dated_persons = count(
            row -> !isempty(cell_string(row.traditional_life_years)),
            person_rows,
        )
        any_dated_persons = count(
            row -> !isempty(cell_string(row.birth_year)) ||
                   !isempty(cell_string(row.death_year)) ||
                   !isempty(cell_string(row.traditional_life_years)),
            person_rows,
        )
        println(io, "人物ノード数: $(length(person_rows))")
        println(io, "date_note空欄: $(length(date_note_blank_ids))人物")
        if !isempty(date_note_blank_ids)
            println(io, "  空欄ID: $(join(sort(date_note_blank_ids), ", "))")
        end
        println(io, "通常年代あり: $(normal_dated_persons)人物")
        println(io, "伝承紀年あり: $(traditional_dated_persons)人物")
        println(io, "何らかの年代情報あり: $(any_dated_persons)人物")
        println(io, "v3.110.1では残っていたdate_note空欄20人物を整理し、人物ノードのdate_note空欄を0としました。")
        println(io, "近現代民間人については、系譜確認に必要な公開情報のみを収録し、非公開子孫の氏名等は追加しません。")
        println(io)

        println(io, "年代品質監査（v3.56から継続）")
        println(io, "--------------------------------")
        quality_counts = Dict(
            key => count(
                row -> cell_string(row.type) != "marriage" &&
                       cell_string(row.date_quality) == key,
                eachrow(nodes),
            )
            for key in (
                "A_standard",
                "B_partial_or_disputed",
                "C_secondary_genealogy",
                "T_traditional",
                "U_undated",
            )
        )
        for key in (
            "A_standard",
            "B_partial_or_disputed",
            "C_secondary_genealogy",
            "T_traditional",
            "U_undated",
        )
            println(io, "  $(key): $(quality_counts[key])人物")
        end

        println(io)
        println(io, "B_partial_or_disputed:")
        disputed_ids = sort([
            cell_string(row.id)
            for row in eachrow(nodes)
            if cell_string(row.type) != "marriage" &&
               cell_string(row.date_quality) == "B_partial_or_disputed"
        ])
        println(io, isempty(disputed_ids) ? "  該当なし" : "  " * join(disputed_ids, ", "))

        println(io)
        println(io, "C_secondary_genealogy:")
        secondary_ids = sort([
            cell_string(row.id)
            for row in eachrow(nodes)
            if cell_string(row.type) != "marriage" &&
               cell_string(row.date_quality) == "C_secondary_genealogy"
        ])
        println(io, isempty(secondary_ids) ? "  該当なし" : "  " * join(secondary_ids, ", "))

        println(io)
        println(io, "通常年代のbirth_year / death_yearは整数年または空欄に正規化しました。")
        println(io, "v3.55までbirth_year='?'だった9人物は空欄へ変更し、表示上は従来どおり ?–没年 とします。")
        println(io, "traditional_life_yearsは通常年代から分離し、T_traditionalとして監査します。")
        println(io)

        println(io, "C_secondary_genealogy 一括再検証（v3.57から継続）")
        println(io, "--------------------------------")
        println(io, "v3.56のC対象: 59人物")
        println(io, "A_standardへ格上げ: 14人物")
        println(io, "年代値を修正しB_partial_or_disputedへ: 2人物")
        println(io, "C_secondary_genealogy継続: 43人物")
        println(io, "主な格上げ根拠: 国立国会図書館典拠・近代日本人の肖像、宮内庁書陵部資料、東京都庭園美術館、京都国立近代美術館、講談社『日本人名大辞典+Plus』。")
        println(io, "山階宮菊麿王: birth_year 1874 → 1873 に修正。")
        println(io, "北白川宮智成親王: birth_year 1855 → 1856 に修正。")
        println(io, "C継続群は主に戦後の旧宮家民間人であり、公的典拠へ置換できない人物を無理に格上げしていません。")
        println(io)

        println(io, "C_secondary_genealogy 層別再検証（v3.58から継続）")
        println(io, "--------------------------------")
        println(io, "v3.57残存C: 43人物")
        println(io, "今回A_standardへ格上げ: 6人物")
        println(io, "今回B_partial_or_disputedへ格上げ: 1人物")
        println(io, "C継続: 36人物")
        println(io, "C継続36人物を、史料未置換の歴史人物・1947年皇籍離脱世代・戦後民間子孫の3群に分類しました。")
        println(io, "A格上げ: 久邇宮朝融王、東久邇盛厚、賀陽恒憲、賀陽邦寿、朝香孚彦、閑院宮愛仁親王。")
        println(io, "B格上げ: 伏見博明（国立国会図書館書誌で1932年生を確認、没年欄は空欄維持）。")
        println(io, "戦後民間子孫は、公開系譜以上の個人情報を追わずC継続を正式な品質判断とします。")
        println(io)

        println(io, "C1・C2および竹田恒泰 再検証（v3.59から継続）")
        println(io, "--------------------------------")
        println(io, "対象: C1 4人物 + C2 11人物 + C3例外の竹田恒泰 = 16人物")
        println(io, "A_standardへ格上げ: 2人物（博義王、賀彦王）")
        println(io, "B_partial_or_disputedへ格上げ: 12人物（C2全11人物 + 竹田恒泰）")
        println(io, "C継続: 2人物（伏見宮邦永親王、伏見宮邦忠親王）")
        println(io, "C2は宮内庁書陵部の御誕生関係録、竹田恒和はJOC公式プロフィールによりbirth_yearを直接確認しました。")
        println(io, "竹田恒泰は国立国会図書館典拠ID 01024918で1975年生を確認し、C3の例外としてBへ格上げしました。")
        println(io, "v3.110.1以後、C2_1947_former_royal は0人物です。")
        println(io)

        println(io, "C最終・神社法人再検証（v3.60から継続）")
        println(io, "--------------------------------")
        println(io, "v3.59残存C: 22人物")
        println(io, "B_partial_or_disputedへ格上げ: 2人物（久邇朝尊、壬生基博）")
        println(io, "A_standardへ格上げ: 1人物（多羅間俊彦。death_year=2015を追加）")
        println(io, "C_secondary_genealogy最終確定: 19人物")
        println(io, "久邇朝尊は神社新報の神宮大宮司就任記事で1959年生を確認。")
        println(io, "壬生基博は公益財団法人山階鳥類研究所公式プロフィールで1949年生を確認。")
        println(io, "多羅間俊彦はブラジル日本文化福祉協会公式訃報で2015年没・86歳を確認し、既存1929年生と整合。")
        println(io, "勤務先・法人役職が確認できても生年を記載しない資料は、年代の品質格上げ根拠には使用しません。")
        println(io, "これをCの最終一括作業とし、残存Cは新たな公的資料が自然に得られた場合のみ更新します。")
        println(io)

        println(io, "B品質理由細分化（v3.61から継続）")
        println(io, "--------------------------------")
        b_rows = [
            row for row in eachrow(nodes)
            if cell_string(row.type) != "marriage" &&
               cell_string(row.date_quality) == "B_partial_or_disputed"
        ]
        println(io, "B_partial_or_disputed: $(length(b_rows))人物")
        for tag in (
            "birth_unrecorded",
            "death_unrecorded",
            "disputed_birth",
            "disputed_death",
            "source_mixed",
            "value_corrected",
        )
            n = count(
                row -> tag in split(cell_string(row.date_quality_detail), ";"),
                b_rows,
            )
            println(io, "  $(tag): $(n)人物")
        end
        println(io, "date_quality_detail は複数tagをセミコロン区切りで保持します。")
        println(io, "例: 志貴皇子 = birth_unrecorded;disputed_death")
        println(io, "例: 北白川宮智成親王 = disputed_birth;value_corrected")
        println(io, "例: 賀陽章憲 = source_mixed")
        println(io)

        println(io, "U品質理由細分化（v3.62から継続）")
        println(io, "--------------------------------")
        u_rows = [
            row for row in eachrow(nodes)
            if cell_string(row.type) != "marriage" &&
               cell_string(row.date_quality) == "U_undated"
        ]
        println(io, "U_undated: $(length(u_rows))人物")
        for tag in (
            "legendary_or_mythic",
            "genealogical_tradition",
            "chronicle_activity_only",
            "historical_period_known",
            "source_conflict_uncertain",
            "external_source_contact",
        )
            n = count(
                row -> tag in split(cell_string(row.date_quality_detail), ";"),
                u_rows,
            )
            println(io, "  $(tag): $(n)人物")
        end
        println(io, "Uは年代空欄という状態だけでなく、『なぜ空欄なのか』を複数tagで保持します。")
        println(io, "例: 大彦命 = genealogical_tradition;chronicle_activity_only;external_source_contact")
        println(io, "例: 手白香皇女 = historical_period_known;genealogical_tradition")
        println(io, "例: 押坂彦人大兄皇子 = historical_period_known;genealogical_tradition;source_conflict_uncertain")
        println(io)

        println(io, "T伝承紀年品質監査（v3.63から継続）")
        println(io, "--------------------------------")
        t_rows = [
            row for row in eachrow(nodes)
            if cell_string(row.type) != "marriage" &&
               cell_string(row.date_quality) == "T_traditional"
        ]
        println(io, "T_traditional: $(length(t_rows))人物")
        for tag in (
            "nihon_shoki_based",
            "kesshi_hachidai",
            "chronology_conversion",
            "uncertain_birth",
            "disputed_death_t",
            "historicity_debated",
            "external_source_contact_t",
            "legendary_era",
        )
            n = count(
                row -> tag in split(cell_string(row.date_quality_detail), ";"),
                t_rows,
            )
            println(io, "  $(tag): $(n)人物")
        end
        println(io, "伝承紀年は通常年代とは分離したまま、その出典・換算・異説・外部史料接点をdetail tagで監査します。")
        println(io, "例: 継体天皇 = nihon_shoki_based;chronology_conversion;uncertain_birth;disputed_death_t")
        println(io, "例: 雄略天皇 = nihon_shoki_based;chronology_conversion;external_source_contact_t")
        println(io)

        println(io, "系譜年代整合性監査（v3.64から継続）")
        println(io, "--------------------------------")
        println(io, "通常年代を持つ親子について、親の出生年・死亡年と子の出生年の整合を監査します。")
        println(io, "hard error条件:")
        println(io, "  子が親より先に出生")
        println(io, "  母の出産年齢 <12 または >55")
        println(io, "  父の出産年齢 <12 または >80")
        println(io, "  子が親の死亡年より2年以上後に出生")
        println(io, "review条件:")
        println(io, "  母の出産年齢 <15 または >45")
        println(io, "  父の出産年齢 <15 または >=65")
        println(io, "  寿命 >110")
        println(io, "v3.110.1で系譜誤接続2件を修正:")
        println(io, "  1) 明治天皇→大正天皇の父子線を維持した上で、大正天皇・貞明皇后の婚姻等関係節点と4皇子への親子接続を修正")
        println(io, "  2) 守貞親王の父を後鳥羽天皇から高倉天皇へ修正")
        println(io, "修正後の静的監査では hard error 0件。")
        println(io, "父年齢境界レビュー: 邦家親王→晃親王 約14歳、邦家親王→依仁親王 約65歳。")
        println(io)

        println(io, "第二段系譜整合性監査（v3.65から継続）")
        println(io, "--------------------------------")
        println(io, "監査項目:")
        println(io, "  同一親の兄弟出生年差")
        println(io, "  同一婚姻等関係節点（同父母）の兄弟出生年差")
        println(io, "  同一親から見た子の出生年スパン")
        println(io, "  同一年出生兄弟")
        println(io, "  第一王子・第二王子等の順位表記と出生年順の逆転")
        println(io, "結果:")
        println(io, "  明確な出生順逆転: 0件")
        println(io, "  同父母の同一年出生: 0件")
        println(io, "  順位表記と出生年の逆転: 0件")
        println(io, "  review: 伏見宮邦家親王の子出生年スパン51年")
        println(io, "  info: 桓武天皇の嵯峨天皇・淳和天皇はいずれも786年生、久邇宮朝彦親王の朝香鳩彦・東久邇稔彦はいずれも1887年生。父単位の同年出生であり、同父母とは限らないためエラーとしません。")
        println(io)

        println(io, "婚姻等関係節点構造監査＋注記表記統一（v3.110.1）")
        println(io, "--------------------------------")
        println(io, "監査項目:")
        println(io, "  婚姻等関係節点の配偶者数")
        println(io, "  配偶者の男女組合せ")
        println(io, "  婚姻等関係節点の子接続")
        println(io, "  同一人物の複数婚姻等関係節点")
        println(io, "  同一子に異なる婚姻等関係節点親組合せがないか")
        println(io, "  婚姻等関係節点経由と直接biological_parentの二重表現")
        println(io, "  重複エッジ")
        println(io, "結果:")
        println(io, "  error: 0件")
        println(io, "  review: 0件")
        println(io, "  info: 6件")
        println(io, "婚姻等関係節点に子がいない場合は、子なし婚姻または未収録の可能性があるためinfo扱い。")
        println(io, "複数婚姻等関係節点に同一人物が登場しても、再婚等があり得るためinfo扱い。")
        println(io)

        println(io, "layout_hint 配置誘導")
        println(io, "--------------------------------")
        println(io, "relation=layout_hint は系譜上の血縁・婚姻・養子関係を意味せず、Mermaidの不可視リンク ~~~ としてノード配置だけを誘導します。")
        println(io, "main_blue / female_purple / lineage_scope / 年代・婚姻等関係節点監査の系譜経路には含めません。")
        println(io)

        println(io, "人物枠内文言")
        println(io, "--------------------------------")
        println(io, "v3.34から人物枠内は display_note を表示し、note は詳細・典拠・収録判断等の管理情報として保持します。")
        println(io, "v3.39ではbirth_year / death_year / date_noteを追加し、旧宮家近現代人物と現代皇族から生没年収録を開始しました。")
        println(io)
        println(io, "lineage_scope 人物数")
        for key in ("imperial", "non_imperial", "granted_clan", "claimed", "unknown", "")
            label = isempty(key) ? "(空欄)" : key
            count_value = count(
                row -> cell_string(row.type) != "marriage" &&
                       cell_string(row.lineage_scope) == key,
                eachrow(nodes),
            )
            println(io, "  $(label): $(count_value)")
        end

        println(io)
        println(io, "自動判定線数")
        for key in ("main_blue", "female_purple", "bloodline_orange", "bloodline_orange_dashed", "modern_inflow_green", "yushi", "default", "layout_hint")
            println(io, "  $(key): $(count(==(key), styles))")
        end

        println(io)
        println(io, "bloodline_orange 補助血統")
        println(io, "--------------------------------")
        println(io, "main_blue・female_purpleでは表現されない、歴代天皇から現皇統へ系譜上流入する別の血縁経路です。")
        println(io, "v3.30では重複流入も省略せず、確認できた別血統経路を橙線で表示します。")
        println(io, "main_blue / female_purpleと共有する区間では既存色を優先し、orangeは共有部へ合流する直前まで表示します。")
        println(io, "主な追加例: 雄略→春日大娘→橘仲→石姫、欽明→桜井皇子→吉備姫王→皇極・斉明、")
        println(io, "および崇神→八坂入彦→八坂入媛→五百城入彦→品陀真若→仲姫→仁徳の重複流入、")
        println(io, "さらに霊元天皇→福子内親王→伏見宮邦永親王との婚姻等関係節点→貞建親王系への重複流入。")
        println(io)
        println(io, "bloodline_orange_dashed 臣籍降下後再流入線")
        println(io, "--------------------------------")
        println(io, "橙色太破線は、皇族・宮家の区間を離れて臣籍降下した後の直系祖先経路を示します。")
        println(io, "当該区間の人物ノードには破線枠を付し、皇室へ再流入する直前まで橙色太破線で表示します。")
        println(io, "v4.2.8では、1947年以前臣籍降下者の先行例外として、邦英王（臣籍降下後の東伏見邦英、のち東伏見慈洽）とその男系を東伏見宮家祭祀継承の文脈で追加し、慈洽本人は臣籍降下後の身分を明示する破線枠としました。また、後冷泉天皇と増守の娘を婚姻等関係節点で束ね、高階為行（落胤）から高階・藤原・源・一条・西園寺系を経て後嵯峨天皇系へ再流入する橙経路を追加しました。後冷泉天皇→婚姻等関係節点→高階為行は、実子関係を維持しつつ皇族身分を伴わないため橙太破線としています。")
        println(io, "弘文系は天智天皇から、天武系は舒明・皇極の婚姻等関係節点から橙実線を開始します。")
        println(io, "一条天皇は円融天皇・藤原詮子の婚姻等関係節点、後水尾天皇は後陽成天皇・近衛前子の婚姻等関係節点を介して再流入します。")
        println(io)
        println(io, "modern_inflow_green 近代皇室流入線")
        println(io, "--------------------------------")
        println(io, "明治天皇以降の皇室本流の男系女子を介して、旧宮家へ流入した近代の血縁強化線です。")
        println(io, "緑の太破線で表示し、原則として「皇室本流の人物 → その皇女（または婚姻等関係節点） → 旧宮家側で最初に血を受ける世代」までを示します。")
        println(io, "主な対象: 明治天皇→昌子内親王→竹田宮、房子内親王→北白川宮、允子内親王→朝香宮、")
        println(io, "聡子内親王→東久邇宮、および昭和天皇→成子内親王→東久邇宮。")
        println(io)
        println(io, "female_purple 男系女子別経路")
        println(io, "--------------------------------")
        println(io, "対象は lineage_scope=imperial であり、神武天皇から本人まで皇室・皇族の父系を男性だけで遡れる女性です。")
        println(io, "本人より下流では、別の女性人物を介さず今上天皇へ至る経路だけを採用します。")
        println(io, "表示範囲は、上流側のmain_blue接続天皇から、下流側のmain_blue再接続点までです。")
        println(io)

        if isempty(female_routes)
            println(io, "  該当なし")
        else
            for route in female_routes
                println(io, "■ $(display_node(route.female_id))")
                println(io, "  lineage_scope: $(get(node_scope, route.female_id, ""))")
                println(io, "  上流接続天皇: $(display_node(route.anchor_id))")
                println(io, "  下流再接続点: $(display_node(route.rejoin_id))")
                println(io, "  紫線本数: $(length(route.purple_edge_path))")
                println(io, "  経路:")
                println(io, "    $(format_path(route))")
                println(io)
            end
        end
    end
end

function main()
    nodes = safe_load_csv(CONFIG.nodes_path)
    edges = safe_load_csv(CONFIG.edges_path)
    errors, warnings = validate_data(nodes, edges)

    audit_errors, audit_warnings = audit_lineage_scope(nodes, edges)
    append!(errors, audit_errors)
    append!(warnings, audit_warnings)

    if !isempty(errors)
        write_report(errors, warnings, String[], nodes, edges, NamedTuple[])
        error("データ検査でエラーが見つかりました。$(CONFIG.report_path) を確認してください。")
    end

    styles, female_routes, route_warnings = determine_styles(nodes, edges)
    append!(warnings, route_warnings)

    # 検査は全データに対して一度だけ実施する。
    write_report(errors, warnings, styles, nodes, edges, female_routes)

    # 同一CSV・同一スタイル判定結果から、用途別の複数図を生成する。
    results = generate_all_diagrams(nodes, edges, styles)
    html_results = generate_html_views(results)

    println("✅ 検査レポート: $(CONFIG.report_path)")
    println("✅ Mermaidファイル:")
    for profile_name in propertynames(DIAGRAM_PROFILES)
        result = results[profile_name]
        println(
            "   $(rpad(String(profile_name), 14)) nodes=$(lpad(result.nodes, 3)), edges=$(lpad(result.edges, 3)) → $(result.path)",
        )
    end

    println("✅ HTMLビュー（Mermaid maxEdges=$(CONFIG.mermaid_max_edges)):")
    println("   full           → $(html_results.full)")

    println(
        "   styles: main_blue=$(count(==("main_blue"), styles)), " *
        "female_purple=$(count(==("female_purple"), styles)), " *
        "bloodline_orange=$(count(==("bloodline_orange"), styles)), " *
        "bloodline_orange_dashed=$(count(==("bloodline_orange_dashed"), styles)), " *
        "modern_inflow_green=$(count(==("modern_inflow_green"), styles)), " *
        "yushi=$(count(==("yushi"), styles)), " *
        "default=$(count(==("default"), styles))",
    )
end

main()
