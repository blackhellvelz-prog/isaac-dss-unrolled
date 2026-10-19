-- Dead Sea Scrolls — меню свитком (автор blackhellvelz): широкий свиток, сетка рисованных иконок с подписями, общее окно
-- всех модов (свои меню DSS, разделы Mod Config Menu, деревья Passive Skill Trees). Мод Мастерской собирается
-- tools/build_workshop.py из модулей src/localfixes. Язык — по языку игры.
LOCALFIXES = LOCALFIXES or {}
if LOCALFIXES.AllInOne then
	Isaac.DebugString("[Scroll Menu] пропуск: стоит общая сборка localfixes")
	return
end
local mod = RegisterMod("Dead Sea Scrolls Unrolled", 1)
LOCALFIXES.Mod = mod
local ok, r = pcall(include, "dss_scroll")
if not ok then Isaac.DebugString("[Scroll Menu] dss_scroll: " .. tostring(r)) end
