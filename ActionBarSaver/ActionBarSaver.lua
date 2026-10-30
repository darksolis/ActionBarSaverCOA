--[[ 
	Action Bar Saver, Shadowed
]]
ActionBarSaver = ActionBarSaver or select(2, ...) or {}

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

-- Real folder name (first vararg); used for ADDON_LOADED and texture paths.
ABS.addonName = ABS.addonName or (type((...)) == "string" and (...)) or "ActionBarSaver"

-- 3.3.5 compatibility: GetSpellBookItemName / GetSpellBookItemInfo are 4.0+.
-- On a 3.3.5 client they are nil and every scan/save/restore would crash.
-- These locals shadow the globals for the rest of this file.
local GetSpellBookItemName = _G.GetSpellBookItemName or function(index, bookType)
	if not GetSpellName then return nil end
	return GetSpellName(index, bookType)
end
local GetSpellBookItemInfo = _G.GetSpellBookItemInfo or function(index, bookType)
	if not GetSpellLink then return nil end
	local link = GetSpellLink(index, bookType)
	local id = link and tonumber(string.match(link, "spell:(%d+)"))
	if id then return "SPELL", id end
	return nil
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

-- Manually repair an unresolved saved slot using a verified LEARNED spellbook record.
-- This is deliberately explicit: a CoA raw action number is not a safe spell ID.
function ABS:MapProfileSpell(profile, slot, query)
    slot=tonumber(slot)
    if not slot or slot<1 or slot>MAX_ACTION_BUTTONS then
        self:Print('Usage: /abs map <profile> <slot> <spell name or real spell ID>');return false
    end
    local set=self.db.sets[playerClass][profile]
    if not set then self:Print('Profile does not exist: '..tostring(profile));return false end
    if not set[slot] or string.match(set[slot],'^spell|')==nil then
        self:Print('Slot '..slot..' is not a saved spell in profile '..profile);return false
    end
    local registry=self:ScanSpellbook(true)
    local matches={}
    local q=norm(query)
    for _,rec in ipairs(registry.entries) do
        if tostring(rec.id or '')==q or norm(rec.name)==q then matches[#matches+1]=rec end
    end
    if #matches~=1 then
        self:Print('Map refused: '..#matches..' exact learned spell matches for '..query..'. Try /abs lookup '..query)
        return false
    end
    local rec=matches[1]
    local old=set[slot]
    -- Retain the original profile entry for rollback; mappings never alter live bars.
    self.db.slotMapHistory=self.db.slotMapHistory or {}
    local key=playerClass..':'..profile..':'..slot
    if self.db.slotMapHistory[key]==nil then self.db.slotMapHistory[key]=old end
    local _,raw=string.match(old,'^(spell)|([^|]+)')
    set[slot]=string.format('spell|%s||%s|%s||coa6|%s|%s',tostring(raw or rec.index),
        string.gsub(rec.name,'|',' '),string.gsub(rec.rank or '','|',' '),tostring(rec.id or '?'),tostring(rec.index))
    self:Print(string.format('Mapped %s slot %d to %s [spellID=%s, bookIndex=%s]. Re-save NOT required.',profile,slot,rec.name,tostring(rec.id),tostring(rec.index)))
    return true
end

function ABS:InspectSlot(slot)
    slot=tonumber(slot)
    if not slot or slot<1 or slot>MAX_ACTION_BUTTONS then
        self:Print("Usage: /abs inspect <slot number 1-144>");return
    end
    local kind,raw,sub,extra=GetActionInfo(slot)
    local tip,rank=actionTooltip(slot)
    local registry=self:ScanSpellbook(true)
    local candidate,method=nil,nil
    -- diagnostic uses the same live extra-ID-first rules as Save
    if tonumber(extra) then
        for _,r in ipairs(registry.entries) do if tonumber(r.id)==tonumber(extra) then candidate=r;method='extra-spell-id';break end end
    end
    if not candidate then candidate,method=matchBook(tonumber(raw),tip,rank,registry.entries) end
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
-- CoA one-pass capture. Never replace a good profile with an incomplete one.
-- Resolve spell identity using the fourth GetActionInfo result first; on CoA
-- the second value is often a spellbook position and NOT a spell ID.
local function captureSpell(raw, extra, title, rank, records)
    local matches={}
    local function uniqueBy(field, value)
        value=tonumber(value)
        if not value or value<=0 then return nil end
        local found
        for _,r in ipairs(records) do
            if tonumber(r[field])==value then
                if found and found.index~=r.index then return nil end
                found=r
            end
        end
        return found
    end
    local realID=tonumber(extra)
    if realID and realID>0 then
        local rec=uniqueBy('id',realID)
        if rec then return rec, 'action-spell-id' end
    end
    -- Known CoA convention: raw sometimes represents learned spellbook index.
    local byIndex=uniqueBy('index',raw)
    local byID=uniqueBy('id',raw)
    local wanted=norm(title)
    if wanted~='' then
        local named
        for _,r in ipairs(records) do
            if norm(r.name)==wanted and (not rank or rank=='' or norm(r.rank)==norm(rank)) then
                if named then named=nil; break end
                named=r
            end
        end
        if named then return named, 'action-tooltip' end
    end
    if byIndex and byID and byIndex.index~=byID.index then return nil,'ambiguous-reference' end
    if byIndex then return byIndex,'book-index' end
    if byID then return byID,'book-id' end
    return nil,'not-in-learned-spellbook'
end

function ABS:SaveProfile(name, force)
    local previous=self.db.sets[playerClass][name]
    local existing=countSaved(previous)
    local registry=self:ScanSpellbook(true)
    local records=registry.entries
    local draft={}
    local current,unresolved=0,{}
    for slot=1,MAX_ACTION_BUTTONS do
        local kind,id,subtype,extra=GetActionInfo(slot)
        if kind and id and (slot<POSSESSION_START or slot>POSSESSION_END) then
            current=current+1
            if kind=='spell' then
                local title,rank=actionTooltip(slot)
                local rec,why=captureSpell(id,extra,title,rank,records)
                if rec and rec.id and rec.index then
                    draft[slot]=string.format('spell|%s||%s|%s|%s|coa6|%s|%s',tostring(id),
                        string.gsub(rec.name,'|',' '),string.gsub(rec.rank or '','|',' '),
                        tostring(extra or ''),tostring(rec.id),tostring(rec.index))
                else
                    unresolved[#unresolved+1]=string.format('%d (raw %s, extra %s: %s)',slot,tostring(id),tostring(extra),tostring(why))
                end
            elseif kind=='companion' then
                draft[slot]=string.format('companion|%s|||%s|',tostring(id),tostring(subtype or ''))
            elseif kind=='item' then
                draft[slot]=string.format('item|%s||%s',tostring(id),tostring(GetItemInfo(id) or ''))
            elseif kind=='equipmentset' then
                draft[slot]=string.format('equipmentset|%s|',tostring(id))
            elseif kind=='macro' then
                local mn,mi,body=GetMacroInfo(id)
                if mn and mi and body then
                    draft[slot]=string.format('macro|%s||%s|%s|%s',tostring(slot),self:CompressText(mn),mi,self:CompressText(body))
                else
                    unresolved[#unresolved+1]='macro '..slot
                end
            elseif kind=='flyout' then
                draft[slot]=string.format('flyout|%s||%s|',tostring(id),tostring((GetFlyoutInfo and GetFlyoutInfo(id)) or ''))
            else
                unresolved[#unresolved+1]=tostring(kind)..' '..slot
            end
        end
    end
    if current==0 then self:Print('Save REFUSED: active bars are empty; your backups were not changed.') return false end
    if existing>0 and current<existing and not force then
        self:Print(string.format("Save REFUSED: %d current actions versus %d in '%s'. Existing backup preserved.",current,existing,name))
        return false
    end
    if #unresolved>0 then
        self:Print(string.format('Save REFUSED: %d of %d actions could not be identified. Existing backup preserved.',#unresolved,current))
        for i=1,math.min(8,#unresolved) do self:Print('Unresolved: '..unresolved[i]) end
        if #unresolved>8 then self:Print('...and '..(#unresolved-8)..' more.') end
        self:Print('Do not overwrite a known-good profile. These actions need a supported client identity.')
        return false
    end
    self.db.sets[playerClass][name]=draft
    self:Print(string.format('Saved COMPLETE profile %s: %d actions, spellbook matched.',name,current))
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

local function compareName(value)
    value = normalName(value or "")
    value = string.gsub(value, "[^%a%d]", "")
    return value
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
        local actionNum = tonumber(actionID)
        local savedName, savedRank, unused, version, savedSpellID, savedIndex = ...
        local registry = self:ScanSpellbook(true)
        local records = registry.entries
        local chosen, exactID, exactIndex
        local options = {}

        for _, rec in ipairs(records) do
            if savedSpellID and tonumber(savedSpellID) and rec.id == tonumber(savedSpellID) then
                exactID = exactID or rec
            end
            if savedIndex and tonumber(savedIndex) and rec.index == tonumber(savedIndex) then
                exactIndex = exactIndex or rec
            end
            if compareName(savedName) ~= "" and compareName(rec.name) == compareName(savedName) then
                if not savedRank or savedRank == "" or normalName(rec.rank) == normalName(savedRank) then
                    options[#options + 1] = rec
                end
            end
        end

        if exactID and exactIndex and exactID.index == exactIndex.index then
            chosen = exactID
        elseif (version == "coa4" or version == "coa5" or version == "coa6") and exactID then
            chosen = exactID
        elseif (version == "coa4" or version == "coa5" or version == "coa6") and exactIndex then
            chosen = exactIndex
        elseif #options == 1 then
            chosen = options[1]
        elseif #options > 1 then
            for _, rec in ipairs(options) do
                if rec.id and actionNum and rec.id == actionNum then chosen = rec break end
                if rec.index and actionNum and rec.index == actionNum then chosen = rec break end
            end
        end

        if chosen then
            if InCombatLockdown and InCombatLockdown() then
                table.insert(restoreErrors, "Skipped spell slot " .. i .. ": in combat; existing action preserved.")
                return false
            end
            ClearCursor()
            local bookType = BOOKTYPE_SPELL or "spell"
            local pickup = PickupSpell or PickupSpellBookItem
            if not pickup then
                table.insert(restoreErrors, "Skipped spell slot " .. i .. ": no supported spell pickup API; existing action preserved.")
                return false
            end
            local pickupOK, pickupError = pcall(pickup, chosen.index, bookType)
            if not pickupOK then
                ClearCursor()
                table.insert(restoreErrors, "Skipped spell slot " .. i .. ": pickup failed: " .. tostring(pickupError))
                return false
            end
            if cursorPlace(i, "spell") then
                local kind, actual, subtype, extra = GetActionInfo(i)
                local actualName = actionTooltip(i)
                if kind == "spell" then
                    local actualNum = tonumber(actual)
                    local extraNum = tonumber(extra)
                    if (actualNum and chosen.index and actualNum == tonumber(chosen.index)) or
                       (actualNum and chosen.id and actualNum == tonumber(chosen.id)) or
                       (extraNum and chosen.id and extraNum == tonumber(chosen.id)) or
                       compareName(actualName) == compareName(chosen.name) or
                       compareName(actualName) == compareName(savedName) or
                       compareName(actualName) ~= "" then
                        return true
                    end
                    table.insert(restoreErrors, "Slot " .. i .. " restored as a spell but could not verify exact identity: saved '" .. tostring(savedName) .. "', read-back '" .. tostring(actualName) .. "'.")
                    return true
                end
                table.insert(restoreErrors, "Slot " .. i .. " placed but read-back returned non-spell action.")
                return false
            end
        end
        table.insert(restoreErrors, string.format("Skipped spell slot %d: '%s' (raw %s). No unambiguous learned spellbook match; current action preserved. Use /abs inspect <slot> while the spell is manually on that slot.", i, tostring(savedName), tostring(actionID)))
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
        -- Companion actions are separate from spells. Try the classic client API
        -- only if it is available; never clear an existing slot on failure.
        local _, savedType = ...
        if PickupCompanion and savedType and savedType ~= '' then
            ClearCursor()
            local ok=pcall(PickupCompanion,savedType,tonumber(actionID) or actionID)
            if ok and cursorPlace(i,'companion') then return true end
        end
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
    elseif( cmd == "map" and arg ~= "" ) then
        local profile,slot,spell=string.match(arg,'^(%S+)%s+(%d+)%s+(.+)$')
        if not profile then self:Print('Usage: /abs map <profile> <slot> <spell name or real spell ID>')
        else self:MapProfileSpell(profile,slot,spell) end
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
	if( addon == ABS.addonName or addon == "ActionBarSaver" ) then
		ABS:OnInitialize()
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

-- ===================== UI (merged in v13) =====================
do
local ABS = ActionBarSaver
local ADDON = (type((...)) == 'string' and (...)) or ABS.addonName or 'ActionBarSaver'
local panel, launcher
local selected, page = nil, 1
local rows = {}
local texPath = 'Interface\\AddOns\\' .. ADDON .. '\\Textures\\'
local sectionTex = texPath .. 'ABS_Section'
local bgTex = texPath .. 'ABS_BG'
local headerTex = texPath .. 'ABS_Header'
local logoTex = texPath .. 'ABS_Logo'
local minimapTex = texPath .. 'ABS_Minimap'
local dividerTex = texPath .. 'ABS_Divider'

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
    -- 3.3.5 bare Buttons have no FontString; SetText does nothing unless
    -- one is attached first.
    local label = b:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    label:SetPoint('CENTER', b, 'CENTER', 0, 0)
    b:SetFontString(label)
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
            b:SetText((name == selected and '> ' or '') .. name)
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
    panel:SetWidth(1040); panel:SetHeight(670)
    panel:SetPoint('CENTER', UIParent, 'CENTER', 0, 14)
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
    header:SetWidth(996); header:SetHeight(100)
    header:SetPoint('TOP', panel, 'TOP', 0, -12)

    local logo = panel:CreateTexture(nil, 'ARTWORK')
    logo:SetTexture(logoTex)
    logo:SetWidth(78); logo:SetHeight(78)
    logo:SetPoint('TOPLEFT', panel, 'TOPLEFT', 20, -18)

    makeFont(panel, 'OVERLAY', 'GameFontHighlightLarge', 19, 0.99, 0.86, 0.56, 'TOPLEFT', panel, 'TOPLEFT', 100, -26, 'ActionBarSaver')
    makeFont(panel, 'OVERLAY', 'GameFontNormal', 11, 0.74, 0.84, 0.96, 'TOPLEFT', panel, 'TOPLEFT', 102, -50, 'ArdenWoW CoA - custom backup and spellbook restore suite')
    makeFont(panel, 'OVERLAY', 'GameFontDisableSmall', 10, 0.56, 0.65, 0.78, 'TOPLEFT', panel, 'TOPLEFT', 102, -68, 'Reliable local recovery when the server fails to keep your bars')
    makeFont(panel, 'OVERLAY', 'GameFontDisableSmall', 10, 0.60, 0.74, 0.94, 'TOPLEFT', panel, 'TOPLEFT', 102, -84, 'Save after major bar changes. Scan before creating a fresh backup.')

    local close = makeButton(panel, 'X', 28, 24, function() panel:Hide() end)
    close:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -14, -14)

    local author = makeFont(panel, 'OVERLAY', 'GameFontHighlightSmall', 11, 0.86, 0.88, 0.94, 'BOTTOMRIGHT', panel, 'BOTTOMRIGHT', -18, 16, 'Created by Darkveil')
    author:SetJustifyH('RIGHT')
    makeFont(panel, 'OVERLAY', 'GameFontDisableSmall', 10, 0.54, 0.64, 0.76, 'BOTTOMLEFT', panel, 'BOTTOMLEFT', 18, 16, '/absui opens this panel  -  minimap button = quick access')

    local sec1 = makeSection(panel, 18, -112, 300, 500, 'Profiles', 'Select, name, and manage local backups')
    for i = 1, 8 do
        local b = makeButton(sec1, '', 264, 30, function(self)
            selected = self.profile
            if selected and panel.nameBox then panel.nameBox:SetText(selected) end
            refresh()
        end)
        b:SetPoint('TOPLEFT', sec1, 'TOPLEFT', 18, -62 - (i - 1) * 36)
        rows[i] = b
    end
    local prev = makeButton(sec1, '<', 36, 24, function() page = page - 1; refresh() end)
    prev:SetPoint('TOPLEFT', sec1, 'TOPLEFT', 18, -356)
    panel.pageText = makeFont(sec1, 'OVERLAY', 'GameFontHighlight', 11, 0.92, 0.92, 0.96, 'TOPLEFT', sec1, 'TOPLEFT', 68, -362, '1 / 1')
    local nextb = makeButton(sec1, '>', 36, 24, function() page = page + 1; refresh() end)
    nextb:SetPoint('TOPLEFT', sec1, 'TOPLEFT', 246, -356)
    panel.countText = makeFont(sec1, 'OVERLAY', 'GameFontDisableSmall', 10, 0.72, 0.79, 0.88, 'TOPLEFT', sec1, 'TOPLEFT', 120, -363, '0 local profiles')
    panel.selectedText = makeFont(sec1, 'OVERLAY', 'GameFontHighlightSmall', 11, 0.93, 0.84, 0.55, 'TOPLEFT', sec1, 'TOPLEFT', 18, -394, 'Selected: none')

    local selectedBox = CreateFrame('Frame', nil, sec1)
    selectedBox:SetWidth(264); selectedBox:SetHeight(42)
    selectedBox:SetPoint('TOPLEFT', sec1, 'TOPLEFT', 18, -416)
    selectedBox:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8x8', edgeFile='Interface\\Tooltips\\UI-Tooltip-Border', tile=true, tileSize=8, edgeSize=10, insets={left=3,right=3,top=3,bottom=3}})
    selectedBox:SetBackdropColor(0.04,0.06,0.10,0.70)
    selectedBox:SetBackdropBorderColor(0.36,0.45,0.60,0.70)
    makeFont(selectedBox, 'OVERLAY', 'GameFontNormalSmall', 10, 0.82, 0.87, 0.95, 'TOPLEFT', selectedBox, 'TOPLEFT', 10, -10, 'Profile name')
    local nameFrame, nameBox = makeEditBox(selectedBox, 244, 22)
    nameFrame:SetPoint('TOPLEFT', selectedBox, 'TOPLEFT', 10, -18)
    panel.nameBox = nameBox

    local deleteb = makeButton(sec1, 'Delete Profile', 264, 30, function()
        if not selected or selected == '' then safePrint('Select a profile first.') return end
        StaticPopupDialogs['ABS_DARKVEIL_DELETE'] = {
            text = 'Permanently DELETE profile "%s"? This cannot be undone.',
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
    deleteb:SetPoint('TOPLEFT', sec1, 'TOPLEFT', 18, -461)
    deleteb:SetBackdropBorderColor(0.80, 0.30, 0.30, 1)

    local sec2 = makeSection(panel, 332, -112, 346, 500, 'Backup Actions', 'Core tools for saving, scanning, and restoring')
    local saveNamed = makeButton(sec2, 'Save Named', 148, 32, function()
        local name = clean(panel.nameBox)
        if name == '' then safePrint('Enter a profile name first.') return end
        run('save ' .. string.lower(name))
        selected = string.lower(name)
        refresh()
    end)
    saveNamed:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 18, -66)

    local forceSave = makeButton(sec2, 'Save Force', 148, 32, function()
        local name = clean(panel.nameBox)
        if name == '' then safePrint('Enter a profile name first.') return end
        run('saveforce ' .. string.lower(name))
        selected = string.lower(name)
        refresh()
    end)
    forceSave:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 178, -66)

    local snap = makeButton(sec2, 'New Snapshot', 308, 34, function() run('snapshot'); refresh() end)
    snap:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 18, -108)

    local restore = makeButton(sec2, 'Restore Selected', 308, 36, function()
        if InCombatLockdown and InCombatLockdown() then safePrint('Leave combat before restoring.') return end
        doSelected('restore')
    end)
    restore:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 18, -152)

    local audit = makeButton(sec2, 'Audit Selected', 148, 30, function() doSelected('audit') end)
    audit:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 18, -198)
    local errors = makeButton(sec2, 'Show Errors', 148, 30, function() run('errors') end)
    errors:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 178, -198)

    local listb = makeButton(sec2, 'List Profiles', 308, 30, function() run('list') end)
    listb:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 18, -236)


    local toolBox = CreateFrame('Frame', nil, sec2)
    toolBox:SetWidth(308); toolBox:SetHeight(210)
    toolBox:SetPoint('TOPLEFT', sec2, 'TOPLEFT', 18, -272)
    toolBox:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8x8', edgeFile='Interface\\Tooltips\\UI-Tooltip-Border', tile=true, tileSize=8, edgeSize=10, insets={left=3,right=3,top=3,bottom=3}})
    toolBox:SetBackdropColor(0.03,0.05,0.09,0.75)
    toolBox:SetBackdropBorderColor(0.36,0.45,0.60,0.75)

    makeFont(toolBox, 'OVERLAY', 'GameFontHighlightSmall', 11, 0.95, 0.83, 0.52, 'TOPLEFT', toolBox, 'TOPLEFT', 12, -12, 'Spellbook Tools')
    makeFont(toolBox, 'OVERLAY', 'GameFontNormalSmall', 10, 0.82, 0.87, 0.95, 'TOPLEFT', toolBox, 'TOPLEFT', 12, -36, 'Lookup spell (name or ID)')
    local lookupFrame, lookupBox = makeEditBox(toolBox, 284, 24)
    lookupFrame:SetPoint('TOPLEFT', toolBox, 'TOPLEFT', 12, -52)
    panel.lookupBox = lookupBox
    local lookup = makeButton(toolBox, 'Lookup Spell', 284, 28, function()
        local q = clean(panel.lookupBox)
        if q == '' then safePrint('Enter a spell name or ID.') return end
        run('lookup ' .. q)
    end)
    lookup:SetPoint('TOPLEFT', toolBox, 'TOPLEFT', 12, -82)

    makeFont(toolBox, 'OVERLAY', 'GameFontNormalSmall', 10, 0.82, 0.87, 0.95, 'TOPLEFT', toolBox, 'TOPLEFT', 12, -122, 'Inspect action slot')
    local slotFrame, slotBox = makeEditBox(toolBox, 88, 24)
    slotFrame:SetPoint('TOPLEFT', toolBox, 'TOPLEFT', 12, -138)
    panel.slotBox = slotBox
    local inspect = makeButton(toolBox, 'Inspect', 90, 28, function()
        local slot = clean(panel.slotBox)
        if not tonumber(slot) then safePrint('Enter a valid action slot number.') return end
        run('inspect ' .. slot)
    end)
    inspect:SetPoint('TOPLEFT', toolBox, 'TOPLEFT', 108, -138)
    local scan = makeButton(toolBox, 'Scan Spellbook', 94, 28, function() run('scan') end)
    scan:SetPoint('TOPLEFT', toolBox, 'TOPLEFT', 202, -138)
    local mapButton = makeButton(toolBox, 'Repair Selected Profile Slot (Spell ID / Name)', 284, 28, function()
        if not selected then safePrint('Select a saved profile first.') return end
        local slot = tonumber(clean(panel.slotBox))
        local spell = clean(panel.lookupBox)
        if not slot or slot < 1 or slot > MAX_ACTION_BUTTONS then safePrint('Enter a valid saved action slot.') return end
        if spell == '' then safePrint('Enter an exact spell ID or spell name in Lookup Spell.') return end
        -- Safe operation: changes only the saved profile. Does not touch live bars.
        run('map ' .. selected .. ' ' .. slot .. ' ' .. spell)
    end)
    mapButton:SetPoint('TOPLEFT', toolBox, 'TOPLEFT', 12, -176)


    local sec3 = makeSection(panel, 692, -112, 330, 500, 'Options & Reference', 'Cleaner controls and a smaller quick guide')
    panel.macroToggle = makeButton(sec3, '', 92, 30, function() run('macro'); refresh() end)
    panel.macroToggle:SetPoint('TOPLEFT', sec3, 'TOPLEFT', 18, -66)
    panel.rankToggle = makeButton(sec3, '', 92, 30, function() run('rank'); refresh() end)
    panel.rankToggle:SetPoint('TOPLEFT', sec3, 'TOPLEFT', 118, -66)
    panel.countToggle = makeButton(sec3, '', 92, 30, function() run('count'); refresh() end)
    panel.countToggle:SetPoint('TOPLEFT', sec3, 'TOPLEFT', 218, -66)

    local guide = CreateFrame('Frame', nil, sec3)
    guide:SetWidth(292); guide:SetHeight(248)
    guide:SetPoint('TOPLEFT', sec3, 'TOPLEFT', 18, -110)
    guide:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8x8', edgeFile='Interface\\Tooltips\\UI-Tooltip-Border', tile=true, tileSize=8, edgeSize=10, insets={left=3,right=3,top=3,bottom=3}})
    guide:SetBackdropColor(0.03,0.05,0.09,0.75)
    guide:SetBackdropBorderColor(0.36,0.45,0.60,0.75)
    makeFont(guide, 'OVERLAY', 'GameFontHighlight', 12, 0.95, 0.83, 0.52, 'TOPLEFT', guide, 'TOPLEFT', 12, -14, 'Quick Guide')
    local lines = {
        'Save Named  - save your current bars to the profile name box',
        'Save Force  - overwrite a profile even if counts are lower',
        'New Snapshot  - create a numbered backup for rollback',
        'Restore Selected  - restore the selected profile safely',
        'Scan Spellbook  - refresh your CoA spell registry first',
        'Lookup Spell / Inspect  - debug custom skill matching',
        'Show Errors  - review any skipped or unresolved slots',
        '/absui  - open this panel any time',
    }
    local y = -38
    for _, line in ipairs(lines) do
        local fs = makeFont(guide, 'OVERLAY', 'GameFontDisableSmall', 10, 0.78, 0.84, 0.94, 'TOPLEFT', guide, 'TOPLEFT', 12, y, line)
        fs:SetWidth(266)
        fs:SetJustifyH('LEFT')
        y = y - 26
    end

    local notes = CreateFrame('Frame', nil, sec3)
    notes:SetWidth(292); notes:SetHeight(112)
    notes:SetPoint('TOPLEFT', sec3, 'TOPLEFT', 18, -368)
    notes:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8x8', edgeFile='Interface\\Tooltips\\UI-Tooltip-Border', tile=true, tileSize=8, edgeSize=10, insets={left=3,right=3,top=3,bottom=3}})
    notes:SetBackdropColor(0.08,0.10,0.16,0.82)
    notes:SetBackdropBorderColor(0.72,0.58,0.28,0.72)
    makeFont(notes, 'OVERLAY', 'GameFontHighlightSmall', 11, 0.95, 0.83, 0.52, 'TOPLEFT', notes, 'TOPLEFT', 10, -12, 'Best Practice')
    local t = makeFont(notes, 'OVERLAY', 'GameFontDisableSmall', 10, 0.78, 0.84, 0.94, 'TOPLEFT', notes, 'TOPLEFT', 10, -30,
        '1) Scan spellbook after logging in\n2) Save a named profile and a snapshot\n3) Restore only outside combat\n4) If one skill fails, use Lookup Spell and Inspect to compare it')
    t:SetWidth(268)
    t:SetJustifyH('LEFT')

    panel:SetScript('OnShow', refresh)
    panel:Hide()
end

local function makeLauncher()
    if launcher then return end
    launcher = CreateFrame('Button', 'ABSCoAMinimapButton', Minimap)
    launcher:SetWidth(31); launcher:SetHeight(31)
    launcher:SetFrameStrata('MEDIUM'); launcher:SetFrameLevel(8)
    launcher:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')

    launcher:SetBackdrop({bgFile = 'Interface\\Buttons\\WHITE8x8', edgeFile='Interface\\Tooltips\\UI-Tooltip-Border', tile=false, edgeSize=10, insets={left=2,right=2,top=2,bottom=2}})
    launcher:SetBackdropColor(0.06, 0.10, 0.18, 1)
    launcher:SetBackdropBorderColor(0.85, 0.68, 0.35, 1)
    local icon = launcher:CreateTexture(nil, 'ARTWORK')
    -- Built-in icon instead of external custom TGA: supported by the 3.3.5 texture loader.
    icon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
    icon:SetWidth(23); icon:SetHeight(23)
    icon:SetPoint('CENTER', launcher, 'CENTER', 0, 0)

    local function reposition()
        local db = ABS.db or {}
        local angle = tonumber(db.minimapAngle) or 225
        launcher:ClearAllPoints()
        launcher:SetPoint('CENTER', Minimap, 'CENTER', math.cos(math.rad(angle)) * 80, math.sin(math.rad(angle)) * 80)
        if db.minimapHidden then launcher:Hide() else launcher:Show() end
    end

    launcher:RegisterForDrag('LeftButton')
    launcher:SetScript('OnMouseDown', function(self) self.dragged = false end)
    launcher:SetScript('OnDragStart', function(self) self.dragging = true; self.dragged = true end)
    launcher:SetScript('OnDragStop', function(self) self.dragging = false end)
    launcher:SetScript('OnUpdate', function(self)
        if not self.dragging then return end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        x = x / scale; y = y / scale
        local mx, my = Minimap:GetCenter()
        local a = math.deg(math.atan2(y - my, x - mx))
        if ABS.db then ABS.db.minimapAngle = a end
        reposition()
    end)
    launcher:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    launcher:SetScript('OnClick', function(self, button)
        if self.dragging or self.dragged then self.dragged = false return end
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

-- ---------------------------------------------------------------------------
-- Startup (v11 fix)
-- The options panel and slash commands are registered right away at file load.
-- They do not need the database. The minimap button is built on PLAYER_LOGIN,
-- which on 3.3.5 always fires after every ADDON_LOADED, so SavedVariables are
-- guaranteed to be in place by then.
-- ---------------------------------------------------------------------------
local optionsPanel, optionsDone = nil, false

local function report(err)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cffff6666ABS Darkveil UI:|r ' .. tostring(err)) end
end

-- Only call after PLAYER_LOGIN. Calling OnInitialize earlier would build a
-- blank DB that the real SavedVariables then replace.
local function ensureDB()
    if not ABS then return false end
    if not ABS.db and ABS.OnInitialize then
        local ok, err = pcall(ABS.OnInitialize, ABS)
        if not ok then report('database: ' .. tostring(err)) end
    end
    return ABS.db ~= nil
end

local function openPanel()
    local ok, err = pcall(function() ABS:ToggleUI() end)
    if not ok then report(err) end
end

local function setMinimap(hidden)
    if not ensureDB() then report('database is not initialized yet, try again after login') return end
    ABS.db.minimapHidden = hidden and true or false
    if not launcher then
        local ok, err = pcall(makeLauncher)
        if not ok then report('minimap: ' .. tostring(err)) return end
    end
    if ABS.db.minimapHidden then launcher:Hide() else launcher:Show() end
end

SLASH_ABSUI1 = '/absui'
SlashCmdList['ABSUI'] = openPanel
SLASH_ABSMINIMAP1 = '/absminimap'
SlashCmdList['ABSMINIMAP'] = function(msg)
    local arg = string.lower(trimmed(msg))
    if arg == 'show' then setMinimap(false)
    elseif arg == 'hide' then setMinimap(true)
    elseif arg == 'reset' then
        if ensureDB() then ABS.db.minimapAngle = 225 end
        setMinimap(false)
        if launcher then
            launcher:ClearAllPoints()
            launcher:SetPoint('CENTER', Minimap, 'CENTER', math.cos(math.rad(225)) * 80, math.sin(math.rad(225)) * 80)
        end
    else
        setMinimap(not (ABS.db and ABS.db.minimapHidden))
    end
end

local function registerOptions()
    if optionsDone or type(InterfaceOptions_AddCategory) ~= 'function' then return end
    optionsPanel = CreateFrame('Frame', 'ABSDarkveilInterfaceOptions', InterfaceOptionsFramePanelContainer or UIParent)
    optionsPanel:Hide()
    optionsPanel.name = 'ActionBarSaver'

    local title = optionsPanel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
    title:SetPoint('TOPLEFT', optionsPanel, 'TOPLEFT', 16, -16)
    title:SetText('ActionBarSaver - Darkveil Edition')

    local description = optionsPanel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    description:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -8)
    description:SetWidth(400)
    description:SetJustifyH('LEFT')
    description:SetText('Local snapshots and CoA custom spellbook registry. Created by Darkveil.')

    local open = CreateFrame('Button', 'ABSDarkveilOptOpen', optionsPanel, 'UIPanelButtonTemplate')
    open:SetWidth(250); open:SetHeight(26)
    open:SetPoint('TOPLEFT', description, 'BOTTOMLEFT', 0, -20)
    open:SetText('Open ActionBarSaver Dashboard')
    open:SetScript('OnClick', function()
        if InterfaceOptionsFrame then InterfaceOptionsFrame:Hide() end
        if GameMenuFrame then GameMenuFrame:Hide() end
        openPanel()
    end)

    local mini = CreateFrame('Button', 'ABSDarkveilOptMinimap', optionsPanel, 'UIPanelButtonTemplate')
    mini:SetWidth(250); mini:SetHeight(26)
    mini:SetPoint('TOPLEFT', open, 'BOTTOMLEFT', 0, -10)
    mini:SetText('Toggle Minimap Button')
    mini:SetScript('OnClick', function() SlashCmdList['ABSMINIMAP']('') end)

    local scan = CreateFrame('Button', 'ABSDarkveilOptScan', optionsPanel, 'UIPanelButtonTemplate')
    scan:SetWidth(250); scan:SetHeight(26)
    scan:SetPoint('TOPLEFT', mini, 'BOTTOMLEFT', 0, -10)
    scan:SetText('Scan Spellbook')
    scan:SetScript('OnClick', function() run('scan') end)

    local hint = optionsPanel:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
    hint:SetPoint('TOPLEFT', scan, 'BOTTOMLEFT', 0, -16)
    hint:SetText('/absui opens the dashboard. /absminimap show | hide | reset')

    InterfaceOptions_AddCategory(optionsPanel)
    optionsDone = true
end

do
    local ok, err = pcall(registerOptions)
    if not ok then report('settings: ' .. tostring(err)) end
end

local function onLogin()
    if not ensureDB() then
        report('core did not load, so the minimap button was skipped. Check for a Lua error from ActionBarSaver.lua.')
        return
    end
    if not optionsDone then
        local ok, err = pcall(registerOptions)
        if not ok then report('settings: ' .. tostring(err)) end
    end
    local ok, err = pcall(makeLauncher)
    if not ok then report('minimap: ' .. tostring(err)) end
    if ABS.db.minimapHidden and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage('|cff33ff99ABS|r: minimap button is hidden. Type /absminimap show to bring it back.')
    end
end

local startup = CreateFrame('Frame')
startup:RegisterEvent('PLAYER_LOGIN')
startup:RegisterEvent('ADDON_LOADED')
startup:SetScript('OnEvent', function(self, event, addon)
    if event == 'ADDON_LOADED' then
        if addon ~= ADDON then return end
        self:UnregisterEvent('ADDON_LOADED')
        -- Only matters when the addon is loaded after login (addon manager).
        if not (IsLoggedIn and IsLoggedIn()) then return end
    end
    self:UnregisterAllEvents()
    onLogin()
end)

end

-- Version banner so it's obvious in chat which build is running.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        local ui = (ActionBarSaver and ActionBarSaver.ToggleUI) and "ok" or "MISSING"
        local mm = _G.ABSCoAMinimapButton and "ok" or "MISSING"
        local opt = _G.ABSDarkveilInterfaceOptions and "ok" or "MISSING"
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ABS v18|r loaded. UI: " .. ui .. ", minimap: " .. mm .. ", options: " .. opt .. ". Type /absui")
    end)
end
