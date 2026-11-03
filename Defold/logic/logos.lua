--[[
  logos.lua — 标志循环（点一下换成下一个），与网页版 app.js 的 LOGO_ORDER / LOGO_FILES
             以及 Godot 版 logic/logos.gd 一一对应

      TARUMT → CoQ → Chess → 围棋 → MWA → 回到 TARUMT

  两项图片都在 assets/logo.atlas 里：
    brand_*  设置页 96×96 用（512 档原图）
    strip_*  棋钟操作条 48×48 用（192 档原图）
    logo     TARUMT 那一张（沿用原来的 logo.png，设置页与操作条共用）

  当前选的是哪一项存在存档里（cfg.logo），关掉再打开保持不变。
]]

local M = {}

M.ORDER = { "tarumt", "coq", "chess", "weiqi", "mwa" }

M.FILES = {
  tarumt = { name = "logo.name.tarumt", brand = "logo", strip = "logo" },
  coq    = { name = "logo.name.coq",    brand = "brand_coq",   strip = "strip_coq" },
  chess  = { name = "logo.name.chess",  brand = "brand_chess", strip = "strip_chess" },
  weiqi  = { name = "logo.name.weiqi",  brand = "brand_weiqi", strip = "strip_weiqi" },
  mwa    = { name = "logo.name.mwa",    brand = "brand_mwa",   strip = "strip_mwa" },
}

--- 不认识的值回落到第一项（存档里可能是旧版 / 手改的值）
function M.normalize(value)
  if type(value) == "string" and M.FILES[value] then return value end
  return M.ORDER[1]
end

--- 下一个标志（到头绕回第一项）
function M.next_id(value)
  local cur = M.normalize(value)
  for i, id in ipairs(M.ORDER) do
    if id == cur then return M.ORDER[(i % #M.ORDER) + 1] end
  end
  return M.ORDER[1]
end

function M.name_key(value) return M.FILES[M.normalize(value)].name end
function M.brand_anim(value) return M.FILES[M.normalize(value)].brand end
function M.strip_anim(value) return M.FILES[M.normalize(value)].strip end

return M
