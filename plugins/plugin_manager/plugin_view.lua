local core = require "core"
local style = require "core.style"
local common = require "core.common"
local config = require "core.config"
local command = require "core.command"
local keymap = require "core.keymap"
local View = require "core.view"
local RootView = require "core.rootview"
local ContextMenu = require "core.contextmenu"
local Widget = require "widget"
local WidgetList = require "widget.widgetlist"
local TextBox = require "widget.textbox"
local SelectBox = require "widget.selectbox"
local CheckBox = require "widget.checkbox"
local Button = require "widget.button"
local Label = require "widget.label"

local PluginView = Widget:extend()
local sort_fields = { "name", "version", "type", "status", "tags", "author", "description" }
PluginView.menu = ContextMenu()

local function index_of(values, value)
  for index, item in ipairs(values) do if item == value then return index end end
end

local function release_mouse(self, ...)
  local handled = Widget.on_mouse_released(self, ...)
  -- Older widgets leave container press flags set when a child consumes the release.
  self.mouse_is_pressed = false
  return handled
end

local function display_name(plugin)
  local name = plugin.name or plugin.id
  return name ~= plugin.id and (name .. " (" .. plugin.id .. ")") or name
end

local function row_key(plugin)
  return table.concat({ plugin.id, plugin.type or "", tostring(plugin.version or ""),
    plugin.repository or "", plugin.path or "" }, "\t")
end

local function status_color(status)
  if status == "installed" or status == "bundled" or status == "orphan" then return style.good end
  if status == "upgradable" then return style.accent end
  if status == "core" then return style.warn end
  if status == "special" then return style.modified end
  return style.text
end

local function inside_userdir(path)
  local root = config.plugins.plugin_manager.userdir or USERDIR
  if not path then return false end
  path, root = path:gsub("\\", "/"), root:gsub("\\", "/"):gsub("/+$", "")
  if PLATFORM == "Windows" then path, root = path:lower(), root:lower() end
  return path:sub(1, #root + 1) == root .. "/"
end

local function eligible(plugin, action)
  if not plugin then return false end
  if action == "install" then return plugin.status == "available" end
  if action == "upgrade" then return plugin.status == "upgradable" end
  if action == "uninstall" then
    return (plugin.status == "installed" or plugin.status == "orphan" or plugin.status == "upgradable")
      and inside_userdir(plugin.path)
  end
  return false
end

local function selectable(plugin)
  return eligible(plugin, "install") or eligible(plugin, "upgrade") or eligible(plugin, "uninstall")
end

local function fitting_length(font, text, width, suffix)
  local low, high = 0, text:ulen()
  while low < high do
    local mid = math.ceil((low + high) / 2)
    if font:get_width(text:usub(1, mid) .. (suffix or "")) <= width then low = mid else high = mid - 1 end
  end
  return low
end

local function fit_text(font, text, width)
  text = tostring(text or "")
  if width <= 0 then return "" end
  if font:get_width(text) <= width then return text end
  if font:get_width("...") > width then return "" end
  return text:usub(1, fitting_length(font, text, width, "...")) .. "..."
end

local function wrap_text(font, text, width)
  local lines = {}
  width = math.max(font:get_width("W"), width)
  for paragraph in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for token in paragraph:gmatch("%S+") do
      local word = token
      if line ~= "" and font:get_width(line .. " " .. word) > width then
        lines[#lines + 1], line = line, ""
      end
      while font:get_width(word) > width do
        local length = math.max(1, fitting_length(font, word, width))
        lines[#lines + 1], word = word:usub(1, length), word:usub(length + 1)
      end
      line = line == "" and word or line .. " " .. word
    end
    lines[#lines + 1] = line
  end
  return lines
end

local FittedLabel = Label:extend()
function FittedLabel:draw()
  if not self:is_visible() then return false end
  local x, y = self:get_content_offset()
  renderer.draw_text(self:get_font(), fit_text(self:get_font(), self.label, self.size.x),
    x, y, self.foreground_color or style.text)
  return true
end

local CatalogSelectBox = SelectBox:extend()
function CatalogSelectBox:update_size_position()
  CatalogSelectBox.super.update_size_position(self)
  local _, height = system.get_window_size(core.window)
  local rows = math.min(8, #self.list.rows)
  self.list_container:set_size(nil, math.min(height / 2,
    rows * (self:get_font():get_height() + style.padding.y) + style.padding.y))
end
function CatalogSelectBox:draw()
  self.border.color = core.active_view == self and style.accent or nil
  return CatalogSelectBox.super.draw(self)
end

local ActionButton = Button:extend()
function ActionButton:new(parent, label, icon, callback, width_label)
  ActionButton.super.new(self, parent, label)
  self.padding.x = style.padding.x / 2
  self.width_label = width_label or label
  self.enabled = true
  self:set_icon(icon)
  self.callback = callback
  self:update_size_position()
end
function ActionButton:update_size_position()
  ActionButton.super.update_size_position(self)
  local icon = self.icon.code and style.icon_font:get_width(self.icon.code) or 0
  if self.icon.code and self.label ~= "" then icon = icon + style.padding.x / 2 end
  self.size.x = self:get_font():get_width(self.width_label) + self.padding.x * 2 + icon
  if self.label == "" then self.size.x = math.max(self.size.x, self.size.y) end
end
function ActionButton:on_click(button)
  if self.enabled and button == "left" then self.callback() end
end
function ActionButton:draw()
  self.foreground_color = self.enabled and style.text or style.dim
  self.icon.color = self.foreground_color
  self.border.color = core.active_view == self and style.accent or nil
  if not self.enabled then self.hover_text, self.hover_back = nil, nil end
  local content_width = self:get_font():get_width(self.label)
  if self.icon.code then
    content_width = content_width + style.icon_font:get_width(self.icon.code)
    if self.label ~= "" then content_width = content_width + style.padding.x / 2 end
  end
  local padding = self.padding.x
  self.padding.x = (self.size.x - content_width) / 2
  local drawn = ActionButton.super.draw(self)
  self.padding.x = padding
  return drawn
end

local PluginSummary = Widget:extend()
function PluginSummary:new(parent, plugin)
  PluginSummary.super.new(self, parent)
  self.plugin = plugin
  self.border.width, self.clickable, self.render_background = 0, false, false
  self:set_size(nil, style.font:get_height() * 2 + style.padding.y / 2)
end
function PluginSummary:update_size_position()
  PluginSummary.super.update_size_position(self)
  self:set_size(nil, style.font:get_height() * 2 + style.padding.y / 2)
end
function PluginSummary:draw()
  if not self:is_visible() then return false end
  local plugin, font = self.plugin, style.font
  local x, y, gap = self.position.x, self.position.y, style.padding.x
  local version = tostring(plugin.status == "core" and VERSION or plugin.version_display or plugin.version or "")
  local version_width = math.min(font:get_width(version), self.size.x * 0.4)
  local color = status_color(plugin.status)
  renderer.draw_text(font, fit_text(font, display_name(plugin), self.size.x - version_width - gap),
    x, y, plugin.status == "upgradable" and color or style.text)
  local right = fit_text(font, version, version_width)
  renderer.draw_text(font, right, x + self.size.x - font:get_width(right), y, color)
  local status = tostring(plugin.status or "")
  local status_width = math.min(font:get_width(status), self.size.x * 0.4)
  local tags = table.concat(plugin.tags or {}, ", ")
  local metadata = (plugin.type or "plugin") .. (tags ~= "" and ("   " .. tags) or "")
  local bottom = y + font:get_height() + style.padding.y / 2
  renderer.draw_text(font, fit_text(font, metadata, self.size.x - status_width - gap), x, bottom, style.dim)
  right = fit_text(font, status, status_width)
  renderer.draw_text(font, right, x + self.size.x - font:get_width(right), bottom, color)
  return true
end

local DetailsBody = Widget:extend()
function DetailsBody:new(parent)
  DetailsBody.super.new(self, parent)
  self.border.width, self.scrollable = 0, true
  self.lines = {}
end
function DetailsBody:set_plugin(plugin)
  if self.plugin ~= plugin then
    self.plugin, self.cached_width = plugin, nil
    self.scroll.y, self.scroll.to.y = 0, 0
  end
end
function DetailsBody:update_lines()
  if self.cached_width == self.size.x and self.cached_scale == SCALE
    and self.cached_text == style.text and self.cached_dim == style.dim then return end
  self.cached_width, self.cached_scale = self.size.x, SCALE
  self.cached_text, self.cached_dim = style.text, style.dim
  self.lines = {}
  local plugin = self.plugin
  if not plugin then return end
  local function add(text, color)
    for _, line in ipairs(wrap_text(style.font, text, self.size.x - style.padding.x * 2)) do
      self.lines[#self.lines + 1] = { text = line, color = color or style.text }
    end
  end
  add(plugin.description or "No description available.")
  add("")
  add("Type: " .. (plugin.type or "plugin") .. "    Status: " .. (plugin.status or "unknown"), status_color(plugin.status))
  add("Version: " .. tostring(plugin.status == "core" and VERSION or plugin.version_display or plugin.version or "unknown"))
  if plugin.available_version then add("Available: " .. plugin.available_version) end
  add("Author: " .. (plugin.author or "unknown"), style.dim)
  if #(plugin.tags or {}) > 0 then add("Tags: " .. table.concat(plugin.tags, ", "), style.dim) end
  local dependencies = {}
  for id, options in pairs(plugin.dependencies or {}) do
    dependencies[#dependencies + 1] = id .. (type(options) == "table" and options.version and (" " .. options.version) or "")
  end
  table.sort(dependencies)
  if #dependencies > 0 then add("Dependencies: " .. table.concat(dependencies, ", "), style.dim) end
  if plugin.repository or plugin.remote then add("Repository: " .. (plugin.remote or plugin.repository), style.dim) end
  if plugin.path then add("Path: " .. plugin.path, style.dim) end
end
function DetailsBody:update()
  self:update_lines()
  return DetailsBody.super.update(self)
end
function DetailsBody:get_scrollable_size()
  return math.max(self.size.y, #self.lines * (style.font:get_height() + style.padding.y / 2) + style.padding.y)
end
function DetailsBody:get_h_scrollable_size() return self.size.x end
function DetailsBody:draw()
  if not DetailsBody.super.draw(self) then return false end
  local x, y = self:get_content_offset()
  local height = style.font:get_height() + style.padding.y / 2
  core.push_clip_rect(self.position.x, self.position.y, self.size.x, self.size.y)
  for i, line in ipairs(self.lines) do
    local top = y + (i - 1) * height
    if top + height >= self.position.y and top < self.position.y + self.size.y then
      renderer.draw_text(style.font, line.text, x + style.padding.x / 2, top, line.color)
    end
  end
  core.pop_clip_rect()
  self:draw_scrollbar()
  return true
end

local function select_option(box, value)
  for i = 2, #box.list.rows do
    if box.list:get_row_data(i) == value then box:set_selected(i - 1); return end
  end
  box:set_selected(1)
end

function PluginView:new(manager, state)
  PluginView.super.new(self, nil, false)
  self.border.width, self.scrollable = 0, false
  self.background_color = style.background
  self.plugin_manager = manager or require "plugins.plugin_manager"
  self.sort = state and state.sort and common.merge({}, state.sort) or { column = 1, asc = true }
  self.sort.column = common.clamp(self.sort.column or 1, 1, #sort_fields)
  self.filter_text = state and state.filter_text or nil
  self.category = state and state.category or "all"
  self.status_filter = state and state.status_filter or "all"
  self.details_ratio = common.clamp(state and state.details_ratio or 0.25, 0.1, 0.5)
  self.checked = state and common.merge({}, state.checked) or {}
  self.pending_state = state
  self.show_incompatible_plugins = false
  self.rows, self.sorted_plugins, self.catalog = {}, {}, {}
  self.initialized = false
  self.progress_callback = function(progress) self.progress = progress; core.redraw = true end
  self:build_controls()
  self:show()
  self:refresh()
end

function PluginView:get_name() return "Plugin Manager" end
function PluginView:get_state()
  local focused = self.selected_plugin
  return {
    filter_text = self.filter_text, category = self.category, status_filter = self.status_filter,
    sort = common.merge({}, self.sort), checked = common.merge({}, self.checked),
    focused_key = focused and row_key(focused), focused_id = focused and focused.id,
    details_ratio = self.details_ratio,
    scroll = { x = self.list.scroll.x, y = self.list.scroll.y,
      to = { x = self.list.scroll.to.x, y = self.list.scroll.to.y } }
  }
end
function PluginView.from_state(state) return PluginView(nil, state or {}) end

function PluginView:build_controls()
  local this = self
  self.filter_bar = Widget(self)
  self.filter_bar.border.width = 0
  self.search = TextBox(self.filter_bar, self.filter_text or "", "Search plugins...")
  self.search:set_tooltip("Search by name, ID, or tag")
  function self.search:on_change(text)
    if not this.updating_controls then this:set_filter(text) end
  end
  self.clear_search = ActionButton(self.filter_bar, "", "X", function() this:set_filter("") end)
  self.clear_search:set_tooltip("Clear search")
  self.category_box = CatalogSelectBox(self.filter_bar, "Category")
  self.category_box:set_tooltip("Category")
  function self.category_box:on_change()
    if this.updating_controls then return end
    this.category = self:get_selected_data() or "all"
    this:apply_filters()
  end
  self.status_box = CatalogSelectBox(self.filter_bar, "Status")
  self.status_box:set_tooltip("Status")
  for _, option in ipairs({ { "All statuses", "all" }, { "Available", "available" },
    { "Installed", "installed" }, { "Updates", "upgradable" } }) do
    self.status_box:add_option(option[1], option[2])
  end
  function self.status_box:on_change()
    if this.updating_controls then return end
    this.status_filter = self:get_selected_data() or "all"
    this:apply_filters()
  end
  self.sort_box = CatalogSelectBox(self.filter_bar, "Sort")
  self.sort_box:set_tooltip("Sort plugins")
  for i, field in ipairs(sort_fields) do
    local name = field:sub(1, 1):upper() .. field:sub(2)
    self.sort_box:add_option(name .. ", ascending", i .. ":asc")
    self.sort_box:add_option(name .. ", descending", i .. ":desc")
  end
  function self.sort_box:on_change()
    if this.updating_controls then return end
    local column, direction = (self:get_selected_data() or "1:asc"):match("(%d+):(%w+)")
    this.sort = { column = tonumber(column), asc = direction == "asc" }
    this:rebuild()
  end
  self.updating_controls = true
  select_option(self.status_box, self.status_filter)
  this.status_filter = self.status_box:get_selected_data() or "all"
  select_option(self.sort_box, self.sort.column .. (self.sort.asc and ":asc" or ":desc"))
  self.updating_controls = false
  self.filter_controls = { self.search, self.clear_search, self.category_box, self.status_box, self.sort_box }

  self.action_bar = Widget(self)
  self.action_bar.border.width = 0
  self.select_visible = CheckBox(self.action_bar, "")
  self.select_visible:set_tooltip("Select or clear visible plugins")
  function self.select_visible:on_change(checked)
    if not this.updating_controls then this:check_visible(checked) end
  end
  self.selection_label = FittedLabel(self.action_bar, "")
  self.clear_selection = ActionButton(self.action_bar, "", "X", function()
    this.checked = {}; this:update_controls()
  end)
  self.clear_selection:set_tooltip("Clear selected plugins")
  self.batch_buttons = {}
  self.action_controls = { self.select_visible, self.selection_label, self.clear_selection }
  for _, action in ipairs({ "install", "upgrade", "uninstall" }) do
    local name = action:sub(1, 1):upper() .. action:sub(2)
    local button = ActionButton(self.action_bar, name .. " (0)", "p", function()
      this:apply_action(action, this:get_checked_plugins(action))
    end, name .. " (999)")
    button:set_tooltip(name .. " selected plugins")
    self.batch_buttons[action] = button
    self.action_controls[#self.action_controls + 1] = button
  end
  self.refresh_button = ActionButton(self.action_bar, "Refresh Listing", nil, function() this:refresh() end)
  self.updates_button = ActionButton(self.action_bar, "Check for Updates", "L", function() this:check_for_updates() end)
  self.upgrade_all_button = ActionButton(self.action_bar, "Upgrade All", "p", function() this:upgrade() end)
  for _, button in ipairs({ self.refresh_button, self.updates_button, self.upgrade_all_button }) do
    button:set_tooltip(button.label)
    self.action_controls[#self.action_controls + 1] = button
  end

  self.list = WidgetList(self)
  self.list.border.width = 0
  self.divider = Widget(self)
  self.divider.border.width, self.divider.render_background = 0, false
  function self.divider:draw()
    renderer.draw_rect(self.position.x, self.position.y + self.size.y / 2,
      self.size.x, math.max(1, SCALE), style.divider or style.dim)
  end
  self.details_header = Widget(self)
  self.details_header.border.width = 0
  self.details_title = FittedLabel(self.details_header, "No plugin selected")
  self.details_buttons, self.details_controls = {}, {}
  for _, action in ipairs({ "install", "upgrade", "uninstall", "source", "readme" }) do
    local labels = { install = "Install", upgrade = "Upgrade", uninstall = "Uninstall", source = "Source", readme = "README" }
    local button = ActionButton(self.details_header, labels[action], action == "source" and "f" or "p", function()
      local plugin = this.selected_plugin
      if action == "source" or action == "readme" then this:open_file(plugin, action)
      else this:apply_action(action, { plugin }) end
    end)
    button:set_tooltip(labels[action])
    self.details_buttons[action] = button
    self.details_controls[#self.details_controls + 1] = button
  end
  self.details_body = DetailsBody(self)
  for _, pane in ipairs({ self.filter_bar, self.action_bar, self.list, self.details_header }) do
    pane.on_mouse_released = release_mouse
  end
  for _, box in ipairs({ self.category_box, self.status_box, self.sort_box }) do
    box.list_container.plugin_view, box.list.plugin_view = self, self
    box.list_container.owner_selectbox, box.list.owner_selectbox = box, box
    local click = box.on_click
    function box:on_click(...)
      click(self, ...)
      this:swap_active_child(self)
    end
  end
end

function PluginView:get_plugins()
  return (self.show_incompatible_plugins and self.plugin_manager.addons or self.plugin_manager.valid_addons) or {}
end
function PluginView:get_sorted_plugins() return self.sorted_plugins end

function PluginView:build_categories()
  local box, tags = self.category_box, {}
  self.updating_controls = true
  box.list:clear()
  box:set_label("Category")
  for _, option in ipairs({ { "All categories", "all" }, { "Plugins", "type:plugin" },
    { "Colors", "type:color" }, { "Fonts", "type:font" }, { "Languages", "language" } }) do
    box:add_option(option[1], option[2])
  end
  if config.plugins.plugin_manager.show_libraries then box:add_option("Libraries", "type:library") end
  for _, plugin in ipairs(self.catalog) do
    for _, tag in ipairs(plugin.tags or {}) do
      if tag ~= "language" then tags[tag] = true end
    end
  end
  local ordered = {}
  for tag in pairs(tags) do ordered[#ordered + 1] = tag end
  table.sort(ordered)
  for _, tag in ipairs(ordered) do box:add_option("Tag: " .. tag, "tag:" .. tag) end
  select_option(box, self.category)
  self.category = box:get_selected_data() or "all"
  self.updating_controls = false
end

function PluginView:matches(plugin)
  local tags = table.concat(plugin.tags or {}, ", ")
  local query = string.ulower(self.filter_text or "")
  if query ~= "" then
    local text = string.ulower(display_name(plugin) .. " " .. plugin.id .. " " .. tags)
    if not text:ufind(query, 1, true) then return false end
  end
  if self.status_filter == "installed" and (plugin.status == "available" or plugin.status == "incompatible") then return false end
  if self.status_filter ~= "all" and self.status_filter ~= "installed" and plugin.status ~= self.status_filter then return false end
  if self.category:sub(1, 5) == "type:" and plugin.type ~= self.category:sub(6) then return false end
  if self.category == "language" then
    if not plugin.id:match("^language_") and not index_of(plugin.tags or {}, "language") then return false end
  elseif self.category:sub(1, 4) == "tag:" then
    if not index_of(plugin.tags or {}, self.category:sub(5)) then return false end
  end
  return true
end

function PluginView:set_filter(text)
  self.filter_text = text ~= "" and text or nil
  if self.search:get_text() ~= (self.filter_text or "") then
    self.updating_controls = true
    self.search:set_text(self.filter_text or "")
    self.updating_controls = false
  end
  self:apply_filters()
end

function PluginView:apply_filters()
  self.sorted_plugins = {}
  for _, plugin in ipairs(self.catalog) do
    if self:matches(plugin) then self.sorted_plugins[#self.sorted_plugins + 1] = plugin end
  end
  self.list:filter(function(plugin) return self:matches(plugin) end)
  self.selected_plugin_idx = nil
  for i, plugin in ipairs(self.sorted_plugins) do
    if plugin == self.selected_plugin then self.selected_plugin_idx = i; break end
  end
  if self.selected_plugin and not self.selected_plugin_idx then self.selected_plugin = nil end
  self:update_controls()
end

function PluginView:build_row(row, plugin)
  local this = self
  local checkbox = CheckBox(row, "")
  checkbox.visible, checkbox.clickable = selectable(plugin), selectable(plugin)
  row.checkbox = checkbox
  row.on_mouse_released = release_mouse
  function checkbox:on_change(checked)
    if this.loading or this.confirming or this.updating_controls then return end
    this:set_checked(plugin, checked)
    this:focus_plugin(plugin)
  end
  local summary = PluginSummary(row, plugin)
  row:set_child_properties(summary, { stretch = 1 })
  local pressed = row.on_mouse_pressed
  function row:on_mouse_pressed(button, x, y, clicks)
    if button == "left" or button == "right" then this:focus_plugin(plugin) end
    if button == "left" and clicks == 2 and checkbox.visible and checkbox.clickable
      and not checkbox:mouse_on_top(x, y) then
      this:set_checked(plugin, this.checked[plugin.id] ~= row_key(plugin))
    end
    return pressed(self, button, x, y, clicks)
  end
  local enter, leave = row.on_mouse_enter, row.on_mouse_leave
  function row:on_mouse_enter(...)
    enter(self, ...)
    this.hovered_plugin = plugin
  end
  function row:on_mouse_leave(...)
    leave(self, ...)
    if this.hovered_plugin == plugin then this.hovered_plugin = nil end
  end
  local moved = row.on_mouse_moved
  function row:on_mouse_moved(x, y, dx, dy)
    self.hovered = self:mouse_on_top(x, y) and this.list:mouse_on_top(x, y)
    self.mouse_is_hovering = self.hovered
    if self.hovered then this.hovered_plugin = plugin
    elseif this.hovered_plugin == plugin then this.hovered_plugin = nil end
    return moved(self, x, y, dx, dy)
  end
  function row:draw()
    if not self:is_visible() then return false end
    if this.selected_plugin == plugin or self.hovered then
      renderer.draw_rect(self.parent.position.x, self.position.y,
        self.parent.size.x, self.size.y, style.line_highlight)
    end
    if this.selected_plugin == plugin then
      renderer.draw_rect(self.position.x, self.position.y, math.max(2, 2 * SCALE), self.size.y, style.accent)
    end
    return Widget.draw(self)
  end
end

function PluginView:rebuild()
  local focused = self.selected_plugin
  local focused_key = focused and row_key(focused)
  local state = self.pending_state
  local scroll = state and state.scroll or {
    x = self.list.scroll.x, y = self.list.scroll.y,
    to = { x = self.list.scroll.to.x, y = self.list.scroll.to.y }
  }
  self.catalog, self.rows = {}, {}
  for _, plugin in ipairs(self:get_plugins()) do self.catalog[#self.catalog + 1] = plugin end
  local field = sort_fields[self.sort.column]
  local function sort_value(plugin)
    if field == "name" then return display_name(plugin) end
    if field == "tags" then return table.concat(plugin.tags or {}, ", ") end
    return tostring(plugin[field] or "")
  end
  table.sort(self.catalog, function(a, b)
    local av, bv = string.ulower(sort_value(a)), string.ulower(sort_value(b))
    if av == bv then return row_key(a) < row_key(b) end
    if self.sort.asc then return av < bv end
    return av > bv
  end)
  self.list:clear()
  local existing = {}
  self.selected_plugin = nil
  for _, plugin in ipairs(self.catalog) do
    local key = row_key(plugin)
    existing[key] = plugin
    self.rows[key] = self.list:add_item(plugin, function(row) self:build_row(row, plugin) end)
    if key == (state and state.focused_key or focused_key) then self.selected_plugin = plugin end
  end
  for id, key in pairs(self.checked) do
    if not existing[key] or not selectable(existing[key]) then self.checked[id] = nil end
  end
  self:build_categories()
  self:apply_filters()
  if state then
    if not self.selected_plugin and state.focused_id then
      for _, plugin in ipairs(self.sorted_plugins) do
        if plugin.id == state.focused_id then self:focus_plugin(plugin); break end
      end
    elseif not self.selected_plugin and state.selected_plugin_idx then
      self:focus_plugin(self.sorted_plugins[state.selected_plugin_idx])
    end
    self.pending_state = nil
  elseif not self.selected_plugin and focused then
    for _, plugin in ipairs(self.sorted_plugins) do
      if plugin.id == focused.id then self:focus_plugin(plugin); break end
    end
  end
  self.list.scroll.x, self.list.scroll.y = scroll.x or 0, scroll.y or 0
  self.list.scroll.to.x = scroll.to and scroll.to.x or self.list.scroll.x
  self.list.scroll.to.y = scroll.to and scroll.to.y or self.list.scroll.y
  self.hovered_plugin = nil
  self:update_controls()
end

function PluginView:focus_plugin(plugin)
  self.selected_plugin, self.selected_plugin_idx = plugin, nil
  for i, entry in ipairs(self.sorted_plugins) do
    if entry == plugin then self.selected_plugin_idx = i; break end
  end
  self:update_controls()
end

function PluginView:set_checked(plugin, checked)
  if self.loading or self.confirming or not selectable(plugin) then return end
  self.checked[plugin.id] = checked and row_key(plugin) or nil
  self:update_controls()
end

function PluginView:check_visible(checked)
  if self.loading or self.confirming then return end
  local candidates = {}
  for _, plugin in ipairs(self.sorted_plugins) do
    if selectable(plugin) and (not candidates[plugin.id] or self.checked[plugin.id] == row_key(plugin)) then
      candidates[plugin.id] = plugin
    end
  end
  for id, plugin in pairs(candidates) do
    if checked then self.checked[id] = row_key(plugin)
    elseif self.checked[id] == row_key(plugin) then self.checked[id] = nil end
  end
  self:update_controls()
end

function PluginView:get_checked_plugins(action)
  local plugins, seen = {}, {}
  for _, plugin in ipairs(self.catalog) do
    if self.checked[plugin.id] == row_key(plugin) and not seen[plugin.id] and (not action or eligible(plugin, action)) then
      plugins[#plugins + 1], seen[plugin.id] = plugin, true
    end
  end
  return plugins
end

function PluginView:update_controls()
  if not self.list then return end
  self.updating_controls = true
  local visible, selected_visible, selected_total = 0, 0, 0
  local visible_keys, visible_ids = {}, {}
  for _, plugin in ipairs(self.sorted_plugins) do
    if selectable(plugin) and not visible_ids[plugin.id] then
      visible_ids[plugin.id] = true
      visible = visible + 1
    end
    visible_keys[row_key(plugin)] = true
  end
  for id, key in pairs(self.checked) do
    selected_total = selected_total + 1
    if visible_ids[id] and visible_keys[key] then selected_visible = selected_visible + 1 end
  end
  local hidden = 0
  for _, key in pairs(self.checked) do if not visible_keys[key] then hidden = hidden + 1 end end
  self.select_visible:set_checked(visible > 0 and selected_visible == visible)
  self.select_visible.mixed = selected_visible > 0 and selected_visible < visible
  self.select_visible.clickable = visible > 0 and not self.loading and not self.confirming
  self.clear_selection.enabled = selected_total > 0 and not self.loading and not self.confirming
  self.selection_label:set_label(string.format("%d of %d shown | %d selected%s",
    #self.sorted_plugins, #self.catalog, selected_total, hidden > 0 and (" (" .. hidden .. " hidden)") or ""))
  self.selection_label:set_tooltip(self.selection_label.label)
  for _, plugin in ipairs(self.catalog) do
    local row = self.rows[row_key(plugin)]
    if row then
      row.checkbox:set_checked(self.checked[plugin.id] == row_key(plugin))
      row.checkbox.clickable = selectable(plugin) and not self.loading and not self.confirming
    end
  end
  for action, button in pairs(self.batch_buttons) do
    local count = #self:get_checked_plugins(action)
    local label = action:sub(1, 1):upper() .. action:sub(2)
    button:set_label(label .. " (" .. count .. ")")
    button.enabled = count > 0 and not self.loading and not self.confirming
  end
  for _, button in ipairs({ self.refresh_button, self.updates_button, self.upgrade_all_button }) do
    button.enabled = not self.loading and not self.confirming
  end
  local plugin = self.selected_plugin
  self.details_title:set_label(plugin and display_name(plugin) or "No plugin selected")
  self.details_body:set_plugin(plugin)
  for action, button in pairs(self.details_buttons) do
    if action == "source" or action == "readme" then button.visible = plugin ~= nil and plugin.type ~= "font"
    else button.visible = eligible(plugin, action) end
    button.enabled = button.visible and not self.loading and not self.confirming
  end
  self.updating_controls = false
  core.redraw = true
end

local function flow(controls, width, gap, minimums)
  local x, y, row_height, row = 0, 0, 0, {}
  local function align_row()
    for _, child in ipairs(row) do
      child:set_position(child.position.rx, y + (row_height - child:get_height()) / 2)
    end
    row = {}
  end
  for _, child in ipairs(controls) do
    if child.visible then
      child:update_size_position()
      local w = math.min(width, minimums and minimums[child] or child:get_width())
      if x > 0 and x + w > width then
        align_row()
        x, y, row_height = 0, y + row_height + gap, 0
      end
      child:set_size(w)
      child:set_position(x, y)
      x, row_height = x + w + gap, math.max(row_height, child:get_height())
      row[#row + 1] = child
    end
  end
  align_row()
  return y + row_height
end

function PluginView:layout()
  local px, py, gap = style.padding.x, style.padding.y, style.padding.x / 2
  local width = math.max(0, self.size.x - px * 2)
  local control_height = style.font:get_height() + py * 2
  local fixed = self.clear_search:get_width() + 540 * SCALE + gap * 4
  local search_width = math.max(math.min(width, 220 * SCALE), width - fixed)
  self.filter_bar:set_position(px, py)
  self.filter_bar:set_size(width, self.size.y)
  local filter_height = flow(self.filter_controls, width, gap, {
    [self.search] = search_width, [self.category_box] = 180 * SCALE,
    [self.status_box] = 160 * SCALE, [self.sort_box] = 200 * SCALE
  })
  self.filter_bar:set_size(nil, filter_height)
  self.action_bar:set_position(px, py + filter_height + gap)
  self.action_bar:set_size(width, self.size.y)
  local action_height = flow(self.action_controls, width, gap, { [self.selection_label] = 220 * SCALE })
  self.action_bar:set_size(nil, action_height)
  local top = py + filter_height + action_height + gap * 2
  local strip = (self.loading or self.error_message) and (style.font:get_height() + py) or 0
  local remaining = math.max(0, self.size.y - top - strip - py)
  local details_height = math.min(remaining * 0.5, math.max(control_height, remaining * self.details_ratio))
  local list_height = math.max(0, remaining - details_height - gap)
  self.list:set_position(px, top)
  self.list:set_size(width, list_height)
  self.divider:set_position(px, top + list_height)
  self.divider:set_size(width, gap)
  local details_top = top + list_height + gap
  self.details_header:set_position(px, details_top)
  self.details_header:set_size(width, details_height)
  local buttons_height = flow(self.details_controls, width, gap)
  local buttons_width = 0
  for _, button in ipairs(self.details_controls) do
    if button.visible then buttons_width = buttons_width + button:get_width() + gap end
  end
  local title_width = width - buttons_width - gap
  local header_height
  if title_width >= 160 * SCALE then
    self.details_title:set_position(0, (control_height - style.font:get_height()) / 2)
    self.details_title:set_size(title_width)
    for _, button in ipairs(self.details_controls) do
      if button.visible then button:set_position(button.position.rx + title_width + gap, button.position.ry) end
    end
    header_height = control_height
  else
    self.details_title:set_position(0, 0)
    self.details_title:set_size(width)
    for _, button in ipairs(self.details_controls) do
      if button.visible then button:set_position(button.position.rx, button.position.ry + control_height) end
    end
    header_height = control_height + buttons_height
  end
  header_height = math.min(header_height, details_height)
  self.details_header:set_size(nil, header_height)
  self.details_body:set_position(px, details_top + header_height)
  self.details_body:set_size(width, math.max(0, details_height - header_height))
  self.resize_available = remaining
end

function PluginView:update()
  self:layout()
  if self.loading and (not self.progress or not self.progress.percent or self.progress.percent == 0) then core.redraw = true end
  return PluginView.super.update(self)
end

function PluginView:on_mouse_pressed(button, x, y, clicks)
  if button == "left" and self.divider:mouse_on_top(x, y) then
    self.resizing_details = true
    return true
  end
  return PluginView.super.on_mouse_pressed(self, button, x, y, clicks)
end
function PluginView:on_mouse_moved(x, y, dx, dy)
  if self.resizing_details then
    self.cursor = "sizev"
    local bottom = self.divider.position.y + self.divider.size.y + self.details_header.size.y + self.details_body.size.y
    self.details_ratio = common.clamp((bottom - y) / math.max(1, self.resize_available), 0.1, 0.5)
    core.redraw = true
    return true
  end
  local result = PluginView.super.on_mouse_moved(self, x, y, dx, dy)
  self.cursor = self.divider:mouse_on_top(x, y) and "sizev" or "arrow"
  return result
end
function PluginView:on_mouse_released(...)
  if self.resizing_details then self.resizing_details = false; return true end
  return release_mouse(self, ...)
end

function PluginView:draw_progress_strip()
  local height = style.font:get_height() + style.padding.y
  local y = self.position.y + self.size.y - height
  renderer.draw_rect(self.position.x, y, self.size.x, height, style.background2)
  local progress = self.progress or {}
  local percent = tonumber(progress.percent)
  if self.loading then
    if percent and percent > 0 then
      renderer.draw_rect(self.position.x, y, self.size.x * common.clamp(percent, 0, 1), math.max(2, SCALE), style.accent)
    else
      local width = self.size.x / 5
      local x = self.position.x + (self.size.x - width) * ((math.sin(system.get_time() * 3) + 1) / 2)
      renderer.draw_rect(x, y, width, math.max(2, SCALE), style.accent)
    end
  end
  renderer.draw_text(style.font, fit_text(style.font, self.error_message or progress.label or "Working...",
    self.size.x - style.padding.x * 2), self.position.x + style.padding.x,
    y + style.padding.y / 2, self.error_message and style.warn or style.text)
end

function PluginView:draw()
  self.background_color = style.background
  if not PluginView.super.draw(self) then return false end
  if not self.initialized or #self.sorted_plugins == 0 then
    local message = self.loading and not self.initialized and "Loading plugins..." or "No matching plugins"
    common.draw_text(style.font, style.dim, message, "center", self.list.position.x,
      self.list.position.y, self.list.size.x, self.list.size.y)
  end
  if self.select_visible.mixed then
    local x, y, w, h = self.select_visible:get_box_rect()
    renderer.draw_rect(x + w / 4, y + h / 2, w / 2, math.max(2, SCALE), style.accent)
  end
  if self.loading or self.error_message then self:draw_progress_strip() end
  return true
end

function PluginView:try_close(do_close)
  self:swap_active_child()
  for _, box in ipairs({ self.category_box, self.status_box, self.sort_box }) do box.list_container:hide() end
  PluginView.super.try_close(self, do_close)
  self:hide()
  self:destroy_childs()
end

function PluginView:refresh(no_refetch, on_complete, keep_error)
  if self.loading or self.confirming then return self.plugin_manager.promise.new():resolve(false) end
  if no_refetch then
    self:rebuild()
    if on_complete then on_complete() end
    return self.plugin_manager.promise.new():resolve(true)
  end
  self.loading = true
  if not keep_error then self.error_message = nil end
  self.progress = { label = "Refreshing plugin listing..." }
  self:update_controls()
  return self.plugin_manager:refresh({ progress = self.progress_callback }):done(function()
    self.loading, self.progress, self.initialized = false, nil, true
    self:rebuild()
    if on_complete then on_complete() end
  end):fail(function(err)
    self.loading, self.progress = false, nil
    self.error_message = tostring(err or "Unable to refresh plugins")
    self:update_controls()
  end)
end

function PluginView:operate(method, plugins)
  if self.loading or self.confirming then return self.plugin_manager.promise.new():resolve(false) end
  self.loading, self.error_message, self.progress = true, nil, nil
  self:update_controls()
  local options = { progress = self.progress_callback }
  local promise
  if plugins then promise = self.plugin_manager[method](self.plugin_manager, plugins, options)
  else promise = self.plugin_manager[method](self.plugin_manager, options) end
  return promise:done(function()
    self.loading, self.progress = false, nil
    if method == "install_many" or method == "upgrade_many" or method == "uninstall_many" then
      for _, plugin in ipairs(plugins) do self.checked[plugin.id] = nil end
    elseif method == "reinstall" then self.checked[plugins.id] = nil
    elseif method == "upgrade" then self.checked = {} end
    self:rebuild()
  end):fail(function(err)
    self.loading, self.progress = false, nil
    self.error_message = tostring(err or "Plugin operation failed")
    self:update_controls()
    self:refresh(false, nil, true)
  end)
end

function PluginView:apply_action(action, plugins)
  local targets = {}
  for _, plugin in ipairs(plugins or {}) do if eligible(plugin, action) then targets[#targets + 1] = plugin end end
  if #targets == 0 or self.loading or self.confirming then return self.plugin_manager.promise.new():resolve(false) end
  if action ~= "uninstall" then return self:operate(action .. "_many", targets) end
  local promise = self.plugin_manager.promise.new()
  local names = {}
  for _, plugin in ipairs(targets) do names[#names + 1] = display_name(plugin) end
  self.confirming = true
  self:update_controls()
  core.nag_view:show("Uninstall plugins?", table.concat(names, ", ")
    .. "\n\nDependent addons and unused user dependencies may also be removed. Bundled files will not be removed.",
    { { text = "Uninstall" }, { text = "Cancel", default_yes = true } }, function(option)
      self.confirming = false
      self:update_controls()
      if option.text == "Uninstall" then self:operate("uninstall_many", targets):forward(promise)
      else promise:resolve(false) end
    end)
  return promise
end

function PluginView:install(plugin) return self:apply_action("install", { plugin }) end
function PluginView:upgrade_plugin(plugin) return self:apply_action("upgrade", { plugin }) end
function PluginView:uninstall(plugin) return self:apply_action("uninstall", { plugin }) end
function PluginView:upgrade() return self:operate("upgrade") end
function PluginView:check_for_updates() return self:operate("check_for_updates") end
function PluginView:unstub(plugin) return self:operate("unstub", plugin) end
function PluginView:reinstall(plugin) return self:operate("reinstall", plugin) end

function PluginView:open_file(plugin, kind)
  if not plugin or plugin.type == "font" then return end
  return self:unstub(plugin):done(function(addon)
    if not addon or not addon.path then return end
    local paths = {}
    if kind == "source" then paths = { addon.path, addon.path .. PATHSEP .. "init.lua" }
    else
      local directories = { addon.path }
      if addon.repo_path then
        directories[#directories + 1] = addon.repo_path
        local parent = common.dirname(addon.repo_path)
        if common.basename(addon.repo_path) == addon.id and common.basename(parent) == "plugins" then
          directories[#directories + 1] = common.dirname(parent)
        end
      end
      for _, directory in ipairs(directories) do
        paths[#paths + 1] = directory .. PATHSEP .. "README.md"
        paths[#paths + 1] = directory .. PATHSEP .. "readme.md"
      end
    end
    for _, path in ipairs(paths) do
      local stat = system.get_file_info(path)
      if stat and stat.type == "file" then core.root_view:open_doc(core.open_doc(path)); return end
    end
    core.error("Can't find %s for %s.", kind == "source" and "source" or "README", addon.id)
  end)
end

function PluginView.active()
  local view = core.active_view
  while view do
    if view:is(PluginView) then return view end
    if view.plugin_view then return view.plugin_view end
    view = view.parent
  end
end
local function active_view()
  local view = PluginView.active()
  return view ~= nil, view
end
local function list_view()
  local view = PluginView.active()
  return view ~= nil and core.active_view ~= view.search.textview, view
end
local function row_action(action, hovered)
  return function()
    local view = PluginView.active()
    if not view or view.loading or view.confirming then return false end
    local plugin = hovered and (view.hovered_plugin or view.selected_plugin) or view.selected_plugin
    return eligible(plugin, action), view, plugin
  end
end

function PluginView:move_selection(delta)
  if #self.sorted_plugins == 0 then return end
  local index = common.clamp((self.selected_plugin_idx or 0) + delta, 1, #self.sorted_plugins)
  local plugin = self.sorted_plugins[index]
  self:focus_plugin(plugin)
  local row = self.rows[row_key(plugin)]
  self.list:relayout()
  self.list.scroll.to.y = math.max(0, row.position.ry - (self.list.size.y - row.size.y) / 2)
end
function PluginView:cycle_focus(delta)
  local controls = {}
  for _, child in ipairs(self.filter_controls) do controls[#controls + 1] = child end
  controls[#controls + 1] = self.list
  for _, child in ipairs(self.action_controls) do
    if child ~= self.selection_label and child.visible and child.clickable ~= false and child.enabled ~= false then controls[#controls + 1] = child end
  end
  for _, child in ipairs(self.details_controls) do if child.visible and child.enabled then controls[#controls + 1] = child end end
  local index = index_of(controls, self.child_active) or 0
  index = ((index - 1 + delta) % #controls) + 1
  for _, box in ipairs({ self.category_box, self.status_box, self.sort_box }) do box.list_container:hide() end
  self:swap_active_child(controls[index])
  core.redraw = true
end

command.add(active_view, {
  ["plugin-manager:filter"] = function(view) view:swap_active_child(view.search) end,
  ["plugin-manager:find"] = function(view) view:swap_active_child(view.search) end,
  ["plugin-manager:clear-filter"] = function(view)
    for _, box in ipairs({ view.category_box, view.status_box, view.sort_box }) do box.list_container:hide() end
    view:set_filter("")
  end,
  ["plugin-manager:escape"] = function(view)
    local closed = false
    for _, box in ipairs({ view.category_box, view.status_box, view.sort_box }) do
      if box.list_container.visible then box.list_container:hide(); closed = true end
    end
    if not closed then view:set_filter("") end
  end,
  ["plugin-manager:focus-next"] = function(view) view:cycle_focus(1) end,
  ["plugin-manager:focus-prev"] = function(view) view:cycle_focus(-1) end,
  ["plugin-manager:refresh-all"] = function(view) view:refresh() end,
  ["plugin-manager:upgrade-all"] = function(view) view:upgrade() end,
})
command.add(list_view, {
  ["plugin-manager:select"] = function(view) view:focus_plugin(view.hovered_plugin) end,
  ["plugin-manager:select-prev"] = function(view)
    local box = core.active_view:is(SelectBox) and core.active_view or core.active_view.owner_selectbox
    if box then box:set_selected(math.max(1, box:get_selected() - 1)) else view:move_selection(-1) end
  end,
  ["plugin-manager:select-next"] = function(view)
    local box = core.active_view:is(SelectBox) and core.active_view or core.active_view.owner_selectbox
    if box then box:set_selected(math.min(#box.list.rows - 1, box:get_selected() + 1)) else view:move_selection(1) end
  end,
  ["plugin-manager:scroll-page-up"] = function(view) view.list.scroll.to.y = math.max(0, view.list.scroll.y - view.list.size.y) end,
  ["plugin-manager:scroll-page-down"] = function(view) view.list.scroll.to.y = math.min(view.list:get_scrollable_size(), view.list.scroll.y + view.list.size.y) end,
  ["plugin-manager:scroll-page-top"] = function(view) view.list.scroll.to.y = 0 end,
  ["plugin-manager:scroll-page-bottom"] = function(view) view.list.scroll.to.y = view.list:get_scrollable_size() end,
  ["plugin-manager:toggle-selected"] = function(view)
    local control = view.child_active
    if control and (control:is(ActionButton) or control:is(CheckBox) or control:is(SelectBox)) then
      control:on_click("left")
      return
    end
    local plugin = view.selected_plugin
    if plugin then view:set_checked(plugin, view.checked[plugin.id] ~= row_key(plugin)) end
  end,
  ["plugin-manager:activate-control"] = function(view)
    local control = view.child_active
    if control and control:is(ActionButton) then control:on_click("left")
    elseif control and control:is(SelectBox) then control:on_click("left")
    elseif control and control:is(CheckBox) then control:on_click("left")
    else view:focus_plugin(view.selected_plugin) end
  end,
})
for _, action in ipairs({ "install", "upgrade", "uninstall" }) do
  command.add(function()
    local view = PluginView.active()
    if not view or view.loading or view.confirming then return false end
    local plugins = view:get_checked_plugins(action)
    if #plugins == 0 and next(view.checked) == nil and eligible(view.selected_plugin, action) then plugins = { view.selected_plugin } end
    return #plugins > 0, view, plugins
  end, { ["plugin-manager:" .. action .. "-selected"] = function(view, plugins) view:apply_action(action, plugins) end })
  command.add(row_action(action, true), {
    ["plugin-manager:" .. action .. "-hovered"] = function(view, plugin) view:apply_action(action, { plugin }) end
  })
end
command.add(function()
  local view = PluginView.active()
  local plugin = view and (view.hovered_plugin or view.selected_plugin)
  return view and not view.loading and not view.confirming and plugin and plugin.type ~= "font", view, plugin
end, {
  ["plugin-manager:view-source-hovered"] = function(view, plugin) view:open_file(plugin, "source") end,
  ["plugin-manager:view-readme-hovered"] = function(view, plugin) view:open_file(plugin, "readme") end,
})
command.add(row_action("uninstall", true), {
  ["plugin-manager:reinstall-hovered"] = function(view, plugin) view:reinstall(plugin) end
})

keymap.add {
  ["ctrl+f"] = "plugin-manager:filter", ["ctrl+r"] = "plugin-manager:refresh-all",
  ["ctrl+u"] = "plugin-manager:upgrade-all", ["escape"] = "plugin-manager:escape",
  ["tab"] = "plugin-manager:focus-next", ["shift+tab"] = "plugin-manager:focus-prev",
  ["up"] = "plugin-manager:select-prev", ["down"] = "plugin-manager:select-next",
  ["pageup"] = "plugin-manager:scroll-page-up", ["pagedown"] = "plugin-manager:scroll-page-down",
  ["home"] = "plugin-manager:scroll-page-top", ["end"] = "plugin-manager:scroll-page-bottom",
  ["space"] = "plugin-manager:toggle-selected", ["return"] = "plugin-manager:activate-control",
}

-- Older editor versions still require manual context-menu routing.
if not View.set_floating then
  local root_update, root_draw = RootView.update, RootView.draw
  function RootView:update(...) root_update(self, ...); PluginView.menu:update() end
  function RootView:draw(...) root_draw(self, ...); PluginView.menu:draw() end
  local root_moved = RootView.on_mouse_moved
  function RootView:on_mouse_moved(...)
    if PluginView.menu:on_mouse_moved(...) then return end
    return root_moved(self, ...)
  end
end
local root_pressed = RootView.on_view_mouse_pressed
function RootView.on_view_mouse_pressed(...)
  return PluginView.menu:on_mouse_pressed(...) or root_pressed(...)
end
PluginView.menu:register(active_view, {
  { text = "Install", command = "plugin-manager:install-hovered" },
  { text = "Upgrade", command = "plugin-manager:upgrade-hovered" },
  { text = "Uninstall", command = "plugin-manager:uninstall-hovered" },
  { text = "View Source", command = "plugin-manager:view-source-hovered" },
  { text = "View README", command = "plugin-manager:view-readme-hovered" },
  ContextMenu.DIVIDER,
  { text = "Refresh Listing", command = "plugin-manager:refresh-all" },
  { text = "Check for Updates", command = "plugin-manager:check-for-updates" },
  { text = "Upgrade All", command = "plugin-manager:upgrade-all" },
})

return PluginView
