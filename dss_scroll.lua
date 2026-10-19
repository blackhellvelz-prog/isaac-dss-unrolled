-- localfixes/dss_scroll.lua — меню Dead Sea Scrolls свитком: широкий развёрнутый свиток, сетка иконок с подписями и
-- общее окно всех модов (18.10, слова пользователя: «Сделай пошире и оформи как свиток / Чтобы соответствовало
-- «Свиткам мертвого моря»»; «Сделай не сплошной текст а иконки которые нужно выбирать с текстом под ним / Соответственно
-- само меню шире»; «Чтобы иконки модов были с страницы модов из Workshop»; «Чтобы было понятно по иконке что это за
-- мод / И сделать окно куда бы могли встраиваться другие моды»; «Если у мода нет своих меню в DSS отдели их в другой
-- пункт и закрась иконку серым»; «И сделай так чтобы это было автоматизировано»).
--
-- Как устроено (разбор ядра DSS v7, 18.10): у каждого мода своя копия ядра — она рисует его меню; общие у всех —
-- список меню (DeadSeaScrollsMenu.Menus) и бумага (DeadSeaScrollsMenu.GetDefaultPanelSprites). Здесь, без правки
-- 11 копий ядра:
--  - бумага: два новых вида панелей «lfscroll_main» и «lfscroll_tip» (свиток 320×256 и обрывок 128×128 —
--    tools/gen_dss_scroll.py; разворачивается и сворачивается анимацией);
--  - при первом открытии меню каждого ядра его панели формата по умолчанию (основная и подсказка) заменяются копиями
--    с геометрией свитка (шире) и своими крючками: GetDrawButtons (сетка — свою отрисовку), HandleInputs (стрелки —
--    по сетке, остальное — ядро: Enter перебирает значения настроек), RenderFront (сетка под рамкой), UpdateAppear
--    (ждать, пока свиток развернётся). Свои форматы модов (журналы, достижения, энциклопедия) не трогаются;
--  - сетка: выбираемые кнопки — ячейки (иконка, под ней подпись в 1–2 строки; у настроек — ещё и значение);
--    пояснения под кнопкой — в подсказку на обрывке; заголовки разделов — строкой; почти сплошной текст — как был;
--  - иконки: моды — картинки Workshop (modthumbs_index.lua, tools/mod_thumbs.py — сам собирает при установке),
--    пункты — иконки генератора «рукописью» (dss_icons_index.lua, tools/gen_dss_icons.py) по словам в тексте;
--  - общее окно: главная страница DSS — моды со своим меню DSS (цветные), пункт «другие моды» — остальные
--    установленные моды серыми (у кого есть раздел Mod Config Menu — открыть его там; дерево навыков — окно PST);
--    другие моды могут добавить себя: LOCALFIXES.ModHub.Add({ name =, open = function() end, thumb = id Workshop,
--    icon = имя иконки, mcm = раздел MCM }).
local LF = LOCALFIXES
local fontHasCyr                     -- ниже: шрифт свитка с кириллицей (menu_rfont Mod Translator) загружен
-- свой текст свитка — на языке игры (19.10, «Один мод, по языку игры»): русский — в русской игре, иначе английский;
-- без шрифта с кириллицей (нет Mod Translator) — английский: русские буквы вышли бы восклицательными знаками
local function L(ru, en)
	if fontHasCyr and not fontHasCyr() then return en end
	local H = LF.HandFont
	if H and H.L then return H.L(ru, en) end
	return Options.Language == "ru" and ru or en       -- без модуля меню (отдельный мод Мастерской) — язык игры
end
local function isRu()
	local H = LF.HandFont
	if H and H.IsRu then return H.IsRu() end
	return Options.Language == "ru"
end
local game = Game()
local sfx = SFXManager()
local GFX = "gfx/ui/localfixes/dss/"

local okF, FONT = pcall(include, "dss_fontdata")
local okI, ICON = pcall(include, "dss_icons_index")
local okT, THUMBS = pcall(include, "modthumbs_index")
if not okF or type(FONT) ~= "table" then FONT = {} end
if not okI or type(ICON) ~= "table" then ICON = {} end
local HAVE_THUMBS = okT and type(THUMBS) == "table"   -- include без файла не падает, а возвращает nil
if not HAVE_THUMBS then THUMBS = { mods = {}, cell = 44 } end

-- ------------------------------------------------------------------ геометрия (от центра панели)
local MAIN_OFF, TIP_OFF = Vector(-66, 2), Vector(162, -6)
local G = { left = -126, right = 126, top = -66, bottom = 92, cols = 4 }
local CELL_W = (G.right - G.left) / G.cols
local LINE = 9                      -- строка шрифта 12
local ICON_SZ = ICON.size or 44
local THUMB_SZ = THUMBS.cell or 44

-- ------------------------------------------------------------------ шрифт DSS (подписи сетки)
local font, rfontOK
local FNAMES = { "12", "16", "24" }
local function getFont()
	if font == nil then
		font = Sprite()
		font:Load("gfx/ui/deadseascrolls/menu_rfont.anm2", true)
		rfontOK = font:IsLoaded()
		if not rfontOK then font:Load("gfx/ui/deadseascrolls/menu_font.anm2", true) end
	end
	return font
end
fontHasCyr = function() getFont() return rfontOK end
-- заголовок страницы и текст подсказки рисует сам свиток (своим шрифтом с кириллицей), если игра русская, а ядра DSS
-- без правки этого ПК (мод из Мастерской: ядро рисует только латиницу; правка ставит флаг LOCALFIXES_DSS_CYR)
local function selfDraw()
	return isRu() and fontHasCyr() and not rawget(_G, "LOCALFIXES_DSS_CYR")
end
local function chars(str)
	local t = {}
	for _, c in utf8.codes(str) do t[#t + 1] = utf8.char(c) end
	return t
end
local function lowerAll(s)
	s = string.lower(s)
	return (s:gsub("\208([\129\144-\175])", function(c)
		local b = c:byte()
		if b == 129 then return "\209\145" end
		if b < 160 then return "\208" .. string.char(b + 32) end
		return "\209" .. string.char(b - 32)
	end))
end
local trCache = {}
local function tr(s)
	if type(s) ~= "string" then return "" end
	local r = trCache[s]
	if r then return r end
	r = s
	if LF and LF.TranslateDSS and fontHasCyr() then
		local ok, t = pcall(LF.TranslateDSS, s)
		if ok and type(t) == "string" then r = t end
	end
	r = lowerAll(r)
	trCache[s] = r
	return r
end
local function glyph(ch) return FONT[ch] or FONT["!"] end
-- строка → { ширина, кадры букв, сдвиги } — один раз на строку и размер (подписи сетки рисуются каждый кадр)
local runCache, runCount = { {}, {}, {} }, 0
local function textRun(str, size)
	local c = runCache[size]
	local r = c[str]
	if r then return r end
	if runCount > 3000 then runCache, runCount = { {}, {}, {} }, 0 c = runCache[size] end
	local frames, adv, w = {}, {}, 0
	for _, ch in ipairs(chars(str)) do
		local d = glyph(ch)
		if d then
			frames[#frames + 1] = d[1]
			adv[#adv + 1] = d[size + 1] + 1
			w = w + d[size + 1] + 1
		else
			w = w + 5
		end
	end
	r = { w = w, frames = frames, adv = adv }
	c[str] = r
	runCount = runCount + 1
	return r
end
local function textWidth(str, size) return textRun(str, size).w end
local ZERO = Vector.Zero
local function drawText(str, x, y, size, color)
	local f = getFont()
	local r = textRun(str, size)
	local px = x - r.w / 2
	f.Color = color
	f.Scale = Vector.One
	local anim = FNAMES[size]
	for i, fr in ipairs(r.frames) do
		f:SetFrame(anim, fr)
		f:Render(Vector(px, y), ZERO, ZERO)
		px = px + r.adv[i]
	end
end
local function cutTo(s, size, maxw)
	local cs = chars(s)
	while #cs > 1 and textWidth(table.concat(cs) .. "..", size) > maxw do cs[#cs] = nil end
	return table.concat(cs) .. ".."
end
local function wrap(str, size, maxw, maxlines)
	local lines, cur, cut = {}, "", false
	for word in str:gmatch("%S+") do
		local cand = cur == "" and word or (cur .. " " .. word)
		if textWidth(cand, size) <= maxw then
			cur = cand
		else
			if cur ~= "" then lines[#lines + 1] = cur end
			cur = word
			while textWidth(cur, size) > maxw do
				local cs = chars(cur)
				local n = #cs
				while n > 1 and textWidth(table.concat(cs, "", 1, n), size) > maxw do n = n - 1 end
				lines[#lines + 1] = table.concat(cs, "", 1, n)
				cur = table.concat(cs, "", n + 1)
				cut = true      -- слово не влезло в строку и разорвано
			end
		end
	end
	if cur ~= "" then lines[#lines + 1] = cur end
	if #lines > maxlines then
		local keep = {}
		for i = 1, maxlines do keep[i] = lines[i] end
		keep[maxlines] = cutTo(keep[maxlines], size, maxw)
		lines = keep
		cut = true
	end
	return lines, cut
end

-- ------------------------------------------------------------------ спрайты
local iconSpr, thumbSpr, symSpr
local function sprites()
	if not iconSpr then
		iconSpr = Sprite()
		iconSpr:Load(GFX .. "icons.anm2", true)
		iconSpr:SetAnimation("Icons", true)
		if HAVE_THUMBS then                           -- лист картинок модов (tools/mod_thumbs.py; нет файла — значки)
			thumbSpr = Sprite()
			thumbSpr:Load("gfx/ui/localfixes/modthumbs.anm2", true)
			thumbSpr:SetAnimation("Thumbs", true)
		end
		symSpr = Sprite()
		symSpr:Load("gfx/ui/deadseascrolls/menu_symbols.anm2", true)
	end
end
local GREY = Color(0.92, 0.92, 0.92, 1)
GREY:SetColorize(1, 1, 1, 1)

-- ------------------------------------------------------------------ моды: иконки Workshop и чьи меню
local byDss, byMcm, byId = {}, {}, {}
local function norm(s) return (lowerAll(tostring(s or "")):gsub("[^%w]", "")) end
-- моды — живой список игры (XMLData, запись MOD; только включённые — меню есть лишь у загруженных), в нём сколько модов
-- установлено, столько и пунктов (19.10: «Ты же понимаешь что это меню должно быть динамичный от количества скаченных
-- модов?»). Подсказки этого ПК (modthumbs_index.lua от tools/mod_thumbs.py: картинка Workshop, имена меню DSS и
-- разделов MCM из скана кода) — по папке мода, если есть; у игрока из Workshop их нет — меню и разделы находятся по
-- сходству названий, вместо картинки — значок рукописью
local MODS
local function mods()
	if MODS then return MODS end
	-- картинка — по номеру мода в Мастерской (лист: моды этого ПК и популярные моды Мастерской), у локального мода —
	-- по папке; в окне — только моды, установленные у игрока (19.10: «Моды которых нет на компьютере вообще не должны
	-- отображаться даже картинкой»), поэтому запасного списка из листа нет
	local byThumbId, byThumbDir = {}, {}
	for _, m in ipairs(THUMBS.mods or {}) do
		if m.id and m.id ~= "" then byThumbId[m.id] = m elseif m.folder and m.folder ~= "" then byThumbDir[m.folder] = m end
	end
	if LOCALFIXES_DSS_NOTHUMBS then byThumbId, byThumbDir = {}, {} end   -- отладка: вид без листа картинок
	local list = {}
	local okN, n = pcall(XMLData.GetNumEntries, XMLNode.MOD)
	for i = 1, (okN and type(n) == "number") and n or 0 do
		local ok, e = pcall(XMLData.GetEntryById, XMLNode.MOD, i)
		if ok and type(e) == "table" and e.name and tostring(e.enabled) == "true" then
			local folder = tostring(e.realdirectory or e.directory or "")
			local id = tostring(e.id or "")
			local t = (id ~= "" and byThumbId[id]) or byThumbDir[folder] or {}
			list[#list + 1] = { name = tostring(e.name):match("^%s*(.-)%s*$"), folder = folder, id = id,
				frame = t.frame, dss = t.dss or {}, mcm = t.mcm or {} }
		end
	end
	table.sort(list, function(a, b) return lowerAll(a.name) < lowerAll(b.name) end)
	for _, m in ipairs(list) do
		if m.id and m.id ~= "" then byId[m.id] = m end
		for _, d in ipairs(m.dss or {}) do byDss[d] = m end
		for _, c in ipairs(m.mcm or {}) do byMcm[c] = m end
	end
	MODS = list
	return list
end
-- расстояние правки (опечатки в именах меню: у Encyclopedia меню DSS — «Encylopedia»)
local function editDist(a, b)
	if math.abs(#a - #b) > 2 then return 99 end
	local prev = {}
	for j = 0, #b do prev[j] = j end
	for i = 1, #a do
		local cur = { [0] = i }
		for j = 1, #b do
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a:byte(i) == b:byte(j) and 0 or 1))
		end
		prev = cur
	end
	return prev[#b]
end
-- мод по сходству названий: имя целиком внутри имени мода (10), аббревиатура имени мода (10: «EID» — External Item
-- Descriptions), слова от трёх букв (по 2), слово с одной опечаткой (2; с двумя «reworked» находил «Mantle Rework»);
-- имя после «for» в имени мода — это аддон к другому моду («Last Judgement Resprites for Reworked Foes» — не сам
-- «Reworked Foes»): совпадение там не считается
local function similarMod(cat)
	local nc = norm(cat)
	local best, bestScore = nil, 0
	for _, m in ipairs(mods()) do
		local lname = lowerAll(m.name)
		lname = lname:gsub("%s+for%s+.*$", "")
		local nm = norm(lname)
		local sc = 0
		if nc ~= "" and nm:find(nc, 1, true) then sc = 10 end
		if #nc >= 2 and #nc <= 5 then
			local ini = {}
			for w in lname:gmatch("%a+") do ini[#ini + 1] = w:sub(1, 1) end
			if table.concat(ini) == nc then sc = sc + 10 end
		end
		for word in lowerAll(cat):gmatch("%a%a%a+") do
			if lname:find(word, 1, true) then
				sc = sc + 2
			elseif #word >= 6 then
				for w2 in lname:gmatch("%a+") do
					if editDist(word, w2) <= 1 then sc = sc + 2 break end
				end
			end
		end
		if sc > bestScore then best, bestScore = m, sc end
	end
	if bestScore >= 2 then return best end
end
-- раздел MCM → мод (разделы, заданные в коде переменной, — по сходству)
local function modForMcm(cat)
	mods()
	if byMcm[cat] then return byMcm[cat] end
	local m = similarMod(cat)
	if m then byMcm[cat] = m end
	return m
end
-- меню DSS → мод
local function modForDss(name)
	mods()
	if byDss[name] then return byDss[name] end
	local m = similarMod(name)
	if m then byDss[name] = m end
	return m
end
local function cleanName(n)
	n = tostring(n or "")
	n = n:gsub("%b[]", ""):gsub("%b()", ""):gsub("^[%s!~%.%-_'\"]+", ""):gsub("%s+$", "")
	return n ~= "" and n or tostring(n)
end

-- ------------------------------------------------------------------ текст кнопки по-русски
-- str — словарём строк; strset — словарём наборов (там перевод целой фразой, уже разбитый на строки старой ширины:
-- «lag reduction» → «меньше / лагов»), иначе — построчно (18.10, автопроверка: такие строки оставались английскими)
local function joinLines(t)
	local out = ""
	for _, l in ipairs(t) do
		l = tostring(l)
		if out == "" then out = l
		elseif out:sub(-1) == "-" then out = out .. l      -- перенос по слогам в словаре: «девочек-» + «зайчиков»
		else out = out .. " " .. l end
	end
	return out
end
local function setLines(set)
	if LF.TranslateDSSSet and fontHasCyr() then
		local ok, t = pcall(LF.TranslateDSSSet, set)
		if ok and type(t) == "table" and t ~= set then
			local r = {}
			for i, l in ipairs(t) do r[i] = lowerAll(tostring(l)) end
			return r
		end
	end
	local r = {}
	for i, l in ipairs(set) do r[i] = tr(tostring(l)) end
	return r
end
local capCache = setmetatable({}, { __mode = "k" })
local function capText(b)
	if type(b.str) == "string" then return tr(b.str) end
	if type(b.strset) == "table" then
		local key = table.concat(b.strset, "\n")
		local c = capCache[b]
		if c and c.key == key then return c.text end
		local text = joinLines(setLines(b.strset))
		capCache[b] = { key = key, text = text }
		return text
	end
	return ""
end

-- ------------------------------------------------------------------ иконка пункта по словам
local KEYWORDS = {
	{ "yes", { "enable all", "unlock all", "включить всё", "включить все", "открыть всё", "открыть все" } },
	{ "no", { "disable all", "lock all", "выключить всё", "выключить все", "закрыть всё", "закрыть все", "заблокировать вс" } },
	{ "reset", { "default", "по умолчанию", "стандартн" } },
	{ "resume", { "resume", "continue", "вернуться", "продолжить" } },
	{ "menusettings", { "menu settings", "настройки меню" } },
	{ "palette", { "palette", "палитр", "colou", "цвет" } },
	{ "hud", { "hud", "интерфейс", "портрет" } },
	{ "music", { "music", "sound", "sfx", "volume", "звук", "музык", "громк" } },
	{ "controls", { "keybind", "hotkey", "gamepad", "controller", "joystick", "analog", "клавиш", "хоткей", "геймпад", "управлен", "кнопк" } },
	{ "cursor", { "cursor", "mouse", "курсор", "мыш" } },
	{ "unlocks", { "unlock", "анлок", "открыт" } },
	{ "progress", { "progress", "completion", "marks", "achievement", "прогресс", "отметк", "достижен", "ачив", "full marks" } },
	{ "credits", { "credit", "автор", "thanks" } },
	{ "changelog", { "changelog", "изменени", "patch", "version", "верси", "wave ", "волна " } },
	{ "notes", { "notes", "заметк", "записк", "info", "сведени" } },
	{ "challenge", { "challenge", "испытан" } },
	{ "bosses", { "boss", "босс" } },
	{ "enemies", { "enem", "monster", "foe", "враг", "монстр" } },
	{ "characters", { "character", "персонаж", "перс.", "исаак", "магдалин", "каин", "иуда", "???", "самсон",
		"азазель", "лазарь", "эдем", "потерянн", "лилит", "хранител", "keeper", "аполлион", "забыт", "вифани", "иаков" } },
	{ "trinket", { "trinket", "брелок" } },
	{ "items", { "item", "предмет", "collectible" } },
	{ "pickups", { "pickup", "coin", "подбор", "монет" } },
	{ "hearts", { "heart", "health", "сердц", "здоров" } },
	{ "reset", { "reset", "сброс", "clear", "очист", "random", "случайн" } },
	{ "commands", { "command", "debug", "console", "команд", "отладк" } },
	{ "manager", { "bypass", "manager", "менеджер", "обход" } },
	{ "fun", { "wack", "fun", "silly", "глупост", "шутк", "насмеш" } },
	{ "popup", { "popup", "notif", "уведомл", "всплыв", "hint", "подсказк", "предсказ" } },
	{ "data", { "data", "данн", "harvest", "sync", "синхрон", "связь с" } },
	{ "language", { "language", "translat", "перевод", "язык" } },
	{ "map", { "map", "карт", "room", "комнат" } },
	{ "difficulty", { "difficult", "сложност", "hard" } },
	{ "visual", { "visual", "effect", "эффект", "графи", "shader", "шейдер", "вид" } },
	{ "settings", { "setting", "настройк", "option", "опци", "config" } },
}
-- короткие ответы — только целым словом («no» не должно цеплять «notes», «нет» — «монет»)
local EXACT_ICON = {
	["yes"] = "yes", ["да"] = "yes", ["ok"] = "yes", ["confirm"] = "yes", ["подтвердить"] = "yes", ["accept"] = "yes",
	["no"] = "no", ["нет"] = "no", ["cancel"] = "no", ["отмена"] = "no", ["отменить"] = "no",
	["back"] = "back", ["назад"] = "back", ["return"] = "back", ["вернуться"] = "back",
	["everything"] = "unlocks", ["всё"] = "unlocks", ["все"] = "unlocks",
	["write"] = "write", ["write!"] = "write", ["записать"] = "write", ["записать!"] = "write", ["написать!"] = "write",
}
local function trim(x) return (x:gsub("^%s+", ""):gsub("%s+$", "")) end
local function iconFor(b)
	local raw = type(b.str) == "string" and b.str or (type(b.strset) == "table" and table.concat(b.strset, " ") or "")
	if b.lfIconName and b.lfIconFor == raw then return b.lfIconName end
	b.lfIconFor = raw
	b.lfIconName = (function()
	local low, ru = trim(lowerAll(raw)), trim(capText(b))
	if EXACT_ICON[low] then return EXACT_ICON[low] end
	if EXACT_ICON[ru] then return EXACT_ICON[ru] end
	local s = lowerAll(raw .. " " .. ru .. " " .. tostring(b.variable or "") .. " " .. tostring(b.dest or ""))
	for _, kw in ipairs(KEYWORDS) do
		for _, w in ipairs(kw[2]) do
			if s:find(w, 1, true) then return kw[1] end
		end
	end
	if b.variable or b.choices or b.max or b.keybind then return "setting" end
	return "page"
	end)()
	return b.lfIconName
end

-- ------------------------------------------------------------------ разметка страницы
local function btnText(b)
	if type(b.str) == "string" then return b.str end
	if type(b.str) == "table" then                     -- журналы изменений: строка — кусочки { str =, color = }
		local parts = {}
		for _, p in ipairs(b.str) do
			if type(p) == "table" and type(p.str) == "string" then parts[#parts + 1] = p.str
			elseif type(p) == "string" then parts[#parts + 1] = p end
		end
		return table.concat(parts)
	end
	if type(b.strset) == "table" then return table.concat(b.strset, " ") end
	return ""
end
local function hasValue(b) return (b.variable or b.setting) and (b.choices or b.max or b.keybind) and true or false end
local KEYNAMES
local function keyName(k)
	if not KEYNAMES then
		KEYNAMES = {}
		for name, v in pairs(Keyboard) do KEYNAMES[v] = name:gsub("^KEY_", ""):gsub("_", " "):lower() end
	end
	if k == nil or k == -1 then return "нет" end
	return KEYNAMES[k] or tostring(k)
end
local function valueText(b)
	if b.keybind then return b.keybinding and L("[жду клавишу]", "[press a key]") or ("[" .. keyName(b.setting) .. "]") end
	if b.choices then return tr(tostring(b.choices[b.setting or 1] or "")) end
	if b.slider then return nil end
	if b.max then return tostring(b.pref or "") .. tostring(b.setting or 0) .. tostring(b.suf or "") end
	return nil
end

local function gridOn(item)
	if type(item) ~= "table" or type(item.buttons) ~= "table" or item.pages or item.scroller or item.gridx or item.lfNoGrid then
		return false
	end
	if item.lfGrid ~= nil then return item.lfGrid end      -- мод может сам включить или выключить сетку страницы
	local title = lowerAll(tostring(item.title or ""))
	if title:find("credit", 1, true) or title:find("thanks", 1, true) or title:find("авторы", 1, true) then return false end
	local sel, text = 0, 0
	for _, b in ipairs(item.buttons) do
		if not b.forcenodisplay then
			if b.spr or b.strpair then return false end
			if not b.nosel then
				if not btnText(b):match("%S") then return false end   -- кнопка без текста — свой рисунок мода
				sel = sel + 1
			elseif btnText(b):match("%S") then text = text + 1 end
		end
	end
	return sel >= 2 and text <= sel * 2 + 6
end

-- кнопка с названием мода (разделы Энциклопедии «Fiend Folio», «Epiphany» …) — картинка мода из Workshop
local byCaption = {}
local function modByCaption(text)
	local n = norm(text)
	if #n < 5 then return nil end
	local hit = byCaption[n]
	if hit ~= nil then return hit or nil end
	hit = false
	-- 1) имя меню DSS мода («Lost n Forgotten», «Fiend Folio», «Epiphany»), 2) начало имени Workshop, 3) имя внутри
	-- имени Workshop («Damn, Fiend Folio: RELOADED», «[Rep] The Binding of Isaac: Epiphany») — от точного к общему
	for pass = 1, 3 do
		for _, m in ipairs(mods()) do
			if m.frame then
				local nm = norm(cleanName(m.name))
				local ok = false
				if pass == 1 then
					for _, dn in ipairs(m.dss or {}) do if norm(dn) == n then ok = true end end
				elseif pass == 2 then
					ok = #nm >= 5 and (nm == n or nm:sub(1, #n) == n or n:sub(1, #nm) == nm)
				else
					ok = #n >= 8 and nm:find(n, 1, true) ~= nil   -- 8+: «vanilla» не должно находить «Better Vanilla Monsters»
				end
				if ok then hit = m break end
			end
		end
		if hit then break end
	end
	byCaption[n] = hit
	return hit or nil
end
local function cellIcon(e)
	local b = e.btn
	if b.lfThumb ~= nil then return "thumb", b.lfThumb, b.lfGrey end
	local dm = b.menu and modForDss(b.menu)
	if dm and dm.frame then return "thumb", dm.frame, false end
	if not b.lfIcon and type(b.str) == "string" then
		local m = modByCaption(b.str)
		if m and m.frame then return "thumb", m.frame, false end
	end
	if b.lfIcon then return "icon", ICON[b.lfIcon] or ICON.page, b.lfGrey end
	local name = iconFor(b)
	-- пункт без своей темы (общий значок настройки) — тема страницы по заголовку («новые враги» → муха)
	if (name == "setting" or name == "page") and e.pageIcon then name = e.pageIcon end
	-- списки разблокировок: у закрытого пункта — закрытый замок (по значению настройки «закрыто» / «locked»)
	if name == "unlocks" and ICON.locked and (b.choices or b.max) then
		local v = valueText(b)
		if v and (v:find("закрыт", 1, true) or v:find("lock", 1, true) or v:find("нет", 1, true)) then
			return "icon", ICON.locked, false
		end
	end
	return "icon", ICON[name] or ICON.page, false
end

-- страницы: ряды (заголовки и ряды ячеек) раскладываются по страницам высотой PAGE_H; ход — слева направо
-- (18.10, «Сделай так чтобы он был с слева направо и разметка страниц»)
local PAGE_H = G.bottom - G.top - 12        -- внизу — номер страницы
local function visSig(item)
	local n, sum = 0, 0
	for i, b in ipairs(item.buttons) do
		if not b.forcenodisplay then n = n + 1 sum = sum + i end
	end
	return n * 100000 + sum
end
-- кэш годен, пока тот же список кнопок (ядро пересоздаёт главную страницу при каждом новом меню), те же кнопки
-- на своих местах и те же подписи (у части модов подпись меняется на ходу)
local function layoutValid(item, sig)
	local L = item.lfLayout
	if not L or item.lfLayoutSig ~= sig or L.buttons ~= item.buttons then return false end
	for _, e in ipairs(L.cells) do
		if item.buttons[e.idx] ~= e.btn or btnText(e.btn) ~= e.src then return false end
	end
	return true
end

-- колонки: 4, если все подписи влезают в 2 строки без разрыва слов; иначе 3, иначе 2 (18.10, автопроверка: 83 подписи
-- резались — «переполненн | ая», «сердце | мамы/оно..»)
local COLS = { 4, 3, 2 }
local function cellW(cols) return (G.right - G.left) / cols end
local function layout(item)
	local sig = visSig(item)
	if layoutValid(item, sig) then return item.lfLayout end
	local entries, cells = {}, {}
	local last, blank = nil, true
	for i, b in ipairs(item.buttons) do
		if not b.forcenodisplay then
			local t = btnText(b)
			if not b.nosel then
				local e = { btn = b, idx = i }
				entries[#entries + 1] = e
				cells[#cells + 1] = e
				last, blank = e, false
			elseif t:match("%S") then
				if last and not blank then
					last.desc = last.desc or {}
					local lines = type(b.strset) == "table" and setLines(b.strset) or { tr(t) }
					for _, l in ipairs(lines) do last.desc[#last.desc + 1] = l end
				else
					entries[#entries + 1] = { head = b }
					last = nil
				end
			else
				blank, last = true, nil
			end
		end
	end
	-- пояснения под кнопкой — в подсказку на обрывке (если своей подсказки у кнопки нет); уже по-русски
	for _, e in ipairs(cells) do
		if e.desc and not e.btn.tooltip and not e.btn.lfTip then
			e.btn.tooltip = { strset = e.desc }
			e.btn.lfTip = true
		end
	end
	-- колонки — по рядам (18.10: в «других модах» два длинных имени уводили всю сетку в 2 колонки, 11 страниц): ряд
	-- открывается на столько колонок, сколько вмещает подпись первой ячейки без разрыва слов (4 → 3 → 2); следующая
	-- ячейка, которой тесно, сужает ряд, если в нём ещё есть место, иначе начинает новый ряд
	local function fitCols(e)
		local t = capText(e.btn)
		for _, c in ipairs(COLS) do
			local _, cut = wrap(t, 1, cellW(c) - 4, 2)
			if not cut then return c end
		end
		return COLS[#COLS]
	end
	local pageIcon = type(item.title) == "string" and iconFor({ str = item.title }) or nil
	if pageIcon == "page" or pageIcon == "setting" or pageIcon == "settings" or pageIcon == "menusettings" then pageIcon = nil end
	for _, e in ipairs(cells) do e.pageIcon = pageIcon end
	local rows, cur = {}, nil
	for _, e in ipairs(entries) do
		if e.head then
			cur = nil
			local lines, cut = wrap(capText(e.head), 1, G.right - G.left - 8, 3)
			rows[#rows + 1] = { head = lines, h = #lines * LINE + 4, cut = cut, src = btnText(e.head) }
		else
			local fc = fitCols(e)
			if cur and #cur.cells < math.min(cur.cols, fc) then
				cur.cols = math.min(cur.cols, fc)
			else
				cur = { cells = {}, h = 0, ih = 0, cols = fc }
				rows[#rows + 1] = cur
			end
			cur.cells[#cur.cells + 1] = e
			e.row, e.col = #rows, #cur.cells
			e.src = btnText(e.btn)
			local kind = cellIcon(e)
			local ih = (kind == "thumb" and THUMB_SZ or ICON_SZ) + 2
			if ih > cur.ih then cur.ih = ih end
		end
	end
	for _, r in ipairs(rows) do
		if r.cells then
			r.cw = cellW(r.cols)
			for _, e in ipairs(r.cells) do e.caption, e.cut = wrap(capText(e.btn), 1, r.cw - 4, 2) end
		end
	end
	for _, r in ipairs(rows) do
		if r.cells then
			local mh = 0
			for _, e in ipairs(r.cells) do
				local h = #e.caption * LINE + ((hasValue(e.btn) or e.btn.slider) and LINE or 0)
				if h > mh then mh = h end
			end
			r.h = r.ih + mh + 4
		end
	end
	-- по страницам; заголовок в конце страницы переносится на следующую вместе со своим рядом
	local pages, page, used = {}, nil, 0
	for ri, r in ipairs(rows) do
		local need = r.h
		if r.head and rows[ri + 1] and rows[ri + 1].cells then need = need + rows[ri + 1].h end
		if not page or (used + need > PAGE_H and #page.rows > 0) then
			page = { rows = {} }
			pages[#pages + 1] = page
			used = 0
		end
		page.rows[#page.rows + 1] = r
		r.page = #pages
		r.py = used
		used = used + r.h
	end
	for _, e in ipairs(cells) do e.page = rows[e.row].page end
	for _, pg in ipairs(pages) do
		pg.cellRows = {}
		for _, r in ipairs(pg.rows) do if r.cells then pg.cellRows[#pg.cellRows + 1] = r end end
	end
	local L = { rows = rows, cells = cells, pages = pages, buttons = item.buttons }
	item.lfLayout, item.lfLayoutSig = L, sig
	return L
end

-- ход: влево/вправо — по порядку (через край страницы — на соседнюю), вверх/вниз — по рядам своей страницы
local function navigate(L, bsel, dir)
	local curI
	for i, e in ipairs(L.cells) do if e.idx == bsel then curI = i break end end
	if not curI then return L.cells[1] and L.cells[1].idx end
	local cur = L.cells[curI]
	if dir == "l" then return L.cells[(curI - 2) % #L.cells + 1].idx end
	if dir == "r" then return L.cells[curI % #L.cells + 1].idx end
	local pg = L.pages[cur.page]
	local rowsC = pg.cellRows
	local pos
	for k, r in ipairs(rowsC) do if r == L.rows[cur.row] then pos = k end end
	if not pos then return bsel end
	local nk = dir == "u" and pos - 1 or pos + 1
	if nk < 1 then nk = #rowsC elseif nk > #rowsC then nk = 1 end
	local row = rowsC[nk]
	return row.cells[math.min(cur.col, #row.cells)].idx
end

-- ------------------------------------------------------------------ отрисовка сетки
local function drawPage(L, pg, pos, ox, sel, cText, cHi, frame)
	local top = pos.Y + G.top
	for _, r in ipairs(pg.rows) do
		local ry = top + r.py
		if r.head then
			for k, line in ipairs(r.head) do
				drawText(line, pos.X + ox, ry + 2 + (k - 1) * LINE, 1, Color(cText.R, cText.G, cText.B, 0.8, 0, 0, 0))
			end
		else
			local n = #r.cells
			local cols, CW = r.cols, r.cw
			local x0 = pos.X + ox + G.left + (cols - n) * CW / 2
			for c, e in ipairs(r.cells) do
				local cx = x0 + CW * (c - 0.5)
				if cx > pos.X + G.left - 40 and cx < pos.X + G.right + 40 then
					local selected = (e == sel)
					local kind, frameNo, grey = cellIcon(e)
					if kind == "thumb" and not (thumbSpr and frameNo) then kind, frameNo = "icon", ICON.page end   -- нет листа (Мастерская)
					local bob = selected and math.sin(frame * 0.2) * 1.5 - 1 or 0
					local spr = kind == "thumb" and thumbSpr or iconSpr
					spr:SetFrame(kind == "thumb" and "Thumbs" or "Icons", frameNo or 0)
					spr.Color = grey and GREY or Color.Default
					spr:Render(Vector(cx, ry + r.ih / 2 + bob), Vector.Zero, Vector.Zero)
					local ty = ry + r.ih
					local col = selected and cHi or cText
					for k, line in ipairs(e.caption) do drawText(line, cx, ty + (k - 1) * LINE, 1, col) end
					local vy = ty + #e.caption * LINE
					local val = valueText(e.btn)
					if val then
						if textWidth(val, 1) > CW + 6 then val = cutTo(val, 1, CW + 6) end
						drawText(val, cx, vy, 1, Color(cHi.R, cHi.G, cHi.B, selected and 1 or 0.75, 0, 0, 0))
					elseif e.btn.slider and e.btn.max then
						local nT = math.ceil(e.btn.max / (e.btn.increment or 1))
						local on = math.floor((e.btn.setting or 0) / (e.btn.increment or 1))
						local str = ""
						for t = 1, nT do str = str .. (t <= on and "i" or ".") end
						drawText(str, cx, vy, 1, cHi)
					end
				end
			end
		end
	end
end

local function drawGrid(panel, pos, tbl)
	local dk = tbl.DirectoryKey
	local item = dk and dk.Item
	if not gridOn(item) then return end
	sprites()
	local L = layout(item)
	local pal = DeadSeaScrollsMenu.GetPalette()
	local cText, cHi = pal[2] or Color(0.2, 0.2, 0.2, 1), pal[3] or Color(0.4, 0.2, 0.2, 1)
	local sel
	for _, e in ipairs(L.cells) do if e.idx == item.bsel then sel = e break end end
	local np = #L.pages
	local cur = sel and sel.page or 1
	-- перелистывание: старая страница уезжает, новая въезжает (вперёд — справа налево, назад — наоборот)
	if item.lfPage ~= cur then
		if item.lfPage and item.lfPage <= np then
			item.lfFrom = item.lfPage
			local fwd = cur > item.lfPage
			if cur == 1 and item.lfPage == np then fwd = true end
			if cur == np and item.lfPage == 1 and np > 1 then fwd = false end
			item.lfSlide = fwd and 1 or -1
			item.lfT = 0
		end
		item.lfPage = cur
	end
	local frame = game:GetFrameCount()
	local span = G.right - G.left + 20
	if item.lfT and item.lfT < 1 and item.lfFrom and L.pages[item.lfFrom] then
		item.lfT = math.min(1, item.lfT + 0.2)
		local t = 1 - (1 - item.lfT) ^ 2
		local dir = item.lfSlide or 1
		drawPage(L, L.pages[item.lfFrom], pos, -dir * span * t, nil, cText, cHi, frame)
		drawPage(L, L.pages[cur], pos, dir * span * (1 - t), sel, cText, cHi, frame)
	else
		drawPage(L, L.pages[cur], pos, 0, sel, cText, cHi, frame)
	end
	-- номер страницы и стрелки
	if np > 1 then
		local y = pos.Y + G.bottom - 9
		drawText(cur .. " / " .. np, pos.X, y, 1, cText)
		local jump = math.sin(frame * 0.15) * 1.2
		drawText("<", pos.X - 26 - jump, y, 1, cHi)
		drawText(">", pos.X + 26 + jump, y, 1, cHi)
	end
end

-- страница, где ядро спрятало все кнопки (у не главного ядра DSS «настройки меню» — общие кнопки ядра, их показывает
-- только главное; 18.10, обход: Epiphany → «настройки меню» была пустой) — пояснение вместо пустого листа
local EMPTY_NOTE_RU = { "здесь пусто:", "эти настройки - в общем", "меню \"свитки мёртвого моря\"", "(клавиша c или f1)" }
local EMPTY_NOTE_EN = { "nothing here:", "these settings are in the", "shared \"dead sea scrolls\"", "menu (key c or f1)" }
local function drawEmptyNote(pos, tbl)
	local item = tbl and tbl.DirectoryKey and tbl.DirectoryKey.Item
	if type(item) ~= "table" or type(item.buttons) ~= "table" or #item.buttons == 0 or item.format then return end
	for _, b in ipairs(item.buttons) do
		if not b.forcenodisplay and (btnText(b):match("%S") or b.spr) then return end
	end
	local pal = DeadSeaScrollsMenu.GetPalette()
	local c = pal[2] or Color(0.2, 0.2, 0.2, 1)
	for k, line in ipairs(L(EMPTY_NOTE_RU, EMPTY_NOTE_EN)) do
		drawText(line, pos.X, pos.Y - 20 + (k - 1) * (LINE + 2), 1, Color(c.R, c.G, c.B, 0.8, 0, 0, 0))
	end
end

-- заголовок страницы и текст обрывка-подсказки — своим шрифтом, когда ядро DSS кириллицу не рисует (selfDraw): как у
-- ядра — заголовок крупным шрифтом по центру с подчёркиванием (символ Sym 0), подсказка — строки по центру обрывка
local SCALER = { 8, 12, 16 }
local drawErr = {}
local function safeDraw(name, f, ...)            -- ошибка отрисовки — один раз в лог (pcall глотал её молча)
	local ok, err = pcall(f, ...)
	if not ok and not drawErr[name] then
		drawErr[name] = true
		Isaac.DebugString("[localfixes] dss_scroll " .. name .. ": " .. tostring(err))
	end
end
local function drawTitle(pos, tbl)
	local item = tbl and tbl.DirectoryKey and tbl.DirectoryKey.Item
	if type(item) ~= "table" or type(item.title) ~= "string" or item.title == "" then return end
	local pal = DeadSeaScrollsMenu.GetPalette()
	local c = pal[3] or Color(0.37, 0.22, 0.24, 1)
	local y = pos.Y - 90
	drawText(tr(item.title), pos.X, y, 3, c)
	sprites()
	symSpr.Color = c
	symSpr:SetFrame("Sym", 0)
	symSpr:Render(Vector(pos.X, y + 16 + SCALER[3] / 2), ZERO, ZERO)
end
local function drawTip(pos, tbl)
	local item = tbl and tbl.DirectoryKey and tbl.DirectoryKey.Item
	if type(item) ~= "table" then return end
	local tip = (type(item.selectedbutton) == "table" and item.selectedbutton.tooltip) or item.tooltip
	if type(tip) ~= "table" then return end
	local size = tip.fsize or 2
	local lines
	if type(tip.strset) == "table" then
		lines = setLines(tip.strset)
	elseif type(tip.buttons) == "table" then
		lines = {}
		for _, b in ipairs(tip.buttons) do
			if type(b.strset) == "table" then
				for _, l in ipairs(setLines(b.strset)) do lines[#lines + 1] = l end
			else
				lines[#lines + 1] = tr(btnText(b))
			end
			size = b.fsize or size
		end
	elseif type(tip.str) == "string" then
		lines = { tr(tip.str) }
	end
	if not lines or #lines == 0 then return end
	local lh = SCALER[size] + (size == 1 and 1 or 2)
	-- не влезает по ширине обрывка — шрифт меньше
	while size > 1 do
		local wide = false
		for _, l in ipairs(lines) do if textWidth(l, size) > 112 then wide = true break end end
		if not wide then break end
		size = size - 1
		lh = SCALER[size] + (size == 1 and 1 or 2)
	end
	local pal = DeadSeaScrollsMenu.GetPalette()
	local c = pal[2] or Color(0.21, 0.18, 0.18, 1)
	local y0 = pos.Y + 2 - (#lines * lh) / 2
	for k, l in ipairs(lines) do
		drawText(l, pos.X + 2, y0 + (k - 1) * lh, size, c)
	end
end

-- ------------------------------------------------------------------ панели-свитки
local SETS = {}
local function loadSet(kind)
	local t = {}
	for key, lay in pairs({ Shadow = "shadow", Back = "back", Face = "face", Border = "border", Mask = "mask" }) do
		local s = Sprite()
		s:Load(GFX .. "scroll_" .. kind .. ".anm2", false)
		s:ReplaceSpritesheet(0, GFX .. "scroll_" .. kind .. "_" .. lay .. ".png")
		s:LoadGraphics()
		t[key] = s
	end
	return t
end
local function installSprites()
	local d = DeadSeaScrollsMenu
	if not d or d.lfScrollSprites or not d.GetDefaultPanelSprites then return end
	local orig = d.GetDefaultPanelSprites
	d.GetDefaultPanelSprites = function(kind)
		if kind == "lfscroll_main" or kind == "lfscroll_tip" then
			SETS[kind] = SETS[kind] or loadSet(kind == "lfscroll_main" and "main" or "tip")
			return SETS[kind]
		end
		return orig(kind)
	end
	d.lfScrollSprites = true
end

-- ------------------------------------------------------------------ кириллица у ядра DSS без правки (Мастерская)
-- 19.10 (пользователь: «В целом все такие надписи внутри DSS надо перевести»): на этом ПК ядра DSS поправлены файлами
-- (apply_fixes dss_cyrillic: UTF-8, кириллица, перевод на выводе). В моде из Мастерской файлы не правятся, но главное
-- ядро — у Encyclopedia, а она выкладывает его таблицу символов (Encyclopedia.mfdat), шрифт же ядро берёт из общей
-- таблицы спрайтов (DeadSeaScrollsMenu.MenuSprites.Font). Ядро перебирает строку по байтам, поэтому русская буква
-- (2 байта UTF-8) — это первый байт D0/D1 шириной 0 (пустой кадр) и второй байт — кадр буквы из шрифта menu_rfont
-- (Mod Translator; тот же, что у правки ядер). Строчные: а-п — D0 B0–BF, р-я — D1 80–8F, ё — D1 91: вторые байты не
-- пересекаются; заглавные (D0 90–AF, кроме Б — её 91 занят ё) рисуются строчными. Перевод: текстовые страницы ядро
-- рисует из прокси кнопок с переведёнными строками (их отдаёт наш GetDrawButtons; выбор и прочее — из самой кнопки),
-- заголовок и подсказку — сам свиток (drawTitle, drawTip).
local cyrRT = false
local function installCyrRT()
	if cyrRT then return true end
	if rawget(_G, "LOCALFIXES_DSS_CYR") or not isRu() or not fontHasCyr() then return false end
	local D, E = rawget(_G, "DeadSeaScrollsMenu"), rawget(_G, "Encyclopedia")
	local M = type(E) == "table" and rawget(E, "mfdat")
	if type(D) ~= "table" or type(M) ~= "table" or type(D.CoreMod) ~= "string"
		or not D.CoreMod:lower():find("encyclopedia", 1, true) or type(M[" "]) ~= "table" then return false end
	for ch, d in pairs(FONT) do
		if #ch == 2 then
			local b1, b2 = ch:byte(1, 2)
			if (b1 == 208 and b2 >= 176) or (b1 == 209 and (b2 <= 143 or b2 == 145)) then M[ch:sub(2, 2)] = d end
		end
	end
	for b2 = 144, 175 do                               -- заглавные А-Я → кадры строчных (кроме Б: 91 — ё)
		if b2 ~= 145 then
			local low = b2 < 160 and ("\208" .. string.char(b2 + 32)) or ("\209" .. string.char(b2 - 32))
			if FONT[low] and M[string.char(b2)] == nil then M[string.char(b2)] = FONT[low] end
		end
	end
	local blank = { M[" "][1], -1, -1, -1 }
	M["\208"], M["\209"] = blank, blank
	cyrRT = true
	rawset(_G, "LOCALFIXES_DSS_CYR_RT", true)
	Isaac.DebugString("[localfixes] свиток DSS: кириллица у ядра без правки — включена (Encyclopedia.mfdat, menu_rfont)")
	return true
end
local refonted = setmetatable({}, { __mode = "k" })
local function refont(ms)
	local f = type(ms) == "table" and ms.Font
	if f and not refonted[f] and f.Load then
		refonted[f] = true
		f:Load("gfx/ui/deadseascrolls/menu_rfont.anm2", true)
	end
end
local function refontAll()
	local D = DeadSeaScrollsMenu
	refont(D.MenuSprites)
	for _, m in pairs(D.Menus or {}) do if type(m) == "table" then refont(m.MenuSprites) end end
end
-- прокси кнопки: переведённые строки поверх самой кнопки (кэш — пока строки кнопки те же)
local PROXY = setmetatable({}, { __mode = "k" })
local function trStrTable(t)
	local out = {}
	for i, v in ipairs(t) do
		if type(v) == "string" then out[i] = tr(v)
		elseif type(v) == "table" then
			local c = setmetatable({}, { __index = v })
			if type(v.str) == "string" then c.str = tr(v.str) end
			out[i] = c
		else out[i] = v end
	end
	return out
end
local function sig(b)
	return tostring(b.str) .. "|" .. tostring(b.strset) .. "|" .. tostring(b.strpair) .. "|" .. tostring(b.choices)
		.. "|" .. tostring(b.pref) .. "|" .. tostring(b.suf)
end
local function proxyOf(b)
	local c = PROXY[b]
	local sg = sig(b)
	if c and c.lfSig == sg then return c.px end
	local px = setmetatable({}, { __index = b, __newindex = function(_, k, v) rawset(b, k, v) end })
	if type(b.str) == "string" then rawset(px, "str", tr(b.str))
	elseif type(b.str) == "table" then rawset(px, "str", trStrTable(b.str)) end
	if type(b.strset) == "table" then rawset(px, "strset", setLines(b.strset)) end
	if type(b.strpair) == "table" then rawset(px, "strpair", trStrTable(b.strpair)) end
	if type(b.choices) == "table" then rawset(px, "choices", trStrTable(b.choices)) end
	if type(b.pref) == "string" then rawset(px, "pref", tr(b.pref)) end
	if type(b.suf) == "string" then rawset(px, "suf", tr(b.suf)) end
	PROXY[b] = { lfSig = sg, px = px }
	return px
end

local NEW = {}   -- исходная панель ядра → копия-свиток
local function appearUntilDone(panel)
	local f = panel.Sprites and panel.Sprites.Face
	if f and f:IsPlaying("Appear") and not f:IsFinished("Appear") then return false end
	panel.Idle = true
	for _, v in pairs(panel.Sprites or {}) do v:Play("Idle", true) end
	panel.MaskAlpha = math.max(0, (panel.MaskAlpha or 1) - 0.25)
	return panel.MaskAlpha <= 0
end
local function makeMain(orig)
	local p = {}
	for k, v in pairs(orig) do p[k] = v end
	p.Sprites = "lfscroll_main"
	p.TitleOffset = Vector(0, -90)
	if selfDraw() then p.TitleOffset, p.lfSelfTitle = Vector(0, -10000), true end   -- заголовок — свой (drawTitle)
	p.Bounds = { G.left - 4, G.top, G.right + 4, G.bottom }
	p.Height = G.bottom - G.top
	p.TopSpacing, p.BottomSpacing = 4, 4
	p.ScrollerSymX, p.ScrollerSymYTop, p.ScrollerSymYBottom = G.right + 6, G.top + 6, G.bottom - 4
	p.lfOrig = orig
	p.GetDrawButtons = function(panel, item, tbl)
		if gridOn(item) then return {} end
		local bs = orig.GetDrawButtons(panel, item, tbl)
		if cyrRT and type(bs) == "table" then              -- текстовая страница — переведённые строки (прокси)
			local out = {}
			for i, b in ipairs(bs) do out[i] = type(b) == "table" and proxyOf(b) or b end
			return out
		end
		return bs
	end
	p.HandleInputs = function(panel, input, item, itemswitched, tbl)
		local m = input and input.menu
		if m and gridOn(item) and not m.keybinding and not input.keybinding then
			if not itemswitched then
				local dir = (m.up and "u") or (m.down and "d") or (m.left and "l") or (m.right and "r")
				if dir then
					local nb = navigate(layout(item), item.bsel or 1, dir)
					if nb and nb ~= item.bsel then
						item.bsel = nb
						sfx:Play(SoundEffect.SOUND_PLOP, 0.35, 0, false, 1.6)
					end
				end
			end
			local s1, s2, s3, s4, s5, s6 = m.up, m.down, m.left, m.right, m.dleft, m.dright
			m.up, m.down, m.left, m.right, m.dleft, m.dright = false, false, false, false, false, false
			orig.HandleInputs(panel, input, item, itemswitched, tbl)
			m.up, m.down, m.left, m.right, m.dleft, m.dright = s1, s2, s3, s4, s5, s6
		else
			orig.HandleInputs(panel, input, item, itemswitched, tbl)
		end
	end
	p.RenderFront = function(panel, pos, tbl)
		if panel.Idle then
			pcall(drawGrid, panel, pos, tbl)
			pcall(drawEmptyNote, pos, tbl)
			if p.lfSelfTitle then safeDraw("title", drawTitle, pos, tbl) end   -- panel здесь — запись ActivePanels
		end
		if orig.RenderFront then orig.RenderFront(panel, pos, tbl) end
	end
	p.UpdateAppear = appearUntilDone
	return p
end
local function makeTip(orig)
	local p = {}
	for k, v in pairs(orig) do p[k] = v end
	p.Sprites = "lfscroll_tip"
	p.lfOrig = orig
	p.UpdateAppear = appearUntilDone
	if selfDraw() then                                 -- подсказка — своим шрифтом (drawTip), ядро её не рисует
		p.GetDrawButtons = function() return {} end
		p.RenderFront = function(panel, pos, tbl)
			if panel.Idle then safeDraw("tip", drawTip, pos, tbl) end
			if orig.RenderFront then orig.RenderFront(panel, pos, tbl) end
		end
	end
	return p
end
local function isDefaultData(pd)
	if pd.lfScroll then return true end
	local o = pd.Offset
	return o and ((o.X == -42 and o.Y == 10) or (o.X == 130 and o.Y == -2))
end
local function patchPanels(tbl)
	local dk = tbl and tbl.DirectoryKey
	if not (dk and dk.ActivePanels) then return end
	-- свой многопанельный формат мода (Энциклопедия: сетка предметов, прокрутка, поиск, сортировка) — как есть: его
	-- панели расставлены под исходную бумагу и наезжали на ролики свитка (18.10, обход)
	local fmt = dk.Item and dk.Item.format
	if type(fmt) == "table" and type(fmt.Panels) == "table" and #fmt.Panels > 2 then return end
	for _, active in ipairs(dk.ActivePanels) do
		local pd, pan = active.PanelData, active.Panel
		if pd and pan and not pan.lfOrig and isDefaultData(pd) and (pan.Sprites == "main" or pan.Sprites == "tooltip") then
			local isMain = pan.Sprites == "main"
			local np = NEW[pan] or (isMain and makeMain(pan) or makeTip(pan))
			NEW[pan] = np
			pd.Panel = np
			pd.Offset = isMain and MAIN_OFF or TIP_OFF
			pd.lfScroll = true
			active.Panel = np
			active.TargetOffset = pd.Offset
			active.Offset = pd.Offset
			active.Sprites = DeadSeaScrollsMenu.GetDefaultPanelSprites(np.Sprites)
			local anim = (active.Idle and "Idle") or "Appear"
			for _, v in pairs(active.Sprites) do v:Play(anim, true) end
			if anim == "Appear" then active.Idle = false active.Appearing = true active.MaskAlpha = 1 end
		end
	end
end

-- ------------------------------------------------------------------ общее окно модов
local HUB_EXTRA = {}
LF.ModHub = LF.ModHub or {}
function LF.ModHub.Add(e)
	if type(e) == "table" and e.name then HUB_EXTRA[#HUB_EXTRA + 1] = e end
end

local pending   -- действие после закрытия меню DSS (открыть MCM, дерево PST, своё окно мода)
local function closeAndThen(fn)
	pending = { fn = fn, frames = 0 }
	if DeadSeaScrollsMenu.CloseMenu then pcall(DeadSeaScrollsMenu.CloseMenu, true, true) end
end
local function openMcm(cat)
	local mcm = ModConfigMenu
	if not mcm then return end
	if cat and mcm.OpenToCategory then mcm.OpenToCategory(cat) else mcm.OpenConfigMenu() end
end

local function otherButtons()
	local list = {}
	local dssMods = {}
	for name in pairs(DeadSeaScrollsMenu.Menus or {}) do
		local m = modForDss(name)
		if m then dssMods[m.folder] = true end
	end
	local mcmCats = {}
	for _, c in ipairs((ModConfigMenu and ModConfigMenu.MenuData) or {}) do
		if c.Name and c.Name ~= "General" and c.Name ~= "Mod Config Menu" then mcmCats[#mcmCats + 1] = c.Name end
	end
	local usedCat = {}
	local function catFor(m)
		for _, c in ipairs(mcmCats) do
			if not usedCat[c] and modForMcm(c) == m then usedCat[c] = true return c end
		end
	end
	for _, m in ipairs(mods()) do
		if not dssMods[m.folder] then
			local cat = catFor(m)
			local name = cleanName(m.name)
			local b = { str = lowerAll(name), lfThumb = m.frame, lfGrey = true, lfHub = true }
			local low = lowerAll(m.name)
			-- без картинки на странице Workshop (у Mod Config Menu Pure её нет) — иконка рукописью по сути мода
			if m.frame == nil then b.lfThumb, b.lfIcon = nil, (low:find("mod config menu", 1, true) and "mcm" or "other") end
			if low:find("passive skill tree", 1, true) and PST and PST.openTreeMenu then
				b.func = function() closeAndThen(function() PST:openTreeMenu() end) end
				b.tooltip = { strset = L({ "открыть", "дерево навыков", "", "настройки —", "в mod config menu" },
					{ "open the", "skill tree", "", "settings in", "mod config", "menu" }) }
			elseif low:find("mod config menu", 1, true) then
				b.func = function() closeAndThen(function() openMcm(nil) end) end
				b.tooltip = { strset = L({ "открыть", "mod config menu" }, { "open", "mod config", "menu" }) }
			elseif cat then
				b.func = function() closeAndThen(function() openMcm(cat) end) end
				b.tooltip = { strset = L({ "настройки мода", "в mod config menu" }, { "mod settings", "in mod", "config menu" }) }
			else
				b.tooltip = { strset = { L("у мода", "this mod has"), L("нет своего", "no menu"), L("меню", "of its own") } }
			end
			list[#list + 1] = b
		end
	end
	-- разделы MCM без найденного мода
	for _, c in ipairs(mcmCats) do
		if not usedCat[c] and not modForMcm(c) then
			list[#list + 1] = { str = lowerAll(c), lfIcon = "mcm", lfGrey = true, lfHub = true,
				func = function() closeAndThen(function() openMcm(c) end) end,
				tooltip = { strset = L({ "настройки мода", "в mod config menu" }, { "mod settings", "in mod", "config menu" }) } }
		end
	end
	-- добавленные другими модами
	for _, e in ipairs(HUB_EXTRA) do
		if e.thumb then mods() end
		local m = e.thumb and byId[tostring(e.thumb)]
		list[#list + 1] = { str = lowerAll(e.name), lfThumb = m and m.frame, lfIcon = (not m) and (e.icon or "other") or nil,
			lfGrey = e.dss ~= true, lfHub = true, tooltip = e.tooltip,
			func = function() closeAndThen(function()
				if e.open then e.open() elseif e.mcm then openMcm(e.mcm) end
			end) end }
	end
	table.sort(list, function(a, b) return a.str < b.str end)
	return list
end

local function sortMods(buttons)
	-- кнопки меню модов — по алфавиту, на своих же местах (продолжить, настройки, изменения — как были)
	local slots, mods = {}, {}
	for i, b in ipairs(buttons) do
		-- «изменения» ядра — тоже openmenu (menu = "Menu", dest = "changelogs"): остаётся на своём месте
		if b.action == "openmenu" and b.menu and b.menu ~= "Menu" and not b.dest then slots[#slots + 1] = i mods[#mods + 1] = b end
	end
	table.sort(mods, function(x, y)
		local a, c = tr(btnText(x)), tr(btnText(y))
		if a ~= c then return a < c end
		return tostring(x.menu) < tostring(y.menu)
	end)
	for k, i in ipairs(slots) do buttons[i] = mods[k] end
end
local function setupHub(menu)
	local dir = menu.Directory
	local main = dir and dir.main
	if not (main and main.buttons) then return end
	if main.lfHubFor == main.buttons and main.lfHubSig == #main.buttons and dir.lfothermods then return end
	-- убрать прежнее своё
	for i = #main.buttons, 1, -1 do if main.buttons[i].lfHub then table.remove(main.buttons, i) end end
	sortMods(main.buttons)
	main.buttons[#main.buttons + 1] = { str = L("другие моды", "other mods"), dest = "lfothermods", lfIcon = "other", lfHub = true,
		tooltip = { strset = L({ "моды без меню", "свитков:", "настройки в mcm", "и окна модов" },
			{ "mods without", "a dss menu:", "mcm settings", "and windows" }) } }
	main.lfHubFor, main.lfHubSig = main.buttons, #main.buttons
	if not dir.lfothermods or dir.lfothermods.lfCount ~= #main.buttons then
		dir.lfothermods = { title = L("другие моды", "other mods"), buttons = otherButtons(), tooltip = { strset = { L("выбрать мод", "choose a mod") } },
			lfCount = #main.buttons }
	end
end

-- ------------------------------------------------------------------ подключение к меню
-- старое ядро DSS без панелей (Alt Horsemen — AHMenuCore.lua: рисует меню целиком само, свиток к нему не цепляется;
-- 18.10, обход всех меню): его страницы рисует и водит новое ядро (то, что у главного меню «Menu»: те же кнопки,
-- переходы и настройки), а открытие-закрытие остаются и его — оно же сохраняет свои настройки своим сохранением
local function adoptOldCore(menu, tbl)
	local d = DeadSeaScrollsMenu
	local master = d.Menus and d.Menus.Menu
	local newRun = master and master.lfRun
	if not (newRun and master.Open and master.Close) or master == menu then return false end
	local oldOpen, oldClose = menu.Open, menu.Close
	local newOpen = master.Open
	menu.lfNewRun = newRun
	menu.Open = function(t, fromNothing)
		if oldOpen then oldOpen(t, fromNothing) end
		newOpen(t, fromNothing)
	end
	menu.Close = function(t, fullClose, noAnimate)
		if oldClose then oldClose(t, fullClose, noAnimate) end    -- сохранение настроек мода — его ядром
		if not (fullClose and not noAnimate) then t.DirectoryKey.ActivePanels = {} end
	end
	-- уже открыто старым ядром (первый кадр) — продолжить новым
	local dk = tbl.DirectoryKey
	dk.PreviousItem, dk.ActivePanels = nil, nil
	tbl.Exiting = nil
	pcall(newOpen, tbl, true)
	Isaac.DebugString("[localfixes] свиток DSS: меню «" .. tostring(menu.Name) .. "» со старым ядром — рисует новое ядро")
	return true
end

local function wrapMenus()
	local d = DeadSeaScrollsMenu
	if not (d and d.Menus) then return end
	installSprites()
	for name, menu in pairs(d.Menus) do
		if type(menu) == "table" and type(menu.Run) == "function" and not menu.lfRun then
			local orig = menu.Run
			menu.lfRun = orig
			menu.Run = function(tbl, ...)
				if name == "Menu" then pcall(setupHub, tbl) end
				local r
				if menu.lfNewRun then
					r = menu.lfNewRun(tbl, ...)
				else
					r = orig(tbl, ...)
					local dk = tbl.DirectoryKey
					-- ядро с панелями всегда заводит ActivePanels; старое — нет (у него свои Init, MaskAlpha)
					if dk and dk.ActivePanels == nil and dk.Init ~= nil and not menu.lfOldTried then
						menu.lfOldTried = true
						local ok, res = pcall(adoptOldCore, menu, tbl)
						if not ok then Isaac.DebugString("[localfixes] свиток DSS: старое ядро — " .. tostring(res)) end
					end
				end
				local ok, err = pcall(patchPanels, tbl)
				if not ok and not menu.lfErr then
					menu.lfErr = true
					Isaac.DebugString("[localfixes] свиток DSS: " .. tostring(err))
				end
				return r
			end
		end
	end
end

local mod = LF.Mod
local preloaded = false
-- кириллица ядра — сразу после загрузки модов (в главном меню MC_POST_RENDER не идёт, а русские названия энциклопедии
-- ставятся на старте забега и смотрят, умеет ли ядро кириллицу)
if ModCallbacks.MC_POST_MODS_LOADED then
	mod:AddCallback(ModCallbacks.MC_POST_MODS_LOADED, function() pcall(installCyrRT) end)
end
local langStamp
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
	-- язык игры сменили — строки свитка заново (английская игра не держит русских подписей из кэша)
	local lang = isRu() and "ru" or "en"
	if lang ~= langStamp then
		if langStamp then
			for k in pairs(trCache) do trCache[k] = nil end
			for k in pairs(capCache) do capCache[k] = nil end
			for k in pairs(PROXY) do PROXY[k] = nil end
		end
		langStamp = lang
	end
	if DeadSeaScrollsMenu then
		wrapMenus()
		if installCyrRT() then refontAll() end
	end
	if not preloaded and DeadSeaScrollsMenu and DeadSeaScrollsMenu.GetDefaultPanelSprites and game:GetFrameCount() > 30 then
		preloaded = true   -- листы свитка, иконок и шрифта — заранее (при открытии меню не грузить: был рывок)
		pcall(function()
			DeadSeaScrollsMenu.GetDefaultPanelSprites("lfscroll_main")
			DeadSeaScrollsMenu.GetDefaultPanelSprites("lfscroll_tip")
			sprites()
			getFont()
		end)
	end
	if pending then
		pending.frames = pending.frames + 1
		if pending.frames >= 2 and not (DeadSeaScrollsMenu and DeadSeaScrollsMenu.IsOpen and DeadSeaScrollsMenu.IsOpen()) then
			local fn = pending.fn
			pending = nil
			pcall(fn)
		elseif pending.frames > 60 then
			pending = nil
		end
	end
end)

local function pageCount(item) return gridOn(item) and #layout(item).pages or 0 end
local function goPage(item, k)
	if not gridOn(item) then return false end
	for _, e in ipairs(layout(item).cells) do
		if e.page == k then item.bsel = e.idx return true end
	end
	return false
end
LF.DSSScroll = { layout = layout, gridOn = gridOn, navigate = navigate, iconFor = iconFor, otherButtons = otherButtons,
	mods = mods, modForDss = modForDss, modForMcm = modForMcm,
	resetMods = function() MODS, byDss, byMcm, byId, byCaption = nil, {}, {}, {}, {} end,
	pageCount = pageCount, goPage = goPage, drawGrid = drawGrid, tr = tr, textWidth = textWidth, cellIcon = cellIcon,
	valueText = valueText, capText = capText }
return LF.DSSScroll
