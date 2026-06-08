-- scratchpad.koplugin — a per-book (and global) note scratchpad for KOReader.
--
-- While reading, open a full-screen editable note backed by a plain text file.
-- Per-book notes are keyed by the book (stable md5 when available), so each
-- book gets its own pad; there's also one shared "global" pad.
--
-- Open it from:  Reader menu → More tools → Scratchpad
-- or bind it to a gesture:  Settings → Taps and gestures → Gesture manager →
--   (pick a gesture) → "Scratchpad: this book" / "Scratchpad: global"
--
-- Notes live in:  koreader/scratchpads/<book-id>.txt  (and _global.txt)

local DataStorage     = require("datastorage")
local Dispatcher      = require("dispatcher")
local InputDialog     = require("ui/widget/inputdialog")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs             = require("libs/libkoreader-lfs")
local util            = require("util")
local _               = require("gettext")

local SCRATCH_DIR = DataStorage:getDataDir() .. "/scratchpads"

local Scratchpad = WidgetContainer:extend{
    name = "scratchpad",
    -- Reader-only: a scratchpad is for notes WHILE reading a book. This also
    -- keeps it out of the File-Manager / SimpleUI-home menu, whose sections
    -- don't include "navi" (registering there with that hint crashes the menu).
    is_doc_only = true,
}

function Scratchpad:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

-- Make both actions bindable to gestures / profiles.
function Scratchpad:onDispatcherRegisterActions()
    Dispatcher:registerAction("scratchpad_book",
        { category = "none", event = "ScratchpadBook",   title = _("Scratchpad: this book"), general = true })
    Dispatcher:registerAction("scratchpad_global",
        { category = "none", event = "ScratchpadGlobal", title = _("Scratchpad: global"), general = true, separator = true })
end

function Scratchpad:addToMainMenu(menu_items)
    menu_items.scratchpad = {
        text = _("Scratchpad"),
        sorting_hint = "navi",   -- first top-level tab (Navigation), next to bookmarks
        sub_item_table = {
            {
                text = _("This book's scratchpad"),
                callback = function() self:openScratchpad(false) end,
            },
            {
                text = _("Global scratchpad"),
                callback = function() self:openScratchpad(true) end,
            },
        },
    }
end

-- ---------------------------------------------------------------------------
-- File helpers
-- ---------------------------------------------------------------------------
local function ensureDir()
    if lfs.attributes(SCRATCH_DIR, "mode") ~= "directory" then
        lfs.mkdir(SCRATCH_DIR)
    end
end

-- Stable id for the open book: prefer the partial md5 (survives renames),
-- fall back to a sanitized filename, else nil (no book open).
function Scratchpad:_bookId()
    local md5
    if self.ui and self.ui.doc_settings then
        local ok, v = pcall(function() return self.ui.doc_settings:readSetting("partial_md5_checksum") end)
        if ok then md5 = v end
    end
    if type(md5) == "string" and md5 ~= "" then return md5 end
    local fp = self.ui and self.ui.document and self.ui.document.file
    if fp then
        local base = fp:gsub(".*/", "")
        return (base:gsub("[^%w%-_%.]", "_"))
    end
    return nil
end

function Scratchpad:_filePath(global)
    ensureDir()
    if global then return SCRATCH_DIR .. "/_global.txt" end
    local id = self:_bookId()
    if not id then return SCRATCH_DIR .. "/_global.txt" end
    return SCRATCH_DIR .. "/" .. id .. ".txt"
end

-- ---------------------------------------------------------------------------
-- The editor
-- ---------------------------------------------------------------------------
function Scratchpad:openScratchpad(global)
    local path = self:_filePath(global)

    local title
    if global then
        title = _("Scratchpad (all books)")
    else
        local fp = self.ui and self.ui.document and self.ui.document.file
        title = (fp and fp:gsub(".*/", "")) or _("Scratchpad")
    end

    self.input = InputDialog:new{
        title             = title,
        input             = util.readFromFile(path, "rb") or "",
        fullscreen        = true,
        condensed         = true,
        allow_newline     = true,
        add_nav_bar       = true,        -- gives the Reset / Save / Close bar
        scroll_by_pan     = true,
        keyboard_visible  = true,
        -- Save button (and save-on-close) route here:
        save_callback = function(content, closing)  -- luacheck: no unused
            local ok = util.writeToFile(content or "", path)
            if ok then return true, _("Scratchpad saved") end
            return false, _("Could not save scratchpad")
        end,
        -- Reset button restores the last saved content:
        reset_callback = function()
            return util.readFromFile(path, "rb") or "", _("Reset to last saved")
        end,
    }
    UIManager:show(self.input)
    self.input:onShowKeyboard()
end

-- Gesture / dispatcher entry points
function Scratchpad:onScratchpadBook()
    self:openScratchpad(false)
    return true
end

function Scratchpad:onScratchpadGlobal()
    self:openScratchpad(true)
    return true
end

return Scratchpad
