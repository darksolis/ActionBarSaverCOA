--[[ 
	Action Bar Saver, Shadowed
]]
ActionBarSaver = select(2, ...)

local ABS = ActionBarSaver
local L = ABS.L

local restoreErrors, spellCache, spellIDCache, macroCache, macroNameCache, highestRanks = {}, {}, {}, {}, {}, {}
local playerClass
if not string.trim then
	function string.trim(str) return (tostring(str or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
end
if not CopyTable then
	function CopyTable(t)
		if type(t) ~= "table" then return t end
		local out = {}
		for k, v in pairs(t) do out[k] = CopyTable(v) end
		return out
	end
end

local MAX_MACROS = 54
local MAX_CHAR_MACROS = 18
local MAX_GLOBAL_MACROS = 36
local MAX_ACTION_BUTTONS = 144
local POSSESSION_START = 121
local POSSESSION_END = 132

-- 3.3.5 does not expose the modern macro-limit globals.
MAX_CHAR_MACROS = tonumber(MAX_CHARACTER_MACROS) or MAX_CHAR_MACROS
MAX_GLOBAL_MACROS = tonumber(MAX_ACCOUNT_MACROS) or MAX_GLOBAL_MACROS
MAX_MACROS = MAX_CHAR_MACROS + MAX_GLOBAL_MACROS

function ABS:OnInitialize()
	local defaults = {
		macro = false,
		checkCount = false,
		restoreRank = false,
		spellSubs = {},
		sets = {}
	}
	
	ActionBarSaverDB = ActionBarSaverDB or {}
		
	-- Load defaults in
	for key, value in pairs(defaults) do
		if( ActionBarSaverDB[key] == nil ) then
			ActionBarSaverDB[key] = value
		end
	end
	
	for classToken in pairs(RAID_CLASS_COLORS or {}) do
		ActionBarSaverDB.sets[classToken] = ActionBarSaverDB.sets[classToken] or {}
	end
	
	self.db = ActionBarSaverDB
	
	playerClass = select(2, UnitClass("player")) or "UNKNOWN"
	ActionBarSaverDB.sets[playerClass] = ActionBarSaverDB.sets[playerClass] or {}
end

-- Text "compression" so it can be stored in our format fine
function ABS:CompressText(text)
	text = string.gsub(text, "\n", "/n")
	text = string.gsub(text, "/n$", "")
	text = string.gsub(text, "||", "/124")
	
	return string.trim(text)
end

function ABS:UncompressText(text)
	text = string.gsub(text, "/n", "\n")
	text = string.gsub(text, "/124", "|")
	
	return string.trim(text)
end

-- Local capture is authoritative; CoA's GetActionInfo spell number can be a
-- spellbook slot, not a global spell ID. Do not call GetSpellInfo on it blindly.
local absTip = CreateFrame("GameTooltip", "ABSArdenInspectTooltip", UIParent, "GameTooltipTemplate")
absTip:SetOwner(UIParent, "ANCHOR_NONE")
local function actionTooltip(slot)
    absTip:ClearLines()
    if not absTip.SetAction then return nil, nil end
    local ok = pcall(absTip.SetAction, absTip, slot)
    if not ok then return nil, nil end
    local first = _G["ABSArdenInspectTooltipTextLeft1"]
    local second = _G["ABSArdenInspectTooltipTextRight1"]
    local name = first and first:GetText()
    local rank = second and second:GetText()
    return name, rank
end
local function norm(v)
    return string.lower(string.trim(tostring(v or "")))
end
local function spellBookRecords()
    local records = {}
    local count = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab=1,count do
        local _,_,offset,numSpells = GetSpellTabInfo(tab)
        if offset and numSpells then
            for idx=offset+1,offset+numSpells do
                local name,rank = GetSpellBookItemName(idx, BOOKTYPE_SPELL)
                local kind,id = GetSpellBookItemInfo(idx, BOOKTYPE_SPELL)
                if name and (kind == "SPELL" or kind == "spell") then
                    records[#records+1] = {index=idx, name=name, rank=rank or "", id=tonumber(id)}
                end
            end
        end
    end
    return records
end
-- Persistent spellbook registry. A spell ID is NOT a spellbook slot.
-- Store both, and use the spellbook slot for PickupSpell on 3.3.5.
local function characterKey()
    local name=UnitName("player") or "unknown"
    local realm=GetRealmName and GetRealmName() or "unknown"
    return realm .. ":" .. name
end
function ABS:ScanSpellbook(silent)
    self.db.spellRegistry=self.db.spellRegistry or {}
    local key=characterKey()
    local records=spellBookRecords()
    local registry={version=6, character=key, class=playerClass, entries={}, byID={}, byName={}, scannedAt=time and time() or 0}
    for _,r in ipairs(records) do
        local rec={name=r.name, rank=r.rank or "", id=r.id, index=r.index}
        registry.entries[#registry.entries+1]=rec
        if rec.id then
            registry.byID[tostring(rec.id)]=registry.byID[tostring(rec.id)] or {}
            table.insert(registry.byID[tostring(rec.id)], #registry.entries)
        end
        local k=norm(rec.name)
        registry.byName[k]=registry.byName[k] or {}
        table.insert(registry.byName[k], #registry.entries)
    end
    -- Do not replace a populated registry with an empty scan on a broken login.
    if #registry.entries>0 then self.db.spellRegistry[key]=registry end
    self.activeSpellRegistry=registry
    if not silent then self:Print(string.format("Scanned %d learned spellbook entries for %s; database stored locally.",#registry.entries,key)) end
    return registry
end
function ABS:LookupSpell(query)
    local registry=self:ScanSpellbook(true)
    local matches={}
    local q=norm(query)
    for _,rec in ipairs(registry.entries) do
        if tostring(rec.id or "")==query or string.find(norm(rec.name),q,1,true) then
            matches[#matches+1]=rec
        end
    end
    self:Print(string.format("Spellbook matches for '%s': %d",query,#matches))
    for i=1,math.min(#matches,15) do
        local r=matches[i]
        self:Print(string.format("%s [%s] spellID=%s bookIndex=%s",r.name,r.rank or "",tostring(r.id),tostring(r.index)))
    end
end
-- CoA returns several incompatible spell references. Always check both
-- spellbook indices and real spell IDs against the scanned learned book.
-- When they disagree AND tooltip provides no identity, never make a guess.
local function matchBook(actionNumber, tooltipName, tooltipRank, records)
    local wanted = norm(tooltipName)
    local matches = {}
    local byIndex, byID = {}, {}
    for _,rec in ipairs(records) do
        if rec.index == actionNumber then byIndex[#byIndex+1] = rec end
        if rec.id and rec.id == actionNumber then byID[#byID+1] = rec end
        if wanted ~= "" and norm(rec.name) == wanted and
           (norm(tooltipRank)=="" or norm(rec.rank)==norm(tooltipRank)) then
            matches[#matches+1] = rec
        end
    end
    if wanted ~= "" then
        if #matches == 1 then return matches[1], "tooltip" end
        if #matches > 1 then
            for _,rec in ipairs(matches) do
                if rec.index==actionNumber or rec.id==actionNumber then return rec,"tooltip+number" end
            end
        end
        return nil,"tooltip unmatched or ambiguous"
    end
    if #byIndex == 1 and #byID == 0 then return byIndex[1],"book-index" end
    if #byID == 1 and #byIndex == 0 then return byID[1],"spell-id" end
    if #byIndex == 1 and #byID == 1 and byIndex[1].index==byID[1].index then
        return byIndex[1],"index+id"
    end
    return nil,"ambiguous or unrecognized number"
end

function ABS:InspectSlot(slot)
    slot=tonumber(slot)
    if not slot or slot<1 or slot>MAX_ACTION_BUTTONS then
        self:Print("Usage: /abs inspect <slot number 1-144>");return
    end
    local kind,raw,sub,extra=GetActionInfo(slot)
    local tip,rank=actionTooltip(slot)
    local registry=self:ScanSpellbook(true)
    local candidate,method=matchBook(tonumber(raw),tip,rank,registry.entries)
    self:Print(string.format("Slot %d: type=%s raw=%s subtype=%s extra=%s tooltip='%s' rank='%s'",slot,tostring(kind),tostring(raw),tostring(sub),tostring(extra),tostring(tip),tostring(rank)))
    for _,rec in ipairs(registry.entries) do
        if rec.index==tonumber(raw) or (rec.id and rec.id==tonumber(raw)) then
            self:Print(string.format("  Candidate: %s [%s] id=%s index=%s",tostring(rec.name),tostring(rec.rank),tostring(rec.id),tostring(rec.index)))
        end
    end
    self:Print(candidate and ("MATCH ("..method.."): "..candidate.name) or ("UNRESOLVED: "..tostring(method)))
end
local function countSaved(set)
    local n=0
    for k,v in pairs(set or {}) do if type(k)=="number" and type(v)=="string" then n=n+1 end end
    return n
end

-- Restore a saved profile
function ABS:SaveProfile(name, force)
    local old=self.db.sets[playerClass][name]
    local existing=countSaved(old)
    local current=0
    for i=1,MAX_ACTION_BUTTONS do
        local kind,id=GetActionInfo(i)
        if kind and id and (i<POSSESSION_START or i>POSSESSION_END) then current=current+1 end
    end
    if current==0 then
        self:Print("REFUSED to save empty action bars. Existing local backups preserved.")
        return false
    end
    if existing>0 and current<existing and not force then
        self:Print(string.format("REFUSED to overwrite '%s': current bars %d, backup %d. Server may have lost actions. Use /abs saveforce %s ONLY if intentional.",name,current,existing,name))
        return false
    end
    self.db.sets[playerClass][name] = self.db.sets[playerClass][name] or {}
	local set = self.db.sets[playerClass][name]
    local registry=self:ScanSpellbook(true)
    local records=registry.entries
    local unresolved = 0
	for actionID=1, MAX_ACTION_BUTTONS do
		set[actionID] = nil
		
		local type, id, subType, extraID = GetActionInfo(actionID)
		if( type and id and ( actionID < POSSESSION_START or actionID > POSSESSION_END ) ) then
			-- DB Format: <type>|<id>|<binding>|<name>|<extra ...>
			-- Save a companion
			if( type == "companion" ) then
				set[actionID] = string.format("%s|%s|%s|%s|%s|%s", type, id, "", "", subType, "")
			-- Save an equipment set
			elseif( type == "equipmentset" ) then
				set[actionID] = string.format("%s|%s|%s", type, id, "")
			-- Save an item
			elseif( type == "item" ) then
				set[actionID] = string.format("%s|%d|%s|%s", type, id, "", (GetItemInfo(id)) or "")
			-- Save a spell
			                elseif( type == "spell" and tonumber(id) and tonumber(id)>0 ) then
                    local title,tipRank=actionTooltip(actionID)
                    title=title and string.gsub(title,"|", " ")
                    tipRank=tipRank and string.gsub(tipRank,"|", " ")
                    local rec=matchBook(tonumber(id), title, tipRank, records)
                    if rec then
                        -- CoA v4: action slot's verified tooltip + actual book ID and index.
                        set[actionID]=string.format("spell|%s||%s|%s|%s|coa6|%s|%s", tostring(id), rec.name, rec.rank or "", tostring(extraID or ""), tostring(rec.id or ""), tostring(rec.index))
                    elseif title and title~="" then
                        unresolved=unresolved+1
                        -- Preserve unidentified custom action for inspection, never guess.
                        set[actionID]=string.format("spell|%s||%s|%s|%s|coa6|?|?", tostring(id), title, tipRank or "", tostring(extraID or ""))
                    else
                        unresolved=unresolved+1
                        set[actionID]=string.format("spell|%s||||coa6|?|?", tostring(id))
                    end
-- Save a macro
			elseif( type == "macro" ) then
				local name, icon, macro = GetMacroInfo(id)
				if( name and icon and macro ) then
					set[actionID] = string.format("%s|%d|%s|%s|%s|%s", type, actionID, "", self:CompressText(name), icon, self:CompressText(macro))
				end
			-- Flyout mnenu
		    elseif( type == "flyout" ) then
		        set[actionID] = string.format("%s|%d|%s|%s|%s", type, id, "", (GetFlyoutInfo(id)), "")
			end
		end
	end
	
	self:Print(string.format(L["Saved profile %s!"], name))
    if unresolved>0 then self:Print(string.format("WARNING: %d spell slots unresolved in backup. Use /abs inspect <slot> to diagnose; do NOT trust this as complete recovery.",unresolved)) end
    return true
end

-- Finds the macroID in case it's changed
function ABS:FindMacro(id, name, data)
	if( macroCache[id] == data ) then
		return id
	end
		
	-- No such luck, check text
	for id, currentMacro in pairs(macroCache) do
		if( currentMacro == data ) then
			return id
		end
	end
	
	-- Still no luck, let us try name
	if( macroNameCache[name] ) then
		return macroNameCache[name]
	end
	
	return nil
end

-- Restore any macros that don't exist
function ABS:RestoreMacros(set)
	local perCharacter = true
	for id, data in pairs(set) do
		local type, id, binding, macroName, macroIcon, macroData = string.split("|", data)
		if( type == "macro" ) then
			-- Do we already have a macro?
			local macroID = self:FindMacro(id, macroName, macroData)
			if( not macroID ) then
				local globalNum, charNum = GetNumMacros()
				-- Make sure we aren't at the limit
				if( globalNum >= MAX_GLOBAL_MACROS and charNum >= MAX_CHAR_MACROS ) then
					table.insert(restoreErrors, L["Unable to restore macros, you already have 36 global and 18 per character ones created."])
					break

				-- We ran out of space for per character, so use global
				elseif( charNum >= MAX_CHAR_MACROS ) then
					perCharacter = false
				end
				
				macroName = self:UncompressText(macroName)

				-- GetMacroInfo still returns the full path while CreateMacro needs the relative
				-- can also return INTERFACE\ICONS\ aswell, apparently.
				macroIcon = macroIcon and string.gsub(macroIcon, "[iI][nN][tT][eE][rR][fF][aA][cC][eE]\\[iI][cC][oO][nN][sS]\\", "")
				
				-- No macro name means a space has to be used or else it won't be created and saved
				CreateMacro(macroName == "" and " " or macroName, macroIcon or "INV_Misc_QuestionMark", self:UncompressText(macroData), perCharacter)
			end
		end
	end
	
	-- Recache macros due to any additions
	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		
		if( name ) then
			-- If there are macros with the same name, then blacklist and don't look by name
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end
		
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
end

-- Restore a saved profile
function ABS:RestoreProfile(name, overrideClass)
	local set = self.db.sets[overrideClass or playerClass][name]
	if( not set ) then
		self:Print(string.format(L["No profile with the name \"%s\" exists."], name))
		return
	elseif( InCombatLockdown() ) then
		self:Print(string.format(L["Unable to restore profile \"%s\", you are in combat."], name))
		return
	end
	
	table.wipe(macroCache)
	table.wipe(spellCache)
	table.wipe(macroNameCache)
	
	-- CoA-specific lookup: names are NOT unique (custom spells can share names),
	-- so index spellbook entries by numeric spell ID and by names only as fallback.
	-- Existing pre-patch profiles already contain spell IDs: no conversion required.
	table.wipe(spellIDCache)
	local tabCount = (GetNumSpellTabs and GetNumSpellTabs()) or MAX_SKILLLINE_TABS or 0
	for book = 1, tabCount do
		local _, _, offset, numSpells = GetSpellTabInfo(book)
		if offset and numSpells then
			for index = offset + 1, offset + numSpells do
				local spell, rank = GetSpellBookItemName(index, BOOKTYPE_SPELL)
				local bookType, spellID
				if GetSpellBookItemInfo then
					bookType, spellID = GetSpellBookItemInfo(index, BOOKTYPE_SPELL)
				end
				if spellID and tonumber(spellID) and (bookType == "SPELL" or bookType == "spell" or bookType == nil) then
					spellIDCache[tonumber(spellID)] = index
				end
				if spell and spell ~= "" then
					spellCache[spell] = index
					spellCache[string.lower(spell)] = index
					if rank and rank ~= "" then
						spellCache[spell .. rank] = index
						spellCache[string.lower(spell .. rank)] = index
					end
				end
			end
		end
	end
	-- Restore by spell ID first, because name/rank matching is unsafe on CoA.

	-- Cache macros
	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)
		
		if( name ) then
			-- If there are macros with the same name, then blacklist and don't look by name
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end
		
		macroCache[i] = macro and self:CompressText(macro) or nil
	end
	
	-- Check if we need to restore any missing macros
	if( self.db.macro ) then
		self:RestoreMacros(set)
	end
	
	-- One automatic safety snapshot per login, before the first destructive restore.
	if not self.db.sets[playerClass]["__arden_before_restore"] then
        local any=false
        for i=1,MAX_ACTION_BUTTONS do if GetActionInfo(i) then any=true;break end end
        if any then self:SaveProfile("__arden_before_restore") end
    end

	-- NON-DESTRUCTIVE restore. Never clear an occupied slot before a replacement
	-- is securely on the cursor. Slots missing from a profile remain untouched.
	ClearCursor()
	local applied, skipped = 0, 0
	for i=1, MAX_ACTION_BUTTONS do
		if( i < POSSESSION_START or i > POSSESSION_END ) and set[i] then
			local ok, result = pcall(function()
				return self:RestoreAction(i, string.split("|", set[i]))
			end)
			if ok and result then
				applied = applied + 1
			else
				skipped = skipped + 1
				if not ok then table.insert(restoreErrors, "Slot " .. i .. ": " .. tostring(result)) end
			end
			ClearCursor()
		end
	end
	self:Print(string.format("Safe restore: %d applied, %d skipped. Unlisted slots were preserved.", applied, skipped))

	-- Done!
	if( #(restoreErrors) == 0 ) then
		self:Print(string.format(L["Restored profile %s!"], name))
	else
		self:Print(string.format(L["Restored profile %s, failed to restore %d buttons type /abs errors for more information."], name, #(restoreErrors)))
	end
end

-- Verify the candidate against BOTH the name saved in the profile and the
-- spellbook. Some CoA GetActionInfo() values are book slots, not spell IDs.
local function normalName(value)
	return string.lower(string.trim(value or ""))
end

local function getBookName(index)
	if not index or not GetSpellBookItemName then return nil end
	local name = GetSpellBookItemName(index, BOOKTYPE_SPELL)
	return name
end

local function cursorPlace(i, wantedType)
	local cursorType = GetCursorInfo()
	if cursorType ~= wantedType then
		ClearCursor()
		return false
	end
	-- PlaceAction swaps any existing action onto the cursor: only clear AFTER
	-- the replacement is already committed to the slot.
	PlaceAction(i)
	ClearCursor()
	return true
end

function ABS:RestoreAction(i, actionType, actionID, binding, ...)
	local name, rank = ...
    if actionType == "spell" then
        local actionNum=tonumber(actionID)
        local savedName,savedRank,unused,version,savedSpellID,savedIndex = ...
        -- Modern records must be tied to the spellbook by tooltip identity.
        -- Older records have unreliable names; never blindly use their ID.
        local registry=self:ScanSpellbook(true)
        local records=registry.entries
        local options={}
        for _,rec in ipairs(records) do
            if norm(rec.name)==norm(savedName) and norm(savedName)~="" then
                if not savedRank or savedRank=="" or norm(rec.rank)==norm(savedRank) then
                    options[#options+1]=rec
                end
            end
        end
        local chosen
        if (version=="coa4" or version=="coa5" or version=="coa6") and savedSpellID and tonumber(savedSpellID) then
            for _,rec in ipairs(options) do
                if rec.id==tonumber(savedSpellID) then chosen=rec;break end
            end
        end
        if not chosen and (version=="coa4" or version=="coa5" or version=="coa6") and savedIndex and tonumber(savedIndex) then
            for _,rec in ipairs(options) do
                if rec.index==tonumber(savedIndex) then chosen=rec;break end
            end
        end
        if not chosen and #options==1 then chosen=options[1] end
        if chosen then
            -- 3.3.5: PickupSpell(index, BOOKTYPE_SPELL) uses a *spellbook slot*.
            -- PickupSpellBookItem only exists on later clients (4.0.1+).
            -- The registry's global spell ID must NEVER be passed as this index.
            if InCombatLockdown and InCombatLockdown() then
                table.insert(restoreErrors,"Skipped spell slot "..i..": in combat; existing action preserved.")
                return false
            end
            ClearCursor()
            local bookType = BOOKTYPE_SPELL or "spell"
            local pickup = PickupSpell or PickupSpellBookItem
            if not pickup then
                table.insert(restoreErrors,"Skipped spell slot "..i..": no supported spell pickup API; existing action preserved.")
                return false
            end
            local pickupOK, pickupError = pcall(pickup, chosen.index, bookType)
            if not pickupOK then
                ClearCursor()
                table.insert(restoreErrors,"Skipped spell slot "..i..": pickup failed: "..tostring(pickupError))
                return false
            end
            if cursorPlace(i,"spell") then
                local kind,actual=GetActionInfo(i)
                local actualName=actionTooltip(i)
                if kind=="spell" and norm(actualName)==norm(chosen.name) then return true end
                table.insert(restoreErrors,"Slot "..i.." placed but failed read-back verification: "..tostring(savedName))
                return false
            end
        end
        table.insert(restoreErrors,string.format("Skipped spell slot %d: '%s' (raw %s). No unambiguous learned spellbook match; current action preserved.",i,tostring(savedName),tostring(actionID)))
        return false
	elseif actionType == "macro" then
		local macroID = self:FindMacro(tonumber(actionID), name, select(2, ...) or -1)
		if macroID then PickupMacro(macroID) end
		if cursorPlace(i, "macro") then return true end
	elseif actionType == "item" then
		PickupItem(tonumber(actionID) or actionID)
		if cursorPlace(i, "item") then return true end
	elseif actionType == "equipmentset" then
		for n=1, (GetNumEquipmentSets and GetNumEquipmentSets() or 0) do
			if GetEquipmentSetInfo(n) == actionID then
				PickupEquipmentSet(n)
				if cursorPlace(i, "equipmentset") then return true end
			end
		end
	elseif actionType == "flyout" then
		if PickupSpell then PickupSpell(tonumber(actionID) or actionID) end
		if cursorPlace(i, "flyout") then return true end
	elseif actionType == "companion" then
		-- CoA pet/companion state is not reliably portable between characters.
	end
	table.insert(restoreErrors, string.format("Skipped %s slot %d (ID %s); existing action preserved.", tostring(actionType), i, tostring(actionID)))
	ClearCursor()
	return false
end

function ABS:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ABS|r: " .. msg)
end

SLASH_ACTIONBARSAVER1 = nil
SlashCmdList["ACTIONBARSAVER"] = nil

SLASH_ABS1 = "/abs"
SLASH_ABS2 = "/actionbarsaver"
SlashCmdList["ABS"] = function(msg)
	msg = msg or ""
	
	local cmd, arg = string.split(" ", msg, 2)
	cmd = string.lower(cmd or "")
	arg = string.lower(arg or "")
	
	local self = ABS
	
	-- Profile saving
	if( cmd == "save" and arg ~= "" ) then
		self:SaveProfile(arg)
	
	-- Spell sub
	elseif( cmd == "saveforce" and arg ~= "" ) then
        self:SaveProfile(arg,true)
    elseif( cmd == "snapshot" ) then
        self.db.snapshotSeq=(self.db.snapshotSeq or 0)+1
        self:SaveProfile("coa-snapshot-"..self.db.snapshotSeq,true)
    elseif( cmd == "scan" ) then
        self:ScanSpellbook(false)
    elseif( cmd == "lookup" and arg ~= "" ) then
        self:LookupSpell(arg)
    elseif( cmd == "inspect" and arg ~= "" ) then
        self:InspectSlot(arg)
    elseif( cmd == "audit" and arg ~= "" ) then
        local set=self.db.sets[playerClass][arg]
        if not set then self:Print("No profile: "..arg);return end
        local total,custom=0,0
        for i,v in pairs(set) do
            if type(i)=="number" then
                total=total+1
                if string.find(v,"|coa4|",1,true) or string.find(v,"|coa6|",1,true) then custom=custom+1 end
            end
        end
        self:Print(string.format("Profile '%s': %d saved actions, %d CoA-verified-format spells.",arg,total,custom))
    elseif( cmd == "link" and arg ~= "" ) then
		local first, second = string.match(arg, "\"(.+)\" \"(.+)\"")
		first = string.trim(first or "")
		second = string.trim(second or "")
		
		if( first == "" or second == "" ) then
			self:Print(L["Invalid spells passed, remember you must put quotes around both of them."])
			return
		end
		
		self.db.spellSubs[first] = second
		
		self:Print(string.format(L["Spells \"%s\" and \"%s\" are now linked."], first, second))
		
	-- Profile restoring
	elseif( cmd == "restore" and arg ~= "" ) then
		for i=#(restoreErrors), 1, -1 do table.remove(restoreErrors, i) end
				
		if( not self.db.sets[playerClass][arg] ) then
			self:Print(string.format(L["Cannot restore profile \"%s\", you can only restore profiles saved to your class."], arg))
			return
		end
		
		self:RestoreProfile(arg, playerClass)
		
	-- Profile renaming
	elseif( cmd == "rename" and arg ~= "" ) then
		local old, new = string.split(" ", arg, 2)
		new = string.trim(new or "")
		old = string.trim(old or "")
		
		if( new == old ) then
			self:Print(string.format(L["You cannot rename \"%s\" to \"%s\" they are the same profile names."], old, new))
			return
		elseif( new == "" ) then
			self:Print(string.format(L["No name specified to rename \"%s\" to."], old))
			return
		elseif( self.db.sets[playerClass][new] ) then
			self:Print(string.format(L["Cannot rename \"%s\" to \"%s\" a profile already exists for %s."], old, new, (UnitClass("player"))))
			return
		elseif( not self.db.sets[playerClass][old] ) then
			self:Print(string.format(L["No profile with the name \"%s\" exists."], old))
			return
		end
		
		self.db.sets[playerClass][new] = CopyTable(self.db.sets[playerClass][old])
		self.db.sets[playerClass][old] = nil
		
		self:Print(string.format(L["Renamed \"%s\" to \"%s\""], old, new))
		
	-- Restore errors
	elseif( cmd == "errors" ) then
		if( #(restoreErrors) == 0 ) then
			self:Print(L["No errors found!"])
			return
		end

		self:Print(string.format(L["Errors found: %d"], #(restoreErrors)))
		for _, text in pairs(restoreErrors) do
			DEFAULT_CHAT_FRAME:AddMessage(text)
		end

	-- Delete profile
	elseif( cmd == "delete" ) then
		self.db.sets[playerClass][arg] = nil
		self:Print(string.format(L["Deleted saved profile %s."], arg))
	
	-- List profiles
	elseif( cmd == "list" ) then
		local classes = {}
		local setList = {}
		
		for class, sets in pairs(self.db.sets) do
			table.insert(classes, class)
		end
		
		table.sort(classes, function(a, b)
			return a < b
		end)
		
		for _, class in pairs(classes) do
			for i=#(setList), 1, -1 do table.remove(setList, i) end
			for setName in pairs(self.db.sets[class]) do
				table.insert(setList, setName)
			end
			
			if( #(setList) > 0 ) then
				DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99%s|r: %s", L[class] or "???", table.concat(setList, ", ")))
			end
		end
		
	-- Macro restoring
	elseif( cmd == "macro" ) then
		self.db.macro = not self.db.macro

		if( self.db.macro ) then
			self:Print(L["Auto macro restoration is now enabled!"])
		else
			self:Print(L["Auto macro restoration is now disabled!"])
		end
	
	-- Item counts
	elseif( cmd == "count" ) then
		self.db.checkCount = not self.db.checkCount

		if( self.db.checkCount ) then
			self:Print(L["Checking item count is now enabled!"])
		else
			self:Print(L["Checking item count is now disabled!"])		
		end
	
	-- Rank restore
	elseif( cmd == "rank" ) then
		self.db.restoreRank = not self.db.restoreRank
		
		if( self.db.restoreRank ) then
			self:Print(L["Auto restoring highest spell rank is now enabled!"])
		else
			self:Print(L["Auto restoring highest spell rank is now disabled!"])
		end
		
	-- Halp
	else
		self:Print(L["Slash commands"])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs save <profile> - Saves your current action bar setup under the given profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs restore <profile> - Changes your action bars to the passed profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs delete <profile> - Deletes the saved profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rename <oldProfile> <newProfile> - Renames a saved profile from oldProfile to newProfile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs link \"<spell 1>\" \"<spell 2>\" - Links a spell with another, INCLUDE QUOTES for example you can use \"Shadowmeld\" \"War Stomp\" so if War Stomp can't be found, it'll use Shadowmeld and vica versa."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs count - Toggles checking if you have the item in your inventory before restoring it, use if you have disconnect issues when restoring."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs rank - Toggles if ABS should restore the highest rank of the spell, or the one saved originally."])
		DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
		DEFAULT_CHAT_FRAME:AddMessage("/abs snapshot - create a new numbered local snapshot; /abs saveforce <name> - overwrite even if bars are missing; /abs audit <name> - count stored actions.")
        DEFAULT_CHAT_FRAME:AddMessage("/abs scan - persist your learned spellbook by name, rank, spell ID and book index.")
        DEFAULT_CHAT_FRAME:AddMessage("/abs lookup <name or ID> - inspect captured spellbook records.")
        DEFAULT_CHAT_FRAME:AddMessage("/abs inspect <slot> - diagnose actual action references and spellbook candidates.")
        DEFAULT_CHAT_FRAME:AddMessage("Safe restore leaves unmatched and unlisted slots untouched. Older profiles may contain bad CoA spell names.")
	end
end

-- Check if we need to load
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
	if( addon == "ActionBarSaver" ) then
		ABS:OnInitialize()
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
