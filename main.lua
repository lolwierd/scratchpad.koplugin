-- scratchpad.koplugin — a per-book (and global) note scratchpad for KOReader.
--
-- While reading, open a full-screen editable note backed by a plain text file.
-- Per-book notes are keyed by the book (stable md5 when available), so each
-- book gets its own pad; there's also one shared "global" pad.
--
-- Sections: any line that starts with "#" (e.g. "# Characters", "## Act II")
-- is treated as a section heading. Use the Sections submenus to jump straight
-- to a section's text, or add a new one.
--
-- Open it from:  Reader menu → Navigation → Scratchpad
-- or bind it to a gesture:  Settings → Taps and gestures → Gesture manager →
--   (pick a gesture) → "Scratchpad: this book" / "Scratchpad: global"
--
-- Notes live in:  koreader/scratchpads/<book-id>.txt  (and _global.txt)

local DataStorage     = require("datastorage")
local Dispatcher      = require("dispatcher")
local InputDialog     = require("ui/widget/inputdialog")
local Menu            = require("ui/widget/menu")
local Notification    = require("ui/widget/notification")
local Screen          = require("device").screen
local TextViewer      = require("ui/widget/textviewer")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs             = require("libs/libkoreader-lfs")
local util            = require("util")
local _               = require("gettext")
local T               = require("ffi/util").template

local SCRATCH_DIR = DataStorage:getDataDir() .. "/scratchpads"

local Scratchpad = WidgetContainer:extend{
    name = "scratchpad",
    -- Reader-only: a scratchpad is for notes WHILE reading a book. This also
    -- keeps it out of the File-Manager / SimpleUI-home menu, whose sections
    -- don't include "navi" (registering there with that hint crashes the menu).
    is_doc_only = true,
}

function Scratchpad:init()
    self._view_pos = {} -- remembers {top_line_num, charpos} per note path (this session)
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
            {
                text_func = function()
                    return T(_("Sections — this book (%1)"), #self:_sections(false))
                end,
                separator = true,
                sub_item_table_func = function() return self:_sectionsMenu(false) end,
            },
            {
                text_func = function()
                    return T(_("Sections — global (%1)"), #self:_sections(true))
                end,
                sub_item_table_func = function() return self:_sectionsMenu(true) end,
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

function Scratchpad:_read(global)
    return util.readFromFile(self:_filePath(global), "rb") or ""
end

function Scratchpad:_title(global)
    if global then return _("Scratchpad (all books)") end
    local fp = self.ui and self.ui.document and self.ui.document.file
    return (fp and fp:gsub(".*/", "")) or _("Scratchpad")
end

-- ---------------------------------------------------------------------------
-- Sections  (a "heading" line starts with one or more '#', e.g. "# Characters")
-- ---------------------------------------------------------------------------

-- Parse section headings out of arbitrary text. Each section carries its
-- title, the raw heading line (used to locate it for navigation), and body.
local function parse_sections(text)
    local sections = {}
    if not text or text == "" then return sections end
    local cur
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local title = line:match("^%s*#+%s+(.-)%s*$")
        if title then
            cur = { title = title, heading = line, lines = {} }
            sections[#sections + 1] = cur
        elseif cur then
            cur.lines[#cur.lines + 1] = line
        end
    end
    for _i, s in ipairs(sections) do
        s.body = (table.concat(s.lines, "\n"):gsub("^%s+", ""):gsub("%s+$", ""))
    end
    return sections
end

function Scratchpad:_sections(global)
    return parse_sections(self:_read(global))
end

function Scratchpad:_sectionsMenu(global)
    local items = {}
    for _i, s in ipairs(self:_sections(global)) do
        items[#items + 1] = {
            text = s.title,
            callback = function() self:_viewSection(global, s) end,
        }
    end
    items[#items + 1] = {
        text = _("New section…"),
        separator = #items > 0,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:_newSection(global, touchmenu_instance)
        end,
    }
    return items
end

function Scratchpad:_viewSection(global, section)
    local viewer
    viewer = TextViewer:new{
        title = section.title,
        text = section.body ~= "" and section.body or _("(empty section)"),
        justified = false,
        add_default_buttons = true,
        buttons_table = {
            {
                { text = _("Edit note"), callback = function()
                    UIManager:close(viewer)
                    self:openScratchpad(global)
                end },
            },
        },
    }
    UIManager:show(viewer)
end

function Scratchpad:_newSection(global, touchmenu_instance)
    local dialog
    dialog = InputDialog:new{
        title = _("New section heading"),
        input = "",
        input_hint = _("e.g. Characters"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Create"), is_enter_default = true, callback = function()
                local name = dialog:getInputText()
                UIManager:close(dialog)
                if not name or name == "" then return end
                local path = self:_filePath(global)
                local existing = util.readFromFile(path, "rb") or ""
                local sep = (existing ~= "" and not existing:match("\n$")) and "\n\n" or "\n"
                util.writeToFile(existing .. sep .. "# " .. name .. "\n", path)
                if touchmenu_instance then touchmenu_instance:updateItems() end
                self:openScratchpad(global, { at_end = true })
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- From inside the open editor: list the headings in the *current* (possibly
-- unsaved) text and jump the cursor to the chosen one.
function Scratchpad:_navToSections()
    local id = self.input
    if not id then return end
    local text = id:getInputText() or ""
    local sections = parse_sections(text)
    if #sections == 0 then
        UIManager:show(Notification:new{ text = _("No sections. Start a line with #") })
        return
    end
    -- Resolve each heading to a char position (progressive search so duplicate
    -- heading text still maps to the right occurrence, in document order).
    local search_from = 1
    local items = {}
    for _i, s in ipairs(sections) do
        local cp = util.stringSearch(text, s.heading, true, search_from)
        if cp and cp > 0 then search_from = cp + 1 end
        items[#items + 1] = {
            text = s.title,
            callback = function()
                if cp and cp > 0 and id._input_widget then
                    id._input_widget:moveCursorToCharPos(cp)
                end
            end,
        }
    end
    local menu
    menu = Menu:new{
        title = _("Sections"),
        item_table = items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
end

-- ---------------------------------------------------------------------------
-- The editor
-- ---------------------------------------------------------------------------
function Scratchpad:openScratchpad(global, opts)
    opts = opts or {}
    local path = self:_filePath(global)

    self.input = InputDialog:new{
        title             = self:_title(global),
        input             = util.readFromFile(path, "rb") or "",
        fullscreen        = true,
        condensed         = true,
        allow_newline     = true,
        -- Don't force the cursor to the end on open: that's what made big notes
        -- jump to the bottom and show phantom space. (Same as texteditor.koplugin.)
        cursor_at_end     = opts.at_end == true,
        add_nav_bar       = true,        -- gives the Reset / Save / Close bar
        scroll_by_pan     = true,
        keyboard_visible  = true,
        auto_para_direction = true,
        -- A "Sections" button in the bar (Reset/Save/Close get appended to this
        -- same first row by InputDialog).
        buttons = {
            {
                { text = _("Sections"), callback = function() self:_navToSections() end },
            },
        },
        -- Remember scroll/cursor position across the re-inits that happen while
        -- typing or toggling the keyboard, so the view stays put.
        view_pos_callback = (not opts.at_end) and function(top_line_num, charpos)
            if top_line_num and charpos then
                self._view_pos[path] = { top_line_num, charpos }
            else
                local p = self._view_pos[path]
                if p then return p[1], p[2] end
                return nil, nil
            end
        end or nil,
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
