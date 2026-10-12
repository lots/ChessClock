--[[
  text.lua — 界面文案（便于换语言 / 换成中文）
  ==================================================================
  默认英文：因为 Defold 内置字体（Vera Sans Mono Bold）只有 ASCII 字形，
  直接显示中文会变成空白方块。

  想改成中文：
    1) 把一个含中文字形的字体（例如思源黑体 NotoSansSC-Regular.ttf）放进
       assets/fonts/，在编辑器里右键 → New → Font，
       字符集填你在界面上用到的字（或勾 All Chars），尺寸 32，
       存成 assets/fonts/ui_zh.font；
    2) 把下面 LANG 改成 "zh"；
    3) 把 logic/ui.lua 里的 M.FONT_UI 指向 /assets/fonts/ui_zh.font。
  数字部分（时间）不受影响，它用的是 clock.font（只有 0-9 和 : . ）。
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
    delay_time   = "BRONSTEIN DELAY (SEC)",
    byoyomi_time = "BYOYOMI (SEC PER MOVE)",
    byoyomi_seg  = "BYOYOMI SEGMENTS",
    presets      = "PRESETS",
    sound        = "SOUND",
    sound_on     = "ON",
    sound_off    = "OFF",
    summary      = "THIS GAME",

    m_fischer    = "Fischer",
    m_delay      = "Bronstein",
    m_byoyomi    = "Byoyomi",
    m_sudden     = "Sudden",

    white        = "WHITE",
    black        = "BLACK",
    move         = "MOVE",
    waiting      = "READY",
    running      = "TO MOVE",
    byoyomi      = "BYOYOMI",
    paused       = "PAUSED",
    paused_tag   = "PAUSED",
    ready_tag    = "SET",
    segments     = "SEG",

    btn_start    = "START",
    btn_pause    = "PAUSE",
    btn_resume   = "RESUME",
    btn_sfx      = "SFX",
    btn_flip     = "FLIP",
    btn_menu     = "MENU",

    time_up      = "TIME UP",
    wins         = "WINS",
    on_time      = "on time",
    over         = "GAME OVER",

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
    delay_time   = "布朗斯坦延时（秒）",
    byoyomi_time = "每步读秒（秒）",
    byoyomi_seg  = "读秒段数",
    presets      = "常用配置",
    sound        = "声音",
    sound_on     = "开",
    sound_off    = "关",
    summary      = "本局用时",

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

    btn_start    = "开始",
    btn_pause    = "暂停",
    btn_resume   = "继续",
    btn_sfx      = "声音",
    btn_flip     = "翻转",
    btn_menu     = "设置",

    time_up      = "超时",
    wins         = "获胜",
    on_time      = "对方超时",
    over         = "对局结束",

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
