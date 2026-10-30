local ABS = ActionBarSaver
local panel, launcher
local selected, page = nil, 1
local rows = {}
local sectionTex = 'Interface\\AddOns\\ActionBarSaver\\Textures\\ABS_Section'
local bgTex = 'Interface\\AddOns\\ActionBarSaver\\Textures\\ABS_BG'
local headerTex = 'Interface\\AddOns\\ActionBarSaver\\Textures\\ABS_Header'
local logoTex = 'Interface\\AddOns\\ActionBarSaver\\Textures\\ABS_Logo'
local minimapTex = 'Interface\\AddOns\\ActionBarSaver\\Textures\\ABS_Minimap'
local dividerTex = 'Interface\\AddOns\\ActionBarSaver\\Textures\\ABS_Divider'

local function run(command)
    if SlashCmdList and SlashCmdList.ABS then SlashCmdList.ABS(command) end
end

local function trimmed(text)
    return tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function clean(box)
    return trimmed(box and box:GetText() or '')
end

local function safePrint(msg)
    if ABS and ABS.Print then ABS:Print(msg) end
end

local function profiles()
    local list = {}
    local db = ABS and ABS.db
    local class = select(2, UnitClass('player')) or 'UNKNOWN'
    local sets = db and db.sets and db.sets[class] or {}
    for name in pairs(sets) do list[#list + 1] = name end
    table.sort(list)
    return list, sets
end

local function makeFont(parent, layer, template, size, r, g, b, anchor, rel, relPoint, x, y, text)
    local fs = parent:CreateFontString(nil, layer or 'OVERLAY', template or 'GameFontNormal')
    if size and fs.SetFont then
        local fontName = GameFontNormal:GetFont()
        fs:SetFont(fontName, size, 'OUTLINE')
    end
    fs:SetPoint(anchor or 'TOPLEFT', rel or parent, relPoint or anchor or 'TOPLEFT', x or 0, y or 0)
    if r then fs:SetTextColor(r, g, b) end
    if text then fs:SetText(text) end
    return fs
end

local function makeButton(parent, title, width, height, onClick)
    local b = CreateFrame('Button', nil, parent)
    b:SetWidth(width); b:SetHeight(height)
    b:SetNormalFontObject(GameFontNormal)
    b:SetHighlightFontObject(GameFontHighlight)
    b:SetText(title or '')
    b:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8x8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    b:SetBackdropColor(0.10, 0.14, 0.22, 0.92)
    b:SetBackdropBorderColor(0.72, 0.58, 0.28, 0.92)
    b:SetScript('OnEnter', function(self)
        self:SetBackdropColor(0.13, 0.19, 0.29, 0.96)
        self:SetBackdropBorderColor(0.42, 0.68, 1.0, 0.96)
    end)
    b:SetScript('OnLeave', function(self)
        self:SetBackdropColor(0.10, 0.14, 0.22, 0.92)
        self:SetBackdropBorderColor(0.72, 0.58, 0.28, 0.92)
    end)
    b:SetScript('OnMouseDown', function(self) self:SetBackdropColor(0.08, 0.12, 0.18, 0.98) end)
    b:SetScript('OnMouseUp', function(self)
        if self.IsMouseOver and self:IsMouseOver() then
            self:SetBackdropColor(0.13, 0.19, 0.29, 0.96)
        else
            self:SetBackdropColor(0.10, 0.14, 0.22, 0.92)
        end
    end)
    if onClick then b:SetScript('OnClick', onClick) end
    return b
end

local function makeEditBox(parent, width, height)
    local f = CreateFrame('Frame', nil, parent)
    f:SetWidth(width); f:SetHeight(height)
    f:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8x8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0.05, 0.08, 0.14, 0.95)
    f:SetBackdropBorderColor(0.55, 0.62, 0.76, 0.7)

    local e = CreateFrame('EditBox', nil, f)
    e:SetAutoFocus(false)
    e:SetMultiLine(false)
    e:SetFontObject(ChatFontNormal)
    if e.SetTextInsets then e:SetTextInsets(8, 8, 0, 0) end
    e:SetAllPoints(f)
    e:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    e:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)
    return f, e
end

local function makeSection(parent, x, y, w, h, title, subtitle)
    local sec = CreateFrame('Frame', nil, parent)
    sec:SetWidth(w); sec:SetHeight(h)
    sec:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)
    sec:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8x8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    sec:SetBackdropColor(0.05, 0.07, 0.11, 0.78)
    sec:SetBackdropBorderColor(0.22, 0.32, 0.48, 0.85)

    local art = sec:CreateTexture(nil, 'BACKGROUND')
    art:SetTexture(bgTex)
    art:SetAllPoints(sec)
    art:SetVertexColor(1, 1, 1, 0.18)

    local head = sec:CreateTexture(nil, 'BORDER')
    head:SetTexture(sectionTex)
    head:SetWidth(w - 18); head:SetHeight(42)
    head:SetPoint('TOP', sec, 'TOP', 0, -10)

    makeFont(sec, 'OVERLAY', 'GameFontHighlightLarge', 14, 0.98, 0.85, 0.52, 'TOPLEFT', sec, 'TOPLEFT', 16, -19, title)
    if subtitle then
        makeFont(sec, 'OVERLAY', 'GameFontDisableSmall', 10, 0.72, 0.80, 0.90, 'TOPLEFT', sec, 'TOPLEFT', 16, -36, subtitle)
    end

    local div = sec:CreateTexture(nil, 'ARTWORK')
    div:SetTexture(dividerTex)
    div:SetWidth(math.min(w - 20, 220)); div:SetHeight(10)
    div:SetPoint('TOPLEFT', sec, 'TOPLEFT', 12, -48)
    return sec
end

local function refresh()
    if not panel then return end
    local names = profiles()
    local maxpage = math.max(1, math.ceil(#names / 8))
    page = math.max(1, math.min(page, maxpage))

    for i, b in ipairs(rows) do
        local name = names[(page - 1) * 8 + i]
        if name then
            b.profile = name
            b:Show()
            b:SetText((name == selected and '» ' or '') .. name)
            if name == selected then
                b:SetBackdropBorderColor(0.36, 0.74, 1.0, 0.96)
            else
                b:SetBackdropBorderColor(0.72, 0.58, 0.28, 0.92)
            end
        else
            b.profile = nil
            b:Hide()
        end
    end

    panel.pageText:SetText(page .. ' / ' .. maxpage)
    panel.countText:SetText(#names .. ' local profiles')
    panel.selectedText:SetText(selected and ('Selected: ' .. selected) or 'Selected: none')

    local db = ABS.db or {}
    panel.macroToggle:SetText('Macros: ' .. (db.macro and 'ON' or 'OFF'))
    panel.rankToggle:SetText('Best Rank: ' .. (db.restoreRank and 'ON' or 'OFF'))
    panel.countToggle:SetText('Item Check: ' .. (db.checkCount and 'ON' or 'OFF'))
end

local function doSelected(prefix)
    if not selected or selected == '' then safePrint('Select a profile first.') return end
    run(prefix .. ' ' .. selected)
end

local function makePanel()
    if panel then return end

    panel = CreateFrame('Frame', 'ABSCoADarkveilPanel', UIParent)
    panel:SetWidth(940); panel:SetHeight(620)
    panel:SetPoint('CENTER', UIParent, 'CENTER', 0, 20)
    panel:SetFrameStrata('DIALOG')
    panel:SetFrameLevel(20)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag('LeftButton')
    panel:SetScript('OnDragStart', function(self) self:StartMoving() end)
    panel:SetScript('OnDragStop', function(self) self:StopMovingOrSizing() end)
    panel:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8x8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 8, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    panel:SetBackdropColor(0.02, 0.03, 0.06, 0.98)
    panel:SetBackdropBorderColor(0.85, 0.70, 0.35, 0.95)
    table.insert(UISpecialFrames, 'ABSCoADarkveilPanel')

    local bg = panel:CreateTexture(nil, 'BACKGROUND')
    bg:SetTexture(bgTex)
    bg:SetAllPoints(panel)
    bg:SetVertexColor(1, 1, 1, 0.95)

    local header = panel:CreateTexture(nil, 'ARTWORK')
    header:SetTexture(headerTex)
    header:SetWidth(900); header:SetHeight(100)
    header:SetPoint('TOP', panel, 'TOP', 0, -12)

    local logo = panel:CreateTexture(nil, 'ARTWORK')
    logo:SetTexture(logoTex)
    logo:SetWidth(74); logo:SetHeight(74)
    logo:SetPoint('TOPLEFT', panel, 'TOPLEFT', 20, -20)

    makeFont(panel, 'OVERLAY', 'GameFontHighlightLarge', 18, 0.99, 0.86, 0.56, 'TOPLEFT', panel, 'TOPLEFT', 100, -28, 'ActionBarSaver')
    makeFont(panel, 'OVERLAY', 'GameFontNormal', 11, 0.74, 0.84, 0.96, 'TOPLEFT', panel, 'TOPLEFT', 102, -52, 'ArdenWoW CoA • custom backup and spellbook restore suite')
    makeFont(panel, 'OVERLAY', 'GameFontDisableSmall', 10, 0.56, 0.65, 0.78, 'TOPLEFT', panel, 'TOPLEFT', 102, -70, 'Reliable local recovery when the server fails to keep your bars')

    local close = makeButton(panel, 'X', 28, 24, function() panel:Hide() end)
    close:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -14, -14)

    local author = makeFont(panel, 'OVERLAY', 'GameFontHighlightSmall', 11, 0.86, 0.88, 0.94, 'BOTTOMRIGHT', panel, 'BOTTOMRIGHT', -18, 16, 'Created by Darkveil')
    author:SetJustifyH('RIGHT')
    makeFont(panel, 'OVERLAY', 'GameFontDisableSmall', 10, 0.54, 0.64, 0.76, 'BOTTOMLEFT', panel, 'BOTTOMLEFT', 18, 16, '/absui opens this panel  •  minimap button = quick access')

    -- Profile section
    local sec1 = makeSection(panel, 18, -112, 280, 450, 'Profiles', 'Save, select, and manage local backups')
    for i = 1, 8 do
        local b = makeButton(sec1, '', 244, 28, function(self)
            selected = self.profile
            if selected and panel.nameBox then panel.nameBox:SetText(selected) end
            refresh()
        end)
        b:SetPoint('TOPLEFT', sec1, 'TOPLEFT', 16, -62 - (i - 1) * 34)
        rows[i] = b
    end
    local prev = makeButton(sec1, '<', 34, 24, function() page = page - 1; refresh() end)
    prev:SetPoint('TOPLEFT', sec1, 'TOPLEFT', 16, -338)
    panel.pageText = makeFont(sec1, 'OVERLAY', 'GameFontHighlight', 11, 0.92, 0.92, 0.96, 'TOPLEFT', sec1, 'TOPLEFT', 58, -344, '1 / 1')
    local nextb = makeButton(sec1, '>', 34, 24, function() page = page + 1; refresh() end)
    nextb:SetPoint('TOPLEFT', sec1, 'TOPLEFT', 226, -338)
    panel.countText = makeFont(sec1, 'OVERLAY', 'GameFontDisableSmall', 10, 0.72, 0.79, 0.88, 'TOPLEFT', sec1, 'TOPLEFT', 108, -345, '0 local profiles')
    panel.selectedText = makeFont(sec1, 'OVERLAY', 'GameFontHighlightSmall', 11, 0.93, 0.84, 0.55, 'TOPLEFT', sec1, 'TOPLEFT', 16, -374, 'Selected: none')

    makeFont(sec1, 'OVERLAY', 'GameFontNormalSmall', 10, 0.82, 0.87, 0.95, 'TOPLEFT', sec1, 'TOPLEFT', 16, -398, 'Profile name')
    local nameFrame, nameBox = makeEditBox(sec1, 244, 26)
    nameFrame:SetPoint('TOPLEFT', sec1, 'TOPLEFT', 16, -416)
    panel.nameBox = nameBox

    -- Actions section
    local sec2 = makeSection(panel, 314, -112, 300, 450, 'Backup Actions', 'Primary tools for capture and restore')
    local saveNamed = makeButton(sec2, 'Save Named', 128, 30, function()
        local name = clean(panel.nameBox)
        if name == '' then safePrint('Enter a profile name first.') return end
        run('save ' .. string.lower(name))
        selected = string.lower(name)
        refresh()
    end)
    saveNamed:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 16, -68)

    local forceSave = makeButton(sec2, 'Save Force', 128, 30, function()
        local name = clean(panel.nameBox)
        if name == '' then safePrint('Enter a profile name first.') return end
        run('saveforce ' .. string.lower(name))
        selected = string.lower(name)
        refresh()
    end)
    forceSave:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 154, -68)

    local snap = makeButton(sec2, 'New Snapshot', 266, 32, function() run('snapshot'); refresh() end)
    snap:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 16, -108)

    local restore = makeButton(sec2, 'Restore Selected', 266, 34, function()
        if InCombatLockdown and InCombatLockdown() then safePrint('Leave combat before restoring.') return end
        doSelected('restore')
    end)
    restore:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 16, -150)

    local audit = makeButton(sec2, 'Audit Selected', 128, 28, function() doSelected('audit') end)
    audit:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 16, -192)
    local errors = makeButton(sec2, 'Show Errors', 128, 28, function() run('errors') end)
    errors:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 154, -192)

    local listb = makeButton(sec2, 'List Profiles', 128, 28, function() run('list') end)
    listb:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 16, -228)
    local deleteb = makeButton(sec2, 'Delete Selected', 128, 28, function()
        if not selected or selected == '' then safePrint('Select a profile first.') return end
        StaticPopupDialogs['ABS_DARKVEIL_DELETE'] = {
            text = 'Delete local profile "%s"? This cannot be undone.',
            button1 = YES,
            button2 = NO,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
            OnAccept = function(self, data)
                run('delete ' .. data)
                if selected == data then selected = nil end
                refresh()
            end,
        }
        StaticPopup_Show('ABS_DARKVEIL_DELETE', selected, nil, selected)
    end)
    deleteb:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 154, -228)

    makeFont(sec2, 'OVERLAY', 'GameFontNormalSmall', 10, 0.82, 0.87, 0.95, 'TOPLEFT', sec2, 'TOPLEFT', 16, -274, 'Lookup spell (name or ID)')
    local lookupFrame, lookupBox = makeEditBox(sec2, 266, 26)
    lookupFrame:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 16, -292)
    panel.lookupBox = lookupBox
    local lookup = makeButton(sec2, 'Lookup Spell', 266, 28, function()
        local q = clean(panel.lookupBox)
        if q == '' then safePrint('Enter a spell name or ID.') return end
        run('lookup ' .. q)
    end)
    lookup:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 16, -324)

    makeFont(sec2, 'OVERLAY', 'GameFontNormalSmall', 10, 0.82, 0.87, 0.95, 'TOPLEFT', sec2, 'TOPLEFT', 16, -362, 'Inspect action slot')
    local slotFrame, slotBox = makeEditBox(sec2, 80, 26)
    slotFrame:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 16, -380)
    panel.slotBox = slotBox
    local inspect = makeButton(sec2, 'Inspect', 90, 28, function()
        local slot = clean(panel.slotBox)
        if not tonumber(slot) then safePrint('Enter a valid action slot number.') return end
        run('inspect ' .. slot)
    end)
    inspect:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 104, -380)
    local scan = makeButton(sec2, 'Scan Spellbook', 88, 28, function() run('scan') end)
    scan:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 194, -380)

    -- Options + Command guide
    local sec3 = makeSection(panel, 630, -112, 292, 450, 'Options & Quick Guide', 'Buttons for the most-used toggles and commands')
    panel.macroToggle = makeButton(sec3, '', 82, 28, function() run('macro'); refresh() end)
    panel.macroToggle:SetPoint('TOPLEFT', sec3, 'TOPLEFT', 16, -68)
    panel.rankToggle = makeButton(sec3, '', 82, 28, function() run('rank'); refresh() end)
    panel.rankToggle:SetPoint('TOPLEFT', sec3, 'TOPLEFT', 106, -68)
    panel.countToggle = makeButton(sec3, '', 82, 28, function() run('count'); refresh() end)
    panel.countToggle:SetPoint('TOPLEFT', sec3, 'TOPLEFT', 196, -68)

    local help = CreateFrame('Frame', nil, sec3)
    help:SetWidth(260); help:SetHeight(310)
    help:SetPoint('TOPLEFT', sec3, 'TOPLEFT', 16, -108)
    help:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8x8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    help:SetBackdropColor(0.03, 0.05, 0.09, 0.75)
    help:SetBackdropBorderColor(0.36, 0.45, 0.60, 0.75)

    makeFont(help, 'OVERLAY', 'GameFontHighlight', 12, 0.95, 0.83, 0.52, 'TOPLEFT', help, 'TOPLEFT', 12, -14, 'Command Guide')
    local guide = {
        '/abs save <name>  – save current bars',
        '/abs saveforce <name>  – force overwrite a profile',
        '/abs snapshot  – create a numbered backup',
        '/abs restore <name>  – restore a selected backup',
        '/abs scan  – rebuild your local spellbook registry',
        '/abs lookup <spell>  – inspect a learned spell record',
        '/abs inspect <slot>  – diagnose a live bar slot',
        '/abs audit <name>  – count what a profile contains',
        '/abs errors  – show restore failures in chat',
        '/abs macro, /abs rank, /abs count  – toggle options',
        '/abs list  – list every profile in chat',
        '/absui  – open this panel',
    }
    local y = -38
    for _, line in ipairs(guide) do
        local fs = makeFont(help, 'OVERLAY', 'GameFontDisableSmall', 10, 0.78, 0.84, 0.94, 'TOPLEFT', help, 'TOPLEFT', 12, y, line)
        fs:SetWidth(234)
        fs:SetJustifyH('LEFT')
        y = y - 22
    end

    local tips = CreateFrame('Frame', nil, sec3)
    tips:SetWidth(260); tips:SetHeight(72)
    tips:SetPoint('BOTTOMLEFT', sec3, 'BOTTOMLEFT', 16, 18)
    tips:SetBackdrop({
        bgFile = 'Interface\\Buttons\\WHITE8x8',
        edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
        tile = true, tileSize = 8, edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    tips:SetBackdropColor(0.08, 0.10, 0.16, 0.82)
    tips:SetBackdropBorderColor(0.72, 0.58, 0.28, 0.72)
    makeFont(tips, 'OVERLAY', 'GameFontHighlightSmall', 11, 0.95, 0.83, 0.52, 'TOPLEFT', tips, 'TOPLEFT', 10, -12, 'Best Practice')
    local t = makeFont(tips, 'OVERLAY', 'GameFontDisableSmall', 10, 0.78, 0.84, 0.94, 'TOPLEFT', tips, 'TOPLEFT', 10, -30,
        '1) Manually set bars once\n2) Click Scan Spellbook\n3) Save Named or New Snapshot\n4) Restore only outside combat')
    t:SetWidth(235)
    t:SetJustifyH('LEFT')

    panel:SetScript('OnShow', refresh)
    panel:Hide()
end

local function makeLauncher()
    if launcher then return end
    launcher = CreateFrame('Button', 'ABSCoAMinimapButton', Minimap)
    launcher:SetWidth(32); launcher:SetHeight(32)
    launcher:SetFrameStrata('MEDIUM'); launcher:SetFrameLevel(8)
    launcher:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')

    local border = launcher:CreateTexture(nil, 'OVERLAY')
    border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    border:SetAllPoints(launcher)

    local icon = launcher:CreateTexture(nil, 'ARTWORK')
    icon:SetTexture(minimapTex)
    icon:SetWidth(20); icon:SetHeight(20)
    icon:SetPoint('CENTER', launcher, 'CENTER', 0, 1)

    local function reposition()
        local db = ABS.db or {}
        local angle = tonumber(db.minimapAngle) or 225
        launcher:ClearAllPoints()
        launcher:SetPoint('CENTER', Minimap, 'CENTER', math.cos(math.rad(angle)) * 78, math.sin(math.rad(angle)) * 78)
        if db.minimapHidden then launcher:Hide() else launcher:Show() end
    end

    launcher:RegisterForDrag('LeftButton')
    launcher:SetScript('OnDragStart', function(self) self.dragging = true end)
    launcher:SetScript('OnDragStop', function(self) self.dragging = false end)
    launcher:SetScript('OnUpdate', function(self)
        if not self.dragging then return end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        x = x / scale; y = y / scale
        local mx, my = Minimap:GetCenter()
        local a = math.deg(math.atan2(y - my, x - mx))
        ABS.db.minimapAngle = a
        reposition()
    end)
    launcher:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    launcher:SetScript('OnClick', function(self, button)
        if self.dragging then return end
        if button == 'RightButton' then
            run('scan')
        else
            ABS:ToggleUI()
        end
    end)
    launcher:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
        GameTooltip:AddLine('ActionBarSaver', 1, 0.84, 0.45)
        GameTooltip:AddLine('Created by Darkveil', 0.75, 0.83, 0.95)
        GameTooltip:AddLine('Left-click: open control panel', 1, 1, 1)
        GameTooltip:AddLine('Right-click: scan spellbook', 1, 1, 1)
        GameTooltip:AddLine('Drag: move minimap button', 0.75, 0.83, 0.95)
        GameTooltip:Show()
    end)
    launcher:SetScript('OnLeave', function() GameTooltip:Hide() end)
    reposition()
end

function ABS:ToggleUI()
    makePanel()
    if panel:IsShown() then panel:Hide() else panel:Show() end
end

-- Register commands as soon as this Lua file is executed. Never require the
-- entire dashboard to build before /absui becomes available.
local initialized, optionsDone = false, false
local optionsPanel
local function report(err)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffff6666ABS Darkveil UI:|r '..tostring(err)) end
end
local function openPanel()
    local ok, err = pcall(function() ABS:ToggleUI() end)
    if not ok then report(err) end
end
SLASH_ABSUI1 = '/absui'
SlashCmdList['ABSUI'] = openPanel
SLASH_ABSMINIMAP1 = '/absminimap'
SlashCmdList['ABSMINIMAP'] = function(msg)
    if not ABS or not ABS.db then report('database is not initialized') return end
    local arg = string.lower(trimmed(msg))
    if arg == 'show' then ABS.db.minimapHidden = false
    elseif arg == 'hide' then ABS.db.minimapHidden = true
    else ABS.db.minimapHidden = not ABS.db.minimapHidden end
    if not launcher then
        local ok, err = pcall(makeLauncher)
        if not ok then report(err) end
    end
    if launcher then
        if ABS.db.minimapHidden then launcher:Hide() else launcher:Show() end
    end
end

local function registerOptions()
    if optionsDone or type(InterfaceOptions_AddCategory) ~= 'function' then return end
    optionsPanel = CreateFrame('Frame', 'ABSDarkveilInterfaceOptions', UIParent)
    optionsPanel.name = 'ActionBarSaver'
    local title = optionsPanel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
    title:SetPoint('TOPLEFT', optionsPanel, 'TOPLEFT', 18, -18)
    title:SetText('ActionBarSaver - Darkveil Edition')
    local description = optionsPanel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
    description:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -16)
    description:SetWidth(490)
    description:SetJustifyH('LEFT')
    description:SetText('Local snapshots and CoA custom spellbook registry. Created by Darkveil.')
    local open = CreateFrame('Button', nil, optionsPanel, 'UIPanelButtonTemplate')
    open:SetWidth(250);open:SetHeight(32)
    open:SetPoint('TOPLEFT', optionsPanel, 'TOPLEFT', 18, -100)
    open:SetText('Open ActionBarSaver Dashboard')
    open:SetScript('OnClick', function()
        if InterfaceOptionsFrame then InterfaceOptionsFrame:Hide() end
        openPanel()
    end)
    local mini = CreateFrame('Button', nil, optionsPanel, 'UIPanelButtonTemplate')
    mini:SetWidth(250); mini:SetHeight(32)
    mini:SetPoint('TOPLEFT', optionsPanel, 'TOPLEFT', 18, -142)
    mini:SetText('Toggle Minimap Button')
    mini:SetScript('OnClick', function() SlashCmdList['ABSMINIMAP']('') end)
    InterfaceOptions_AddCategory(optionsPanel)
    optionsDone = true
end

-- Defer setup until the core addon has populated ABS.db. Core registers its
-- own ADDON_LOADED listener and listener execution order must not be assumed.
local startup = CreateFrame('Frame')
startup:RegisterEvent('PLAYER_LOGIN')
startup:RegisterEvent('PLAYER_ENTERING_WORLD')
startup:RegisterEvent('ADDON_LOADED')
startup:SetScript('OnEvent', function(self, event, addon)
    if event == 'ADDON_LOADED' and addon ~= 'ActionBarSaver' and addon ~= 'Blizzard_InterfaceOptions' then return end
    if not ABS or not ABS.db then return end
    if not initialized then
        local ok, err = pcall(makeLauncher)
        if not ok then report('minimap: '..tostring(err)) else initialized = true end
    end
    if not optionsDone then
        local ok, err = pcall(registerOptions)
        if not ok then report('settings: '..tostring(err)) end
    end
end)
-- For late loads, the core may already have initialized.
if ABS and ABS.db then
    local ok, err = pcall(makeLauncher)
    if not ok then report('minimap: '..tostring(err)) else initialized = true end
    local ok2, err2 = pcall(registerOptions)
    if not ok2 then report('settings: '..tostring(err2)) end
end
