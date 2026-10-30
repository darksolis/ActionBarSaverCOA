if( GetLocale() ~= "koKR" ) then return end
local L = {}

ActionBarSaver = ActionBarSaver or select(2, ...) or {}
local ABS = ActionBarSaver
ABS.L = setmetatable(L, {__index = ABS.L})
