--[[
  text.lua — 界面文案（便于换语言 / 换成中文）
  ==================================================================
  默认英文：因为 Defold 内置字体（Vera Sans Mono Bold）只有 ASCII 与 Latin-1，
  直接显示中文会变成空白方块。

  想改成中文：
    1) 把一个含中文字形的字体（例如思源黑体 NotoSansSC-Regular.ttf）放进
       assets/fonts/，在编辑器里右键 → New → Font，
       字符集填你在界面上用到的字（或勾 All Chars），尺寸 32，
       存成 assets/fonts/ui_zh.font；
    2) 把下面 LANG 改成 "zh"；
    3) 把 logic/ui.lua 里的 M.FONT_UI 指向 /assets/fonts/ui_zh.font。
  数字部分（时间）不受影响，它用的是 clock.font（只有 0-9 和 : . ）。

  非 ASCII 的两个字符 ° 与 × 已经写进 assets/fonts/ui.font 的 characters
  （实测 Vera Sans Mono Bold 里这两个码位有字形）；⇵ ⛶ ⚙ 🔊 没有字形，
  所以那些按钮改用 assets/icons 里的图片，**不要**把它们写进这里的文案。
]]

local M = {}

M.LANG = "en"

local strings = {
  en = {
    title        = "CoQ CHESS CLOCK",
    subtitle     = "tournament clock for phone / desktop",

    mode         = "1. TIME MODE",
    timing       = "2. TIME CONTROL",
    start        = "START GAME",
    base_time    = "BASE TIME (MIN)",
    add_time     = "FISCHER ADD (SEC)",
    delay_time   = "DELAY (SEC)",
    byoyomi_time = "BYOYOMI (SECONDS)",
    byoyomi_seg  = "BYOYOMI SEGMENTS",
    presets      = "PRESETS",
    sound        = "SOUND",
    sound_on     = "ON",
    sound_off    = "OFF",
    theme        = "COLOUR THEME",
    theme_light  = "LIGHT",
    theme_medium = "MEDIUM",
    theme_dark   = "DARK",
    summary      = "THIS GAME",

    -- 「怎么用」里关于开局的那两句：点「开始对局」后没有第二次「开始」，
    -- 由不该先走的一方拍自己那侧 → 对方的钟开始走（与网页版 how.facing 一致）
    how_start_1  = "NO SECOND START: tap the side not to move first (Black) - White's clock runs",
    how_start_2  = "After your move tap your own side - the opponent's clock runs",

    -- 「怎么用」现在单独一页：设置页只留入口，页内标题 / 返回按钮各一条
    how          = "HOW TO USE",
    back         = "< BACK",
    preset_custom = "CUSTOM",

    m_fischer    = "Fischer",
    m_delay      = "Bronstein",
    m_byoyomi    = "Byoyomi",
    m_sudden     = "Sudden",

    white        = "WHITE",
    black        = "BLACK",
    move         = "MOVE",
    waiting      = "WAITING",
    running      = "TO MOVE",
    byoyomi      = "BYOYOMI",
    paused       = "PAUSED",
    paused_tag   = "PAUSED",
    ready_tag    = "SET",
    segments     = "SEG",

    -- 棋钟页没有「开始」按钮：开局靠拍对侧面板，所以这颗按钮只有暂停/继续两态，
    -- 按钮上只写一个字（P / C），完整含义由 README 与按钮位置说明
    btn_pause    = "P",
    btn_resume   = "C",
    btn_facing   = "180°",        -- 对坐模式开关（原来写 ⇅，字体没有该字形）

    time_up      = "TIME UP",
    wins         = "WINS",
    on_time      = "on time",

    btn_rematch  = "REMATCH",
    btn_back     = "MAIN MENU",
  },
  zh = {
    title        = "CoQ 棋钟",
    subtitle     = "手机 / 电脑都能用的比赛棋钟",

    mode         = "1. 计时模式",
    timing       = "2. 时间设置",
    start        = "开始对局",
    base_time    = "基础时间（分钟）",
    add_time     = "费舍尔加秒（秒）",
    delay_time   = "延时（秒）",
    byoyomi_time = "读秒（每手秒）",
    byoyomi_seg  = "读秒段数",
    presets      = "常用配置",
    sound        = "声音",
    sound_on     = "开",
    sound_off    = "关",
    theme        = "界面主题",
    theme_light  = "浅色",
    theme_medium = "中性",
    theme_dark   = "深色",
    summary      = "本局用时",

    how_start_1  = "点「开始对局」后没有第二次「开始」：由不该先走的一方（黑方）拍自己那侧 → 白方开始走",
    how_start_2  = "此后谁走完棋就拍自己那一侧，对方的钟随即开始计时",

    -- 「怎么用」现在单独一页：设置页只留入口，页内标题 / 返回按钮各一条
    how          = "怎么用",
    back         = "< 返回",
    preset_custom = "自定义",

    m_fischer    = "加秒",
    m_delay      = "延时",
    m_byoyomi    = "读秒",
    m_sudden     = "无加秒",

    white        = "白方",
    black        = "黑方",
    move         = "步数",
    waiting      = "等待",
    running      = "计时中",
    byoyomi      = "读秒中",
    paused       = "已暂停",
    paused_tag   = "暂停",
    ready_tag    = "待开始",
    segments     = "段",

    btn_pause    = "停",
    btn_resume   = "续",
    btn_facing   = "180°",

    time_up      = "超时",
    wins         = "获胜",
    on_time      = "对方超时",

    btn_rematch  = "再来一局",
    btn_back     = "返回设置",
  },
}

--- 取文案。缺字时回退到英文，再缺就回退到 key 本身（方便发现漏翻）
function M.t(key)
  local tbl = strings[M.LANG] or strings.en
  local v = tbl[key]
  if v == nil then v = strings.en[key] end
  if v == nil then v = key end
  return v
end

return M
