local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local style = require "core.style"
local json = require "core.json"
local manager = require "plugins.plugin_manager"
local test = require "core.test"

local originals, threads, responses, errors, commands

local function mock_process(response)
  local stdout, stderr = response.stdout or "", response.stderr or ""
  return {
    read_stdout = function(_, size)
      if #stdout == 0 then return nil end
      local chunk = stdout:sub(1, math.min(size, 31))
      stdout = stdout:sub(#chunk + 1)
      return chunk
    end,
    read_stderr = function(_, size)
      if #stderr == 0 then return nil end
      local chunk = stderr:sub(1, size)
      stderr = stderr:sub(#chunk + 1)
      return chunk
    end,
    returncode = function() return response.code or 0 end
  }
end

local function run_threads()
  for _ = 1, 20 do
    local running = false
    for _, thread in ipairs(threads) do
      if coroutine.status(thread) ~= "dead" then
        local ok, err = coroutine.resume(thread)
        test.ok(ok, err)
        running = true
      end
    end
    if not running then return end
  end
  error("ppm process loop did not finish")
end

test.describe("plugin_manager processes", function()
  test.before_each(function()
    originals = {
      start = process.start,
      add_thread = core.add_thread,
      error = core.error,
      restart = config.plugins.plugin_manager.restart_on_change,
      perform = command.perform, addons = manager.addons, valid_addons = manager.valid_addons
    }
    threads, responses, errors, commands = {}, {}, {}, {}
    config.plugins.plugin_manager.restart_on_change = false
    process.start = function(argv)
      commands[#commands + 1] = argv
      return mock_process(assert(table.remove(responses, 1), "unexpected ppm command"))
    end
    core.add_thread = function(fn)
      table.insert(threads, coroutine.create(fn))
    end
    core.error = function(...)
      table.insert(errors, string.format(...))
    end
  end)

  test.after_each(function()
    process.start = originals.start
    core.add_thread = originals.add_thread
    core.error = originals.error
    config.plugins.plugin_manager.restart_on_change = originals.restart
    command.perform = originals.perform
    manager.addons, manager.valid_addons = originals.addons, originals.valid_addons
  end)

  test.test("routes overlapping commands to their own progress callbacks", function()
    responses = {
      { stdout = '{"progress":{"label":"purging","percent":0.5}}\n{}' },
      {
        stdout = '{"progress":{"label":"downloading Emmet","percent":0.5}}\n',
        stderr = '{"error":"download failed"}',
        code = 1
      }
    }
    local purge_progress, install_progress = {}, {}
    manager:purge({ progress = function(progress)
      table.insert(purge_progress, progress.label)
    end })
    local result = manager:install({ id = "lsp_emmet", version = "2.7.0" }, {
      progress = function(progress) table.insert(install_progress, progress.label) end
    })
    run_threads()
    test.equal(#purge_progress, 1)
    test.equal(purge_progress[1], "purging")
    test.equal(install_progress[2], "downloading Emmet")
    test.equal(result.success, false)
    test.equal(result.result, "download failed")
    test.contains(errors[1], " install lsp_emmet:2.7.0 ")
  end)

  test.test("reads complete errors longer than one pipe chunk", function()
    responses = {{
      code = 1,
      stderr = json.encode({ warnings = { ("repository warning "):rep(300) }, error = "fetch failed" })
    }}
    local result = manager:install({ id = "lsp_emmet" })
    run_threads()
    test.equal(result.success, false)
    test.equal(result.result, "fetch failed")
    test.contains(errors[1], ("repository warning "):rep(300))
  end)

  test.test("rejects plain stderr without aborting the process loop", function()
    responses = {{ code = 1, stderr = "fatal: TLS initialization failed\n" }}
    local result = manager:purge()
    run_threads()
    test.equal(result.success, false)
    test.equal(result.result, "fatal: TLS initialization failed\n")
  end)

  test.test("converts core.json's long progress numbers to numeric percentages", function()
    responses = {{ stdout = '{"progress":{"label":"Downloading","percent":0.12345678901234}}\n{}' }}
    local progress
    local result = manager:purge({ progress = function(value) progress = value end })
    run_threads()
    test.equal(result.success, true)
    test.equal(progress.percent, 0.12345678901234)
    test.type(progress.percent, "number")
  end)

  test.test("rejects decode errors returned by core.json for addon listings", function()
    responses = {{ stdout = '{"addons":[]} trailing garbage' }}
    local result = manager:refresh()
    run_threads()
    test.equal(result.success, false)
    test.contains(result.result, "trailing garbage")
  end)

  test.test("rejects non-object listing responses without indexing false", function()
    responses = {{ stdout = 'false' }}
    local result = manager:refresh()
    run_threads()
    test.equal(result.success, false)
    test.equal(result.result, "invalid ppm JSON response")
  end)

  test.test("leaves the unused standalone JSON addon unprotected", function()
    responses = {
      { stdout = '{"addons":[{"id":"json","status":"installed"}]}' },
      { stdout = '{"repositories":[]}' }
    }
    local result = manager:refresh()
    run_threads()
    test.equal(result.success, true)
    test.equal(manager.valid_addons[1].status, "installed")
  end)

  test.test("forwards listing errors to refresh callers", function()
    responses = {{ code = 1, stderr = '{"error":"repository fetch failed"}' }}
    local result = manager:refresh()
    run_threads()
    test.equal(result.success, false)
    test.equal(result.result, "repository fetch failed")
  end)

  test.test("forwards initial listing errors to addon callers", function()
    responses = {{ code = 1, stderr = '{"error":"repository fetch failed"}' }}
    local addons = manager.addons
    manager.addons = nil
    local result = manager:get_addons()
    run_threads()
    manager.addons = addons
    test.equal(result.success, false)
    test.equal(result.result, "repository fetch failed")
  end)

  test.test("clears the view loading state after a failed install", function()
    responses = {{ code = 1, stderr = '{"error":"download failed"}' }}
    local view = setmetatable({ plugin_manager = manager,
      refresh = function() return manager.promise.new():resolve() end
    }, { __index = manager.view })
    local result = view:install({ id = "lsp_emmet", status = "available" })
    test.equal(view.loading, true)
    run_threads()
    test.equal(result.success, false)
    test.equal(view.loading, false)
  end)

  local function listing_responses()
    return { { stdout = '{}' }, { stdout = '{"addons":[]}' }, { stdout = '{"repositories":[]}' } }
  end

  test.test("batch install submits unique versioned IDs in one command", function()
    responses = listing_responses()
    local result = manager:install_many({ { id = "first", version = "1.0" },
      { id = "second", version = "3.0" }, { id = "first", version = "2.0" } })
    run_threads()
    test.equal(result.success, true)
    test.equal(commands[1][2], "install")
    test.equal(commands[1][3], "first:2.0")
    test.equal(commands[1][4], "second:3.0")
    test.equal(commands[2][2], "list")
    test.equal(#commands, 3)
  end)

  test.test("selected upgrades update metadata once without pinning installed versions", function()
    responses = listing_responses()
    table.insert(responses, 1, { stdout = '{}' })
    local result = manager:upgrade_many({ { id = "first", version = "1.0", available_version = "2.0" },
      { id = "second", version = "3.0" } })
    run_threads()
    test.equal(result.success, true)
    test.equal(commands[1][2], "update")
    test.equal(commands[2][2], "install")
    test.equal(commands[2][3], "first")
    test.equal(commands[2][4], "second")
    test.equal(#commands, 4)
  end)

  test.test("batch completion callbacks run before exactly one soft restart", function()
    responses = { { stdout = '{}' } }
    config.plugins.plugin_manager.restart_on_change = true
    local events = {}
    command.perform = function(name)
      test.equal(name, "core:restart")
      events[#events + 1] = "restart"
    end
    local result = manager:install_many({ { id = "first" }, { id = "second" } }):done(function()
      events[#events + 1] = "completed"
    end)
    run_threads()
    test.equal(result.success, true)
    test.same(events, { "completed", "restart" })
    test.equal(#commands, 1)
  end)

  test.test("check for updates refreshes repositories and listing without installing", function()
    responses = listing_responses()
    local result = manager:check_for_updates()
    run_threads()
    test.equal(result.success, true)
    test.equal(commands[1][2], "repo")
    test.equal(commands[1][3], "update")
    test.equal(commands[2][2], "list")
    test.equal(#commands, 3)
  end)
end)

test.describe("plugin_manager view state", function()
  test.before_each(function(context)
    context.originals = {
      refresh = manager.refresh,
      addons = manager.addons,
      valid_addons = manager.valid_addons,
      add_thread = core.add_thread,
      active_view = core.active_view
    }
    threads = {}
    core.add_thread = function(fn)
      table.insert(threads, coroutine.create(fn))
    end
    manager.addons = {
      { id = "other", name = "Other", version = "1.0", type = "plugin",
        status = "available", tags = { "language" } },
      { id = "terminal", name = "Terminal", version = "1.0", type = "plugin",
        status = "installed", tags = { "utility" }, path = USERDIR .. PATHSEP .. "plugins/terminal" },
      { id = "terminal_extra", name = "Terminal Extra", version = "1.0", type = "plugin",
        status = "available", tags = { "utility" } }
    }
    manager.valid_addons = manager.addons
    context.refresh = manager.promise.new()
    manager.refresh = function() return context.refresh end
  end)

  test.after_each(function(context)
    manager.refresh = context.originals.refresh
    manager.addons = context.originals.addons
    manager.valid_addons = context.originals.valid_addons
    core.add_thread = context.originals.add_thread
    core.active_view = context.originals.active_view
  end)

  local function state(filter_text)
    return {
      filter_text = filter_text,
      sort = { column = 1, asc = false },
      selected_plugin_idx = 2,
      scroll = { x = 12, y = 24, to = { x = 12, y = 32 } }
    }
  end

  test.test("saves the current filter alongside existing view state", function()
    local view = manager.view()
    view:set_filter("terminal")
    view.sort = { column = 1, asc = false }
    view.list.scroll = { x = 12, y = 24, to = { x = 12, y = 32 } }
    local saved = view:get_state()
    test.equal(saved.filter_text, "terminal")
    test.same(saved.scroll, state().scroll)
    test.same(saved.sort, state().sort)
    test.equal(saved.category, "all")
    test.equal(saved.status_filter, "all")
  end)

  test.test("restores the filter before an asynchronous listing selects its row", function(context)
    local saved = state("TERMINAL")
    local view = manager.view.from_state(saved)
    test.equal(view.filter_text, "TERMINAL")
    test.equal(view.initialized, false)
    test.is_nil(view.selected_plugin)
    context.refresh:resolve()
    run_threads()
    test.equal(#view:get_sorted_plugins(), 2)
    test.equal(view.selected_plugin.id, "terminal")
    test.equal(view.search:get_text(), "TERMINAL")
    test.same(view:get_state().scroll, saved.scroll)
    test.equal(view:get_state().focused_id, "terminal")
  end)

  test.test("reapplies the filter when the initial listing completes immediately", function(context)
    context.refresh:resolve()
    local view = manager.view.from_state(state("utility"))
    run_threads()
    test.equal(#view:get_sorted_plugins(), 2)
    test.equal(view.selected_plugin.id, "terminal")
    test.equal(view:get_state().filter_text, "utility")
  end)

  test.test("restores older states without a filter as an unfiltered listing", function(context)
    local view = manager.view.from_state(state())
    context.refresh:resolve()
    run_threads()
    test.is_nil(view.filter_text)
    test.equal(#view:get_sorted_plugins(), 3)
    test.equal(view.selected_plugin.id, "terminal")
  end)

  test.test("keeps a cleared filter cleared when saving and restoring", function(context)
    local view = manager.view.from_state(state("terminal"))
    context.refresh:resolve()
    run_threads()
    command.map["plugin-manager:clear-filter"].perform(view)
    test.is_nil(view:get_state().filter_text)
    local restored = manager.view.from_state(view:get_state())
    run_threads()
    test.is_nil(restored.filter_text)
    test.equal(#restored:get_sorted_plugins(), 3)
  end)
end)

test.describe("plugin_manager widget view", function()
  test.before_each(function(context)
    context.originals = {
      addons = manager.addons, valid_addons = manager.valid_addons, refresh = manager.refresh,
      install_many = manager.install_many, upgrade_many = manager.upgrade_many,
      uninstall_many = manager.uninstall_many, check_for_updates = manager.check_for_updates,
      unstub = manager.unstub, open_doc = core.open_doc, root_open_doc = core.root_view.open_doc,
      show = core.nag_view.show, active_view = core.active_view,
      libraries = config.plugins.plugin_manager.show_libraries
    }
    context.addons = {
      { id = "first", name = "First Plugin", version = "1.0", type = "plugin", status = "available", tags = { "utility" } },
      { id = "second", name = "Second Plugin", version = "2.0", type = "plugin", status = "available", tags = { "language" } },
      { id = "language_local", version = "1.0", type = "plugin", status = "bundled", tags = {} },
      { id = "theme", version = "1.0", type = "color", status = "available", tags = { "dark" } },
      { id = "font", version = "1.0", type = "font", status = "available", tags = {} },
      { id = "updating", version = "1.0", available_version = "2.0", type = "plugin", status = "upgradable",
        path = USERDIR .. PATHSEP .. "plugins/updating.lua", tags = {} },
      { id = "orphan", version = "1.0", type = "plugin", status = "orphan",
        path = USERDIR .. PATHSEP .. "plugins/orphan.lua", tags = {} },
      { id = "protected", version = "1.0", type = "plugin", status = "special", tags = {} }
    }
    manager.addons, manager.valid_addons = context.addons, context.addons
    context.refresh_calls, context.operations = 0, {}
    manager.refresh = function()
      context.refresh_calls = context.refresh_calls + 1
      return manager.promise.new():resolve()
    end
    for _, method in ipairs({ "install_many", "upgrade_many", "uninstall_many", "check_for_updates" }) do
      manager[method] = function(_, addons, options)
        context.operations[#context.operations + 1] = { method = method, addons = addons, options = options }
        context.operation = manager.promise.new()
        return context.operation
      end
    end
    core.nag_view.show = function(_, title, message, options, callback)
      context.confirmation = { title = title, message = message, options = options, callback = callback }
    end
    context.view = manager.view()
    core.active_view = context.view
  end)

  test.after_each(function(context)
    local original = context.originals
    manager.addons, manager.valid_addons, manager.refresh = original.addons, original.valid_addons, original.refresh
    manager.install_many, manager.upgrade_many = original.install_many, original.upgrade_many
    manager.uninstall_many, manager.check_for_updates = original.uninstall_many, original.check_for_updates
    manager.unstub, core.open_doc, core.root_view.open_doc = original.unstub, original.open_doc, original.root_open_doc
    core.nag_view.show, core.active_view = original.show, original.active_view
    config.plugins.plugin_manager.show_libraries = original.libraries
    context.view:destroy_childs()
    if context.files_root then test.ok(common.rm(context.files_root, true)) end
  end)

  local function choose(box, data)
    for index = 2, #box.list.rows do
      if box.list:get_row_data(index) == data then box:set_selected(index - 1); return end
    end
    test.fail("missing option " .. data)
  end

  test.test("combines built-in search, category, and status without refetching", function(context)
    local view = context.view
    view.search:set_text("SECOND")
    choose(view.category_box, "language")
    choose(view.status_box, "available")
    test.equal(#view:get_sorted_plugins(), 1)
    test.equal(view:get_sorted_plugins()[1].id, "second")
    view:set_filter("language_local")
    test.equal(#view:get_sorted_plugins(), 0)
    choose(view.status_box, "installed")
    test.equal(view:get_sorted_plugins()[1].id, "language_local")
    view:set_filter("")
    choose(view.category_box, "type:color")
    choose(view.status_box, "all")
    view.search:set_text("DARK")
    test.equal(view:get_sorted_plugins()[1].id, "theme")
    choose(view.sort_box, "4:desc")
    test.equal(context.refresh_calls, 1)
    test.equal(view.sort.column, 4)
    test.equal(view.sort.asc, false)
  end)

  test.test("preserves checked IDs across filters and installs hidden selections together", function(context)
    local view = context.view
    view:set_checked(context.addons[1], true)
    view:set_checked(context.addons[2], true)
    view:set_filter("first")
    test.equal(#view:get_checked_plugins("install"), 2)
    test.contains(view.selection_label.label, "1 hidden")
    test.equal(view.batch_buttons.install.label, "Install (2)")
    view.batch_buttons.install:on_click("left")
    test.equal(#context.operations, 1)
    test.equal(#context.operations[1].addons, 2)
    test.equal(view.loading, true)
    context.operations[1].options.progress({ label = "Downloading file.zip", percent = 0.5 })
    test.equal(view.progress.label, "Downloading file.zip")
    test.equal(view.batch_buttons.install.enabled, false)
    context.operation:resolve()
    test.equal(view.loading, false)
    test.same(view.checked, {})
  end)

  test.test("selects only visible actionable rows and keeps one candidate per ID", function(context)
    local view = context.view
    view:set_filter("first")
    view:check_visible(true)
    test.equal(#view:get_checked_plugins(), 1)
    view:set_filter("second")
    view:check_visible(true)
    test.equal(#view:get_checked_plugins(), 2)
    local candidate = common.merge(context.addons[1], { version = "2.0" })
    manager.valid_addons[#manager.valid_addons + 1] = candidate
    view:refresh(true)
    view:set_checked(candidate, true)
    local checked = view:get_checked_plugins()
    test.equal(#checked, 2)
    for _, addon in ipairs(checked) do if addon.id == "first" then test.equal(addon.version, "2.0") end end
    view:set_filter("")
    view:check_visible(true)
    test.is_nil(view.checked.protected)
    test.is_nil(view.checked.language_local)
    test.equal(view.select_visible.checked, true)
    test.equal(view.select_visible.mixed, false)
    for _, addon in ipairs(view:get_checked_plugins()) do
      if addon.id == "first" then test.equal(addon.version, "2.0") end
    end
  end)

  test.test("selected commands do not act on an unchecked focused row", function(context)
    local view = context.view
    view:set_checked(context.addons[1], true)
    view:focus_plugin(context.addons[6])
    test.equal(command.is_valid("plugin-manager:upgrade-selected"), false)
    test.equal(command.is_valid("plugin-manager:uninstall-selected"), false)
    test.equal(command.is_valid("plugin-manager:install-selected"), true)
  end)

  test.test("keyboard controls close menus before clearing search and activate checkboxes", function(context)
    local view = context.view
    view:set_filter("first")
    view.category_box:on_click("left")
    test.equal(view.category_box.list_container.visible, true)
    test.ok(command.perform("plugin-manager:escape"))
    test.equal(view.category_box.list_container.visible, false)
    test.equal(view.filter_text, "first")
    test.ok(command.perform("plugin-manager:escape"))
    test.is_nil(view.filter_text)
    view:swap_active_child(view.select_visible)
    test.ok(command.perform("plugin-manager:toggle-selected"))
    test.equal(#view:get_checked_plugins(), 6)
    view:swap_active_child(view.clear_selection)
    test.ok(command.perform("plugin-manager:activate-control"))
    test.same(view.checked, {})
  end)

  test.test("shows eligible subsets for mixed selections and protects bundled rows", function(context)
    local view = context.view
    for _, addon in ipairs(context.addons) do view:set_checked(addon, true) end
    test.equal(#view:get_checked_plugins("install"), 4)
    test.equal(#view:get_checked_plugins("upgrade"), 1)
    test.equal(#view:get_checked_plugins("uninstall"), 2)
    view:focus_plugin(context.addons[3])
    test.equal(view.details_buttons.uninstall.visible, false)
    test.equal(command.is_valid("plugin-manager:uninstall-hovered"), false)
    view:focus_plugin(context.addons[6])
    test.equal(view.details_buttons.uninstall.visible, true)
    test.equal(view.details_buttons.upgrade.visible, true)
  end)

  test.test("confirming or cancelling uninstall does not remove protected files", function(context)
    local view = context.view
    view:set_checked(context.addons[6], true)
    view:set_checked(context.addons[7], true)
    local result = view:apply_action("uninstall", view:get_checked_plugins("uninstall"))
    test.equal(view.confirming, true)
    test.equal(#context.operations, 0)
    test.contains(context.confirmation.message, "Dependent addons")
    context.confirmation.callback({ text = "Cancel" })
    test.equal(result.result, false)
    test.equal(#context.operations, 0)
    test.equal(#view:get_checked_plugins(), 2)
    view:apply_action("uninstall", view:get_checked_plugins("uninstall"))
    context.confirmation.callback({ text = "Uninstall" })
    test.equal(context.operations[1].method, "uninstall_many")
    test.equal(#context.operations[1].addons, 2)
    context.operation:resolve()
    test.same(view.checked, {})
  end)

  test.test("failure clears busy state and reconciles completed and unresolved selections", function(context)
    local view = context.view
    view:set_checked(context.addons[1], true)
    view:set_checked(context.addons[2], true)
    local result = view:apply_action("install", view:get_checked_plugins("install"))
    manager.valid_addons[1] = common.merge(context.addons[1], {
      status = "installed", path = USERDIR .. PATHSEP .. "plugins/first.lua"
    })
    context.operation:reject("second download failed")
    test.equal(result.success, false)
    test.equal(view.loading, false)
    test.equal(view.error_message, "second download failed")
    test.equal(context.refresh_calls, 2)
    test.is_nil(view.checked.first)
    test.not_nil(view.checked.second)
  end)

  test.test("row double clicks toggle visible checkboxes without mutating plugins", function(context)
    local view = context.view
    view:set_filter("first")
    view:set_size(1100, 700)
    view:update()
    local row = view.list.items[1].row
    row:on_mouse_pressed("left", row.position.x + 80, row.position.y + 8, 2)
    test.equal(view.selected_plugin.id, row.data.id)
    test.equal(row.checkbox.checked, true)
    test.equal(#view:get_checked_plugins(), 1)
    row:on_mouse_pressed("left", row.position.x + 80, row.position.y + 8, 2)
    test.equal(row.checkbox.checked, false)
    test.equal(#view:get_checked_plugins(), 0)
    test.equal(#context.operations, 0)
    view:focus_plugin(context.addons[5])
    test.equal(view.details_buttons.source.visible, false)
    test.equal(view.details_buttons.readme.visible, false)
    test.equal(command.is_valid("plugin-manager:view-source-hovered"), false)
    test.equal(command.is_valid("plugin-manager:view-readme-hovered"), false)
  end)

  test.test("row double clicks respect hidden checkboxes and busy operations", function(context)
    local view = context.view
    view:set_size(1300, 800)
    view:update()
    local rows = {}
    for _, plugin, row in view.list:each_item() do rows[plugin.id] = row end
    local function click(row, button)
      row:on_mouse_pressed(button or "left", row.position.x + 80, row.position.y + 8, 2)
    end
    click(rows.language_local)
    click(rows.protected)
    test.same(view.checked, {})
    click(rows.first, "right")
    test.same(view.checked, {})
    view.loading = true
    click(rows.first)
    test.same(view.checked, {})
    view.loading, view.confirming = false, true
    click(rows.first)
    test.same(view.checked, {})
    view.confirming = false
    click(rows.updating)
    test.equal(rows.updating.checkbox.checked, true)
    test.equal(#context.operations, 0)
  end)

  test.test("double clicking the checkbox does not also toggle the row", function(context)
    local view = context.view
    view:set_filter("first")
    view:set_size(1300, 800)
    view:update()
    local row = view.list.items[1].row
    local checkbox = row.checkbox
    local x, y = checkbox.position.x + checkbox.size.x / 2, checkbox.position.y + checkbox.size.y / 2
    row:on_mouse_pressed("left", x, y, 1)
    row:on_mouse_released("left", x, y)
    test.equal(checkbox.checked, true)
    row:on_mouse_pressed("left", x, y, 2)
    row:on_mouse_released("left", x, y)
    test.equal(checkbox.checked, false)
    test.same(view.checked, {})
    test.equal(#context.operations, 0)
  end)

  for _, cached in ipairs({ true, false }) do
    test.test("README and Source preserve list position with " .. (cached and "cached" or "downloaded") .. " metadata", function(context)
      local view = context.view
      context.files_root = core.temp_filename("-plugin-manager-readme-tests")
      test.ok(common.mkdirp(context.files_root))
      for _, name in ipairs({ "README.md", "init.lua" }) do
        local file = assert(io.open(context.files_root .. PATHSEP .. name, "wb"))
        file:write("plugin manager navigation fixture\n")
        file:close()
      end
      core.open_doc = function(path) return path end
      core.root_view.open_doc = function(_, doc) context.opened_doc = doc end
      for index = 1, 80 do
        context.addons[#context.addons + 1] = {
          id = string.format("fixture_%03d", index), version = "1.0",
          type = "plugin", status = "available", tags = {}
        }
      end
      view:refresh(true)
      view:set_size(1300, 800)
      view:update()
      local plugin = view:get_sorted_plugins()[40]
      view:focus_plugin(plugin)
      for _, kind in ipairs({ "readme", "source" }) do
        plugin.path = cached and context.files_root or nil
        local pending
        if not cached then
          pending = manager.promise.new()
          manager.unstub = function() return pending end
        end
        local scroll = { x = 0, y = 650, to = { x = 0, y = 710 } }
        view.list.scroll.y, view.list.scroll.to.y = scroll.y, scroll.to.y
        view.details_buttons[kind]:on_click("left")
        if pending then
          test.equal(view.loading, true)
          plugin.path = context.files_root
          pending:resolve(plugin)
        end
        test.equal(context.opened_doc, context.files_root .. PATHSEP .. (kind == "readme" and "README.md" or "init.lua"))
        test.same(view:get_state().scroll, scroll)
        test.equal(view.selected_plugin, plugin)
        view:update()
        test.equal(view.list.scroll.to.y, scroll.to.y)
        test.ok(view.list.scroll.y > 0)
        test.equal(view.loading, false)
      end
    end)
  end

  test.test("refreshing retains list position while changing filters resets it", function(context)
    local view = context.view
    view.list.scroll.y, view.list.scroll.to.y = 24, 32
    view:refresh()
    test.equal(view.list.scroll.y, 24)
    test.equal(view.list.scroll.to.y, 32)
    view:set_filter("first")
    test.equal(view.list.scroll.y, 0)
    test.equal(view.list.scroll.to.y, 0)
  end)

  test.test("restores controls, checked candidates, focused ID, and panel size", function(context)
    local view = context.view
    view:set_checked(context.addons[1], true)
    view:set_checked(context.addons[2], true)
    view:set_filter("first")
    choose(view.category_box, "type:plugin")
    choose(view.status_box, "available")
    view:focus_plugin(context.addons[1])
    view.details_ratio = 0.4
    local saved = view:get_state()
    local restored = manager.view.from_state(saved)
    test.same(restored:get_state(), saved)
    test.equal(restored.search:get_text(), "first")
    test.equal(restored.category_box:get_selected_data(), "type:plugin")
    test.equal(restored.status_box:get_selected_data(), "available")
    test.equal(restored.selected_plugin.id, "first")
    test.equal(#restored:get_checked_plugins(), 2)
    restored:destroy_childs()
  end)

  test.test("commands use the owning view while search has focus", function(context)
    local view = context.view
    local other = manager.view()
    core.active_view = view.search.textview
    test.equal(manager.view.active(), view)
    test.ok(command.perform("plugin-manager:clear-filter"))
    test.equal(manager.view.active(), view)
    test.ok(command.perform("plugin-manager:focus-next"))
    test.equal(view.child_active, view.search)
    test.is_nil(other.child_active)
    other:destroy_childs()
  end)

  test.test("libraries category follows the existing visibility preference", function(context)
    local view = context.view
    config.plugins.plugin_manager.show_libraries = true
    view:refresh(true)
    choose(view.category_box, "type:library")
    test.equal(#view:get_sorted_plugins(), 0)
    config.plugins.plugin_manager.show_libraries = false
    view:refresh(true)
    test.equal(view.category, "all")
  end)

  test.test("bottom details and wrapped controls stay within wide and narrow views", function(context)
    local view = context.view
    view:focus_plugin(context.addons[1])
    for _, size in ipairs({ { 1300, 800 }, { 580, 800 }, { 420, 800 } }) do
      view:set_size(size[1], size[2])
      view:update()
      test.ok(view.list.size.y > 0)
      test.ok(view.details_body.position.y >= view.list.position.y + view.list.size.y)
      for _, child in ipairs(view.childs) do
        if child.visible then
          test.ok(child.position.x + child.size.x <= view.position.x + view.size.x + 1)
          test.ok(child.position.y + child.size.y <= view.position.y + view.size.y + 1)
        end
      end
    end
  end)

  test.test("clear buttons stay square and compact batch buttons keep stable widths", function(context)
    local view = context.view
    view:set_size(1300, 800)
    view:update()
    for _, button in ipairs({ view.clear_search, view.clear_selection }) do
      test.equal(button.size.x, button.size.y)
    end
    for action, button in pairs(view.batch_buttons) do
      local width = button.size.x
      local name = action:sub(1, 1):upper() .. action:sub(2)
      test.equal(button.padding.x, style.padding.x / 2)
      for _, count in ipairs({ 0, 1, 99, 999 }) do
        button:set_label(name .. " (" .. count .. ")")
        button:update_size_position()
        test.equal(button.size.x, width)
        local contents = style.font:get_width(button.label)
          + style.icon_font:get_width(button.icon.code) + style.padding.x / 2
        test.ok(contents <= width)
      end
    end
  end)
end)

test.describe("plugin_manager addon compatibility", function()
  test.before_each(function(context)
    context.addons = manager.addons
    context.enter = core.command_view.enter
    context.root = core.temp_filename("-plugin-manager-tests")
    test.ok(common.mkdirp(context.root))
  end)

  test.after_each(function(context)
    manager.addons = context.addons
    core.command_view.enter = context.enter
    if context.root and system.get_file_info(context.root) then
      test.ok(common.rm(context.root, true))
    end
  end)

  test.test("requires the requested addon id and version even without a mod version", function()
    manager.addons = {
      { id = "other", version = "1.0" },
      { id = "wanted", version = "1.0" },
      { id = "wanted", version = "2.0" }
    }
    test.equal(manager:get_addon("wanted:2.0").result, manager.addons[3])
    test.equal(manager:get_addon("wanted").result, manager.addons[2])
    test.equal(manager:get_addon("wanted:3.0").success, false)
    test.equal(manager:get_addon("missing").success, false)
  end)

  test.test("matches the runtime loader for semantic mod versions", function(context)
    local versions = {
      MOD_VERSION_MAJOR, MOD_VERSION_STRING,
      string.format("%d.%d", MOD_VERSION_MAJOR, MOD_VERSION_MINOR),
      string.format("%d.%d.%d", MOD_VERSION_MAJOR, MOD_VERSION_MINOR, MOD_VERSION_PATCH + 1),
      string.format("%d.%d.0", MOD_VERSION_MAJOR, MOD_VERSION_MINOR + 1),
      string.format("%d.0.0", MOD_VERSION_MAJOR + 1),
      string.format("%d.0.0", MOD_VERSION_MAJOR - 1)
    }
    if MOD_VERSION_MINOR > 0 then
      table.insert(versions, string.format("%d.%d.%d",
        MOD_VERSION_MAJOR, MOD_VERSION_MINOR - 1, MOD_VERSION_PATCH + 10))
    end
    for _, version in ipairs(versions) do
      local path = context.root .. PATHSEP .. "version_fixture.lua"
      local file = assert(io.open(path, "wb"))
      file:write("-- mod-version: " .. version .. "\nreturn {}\n")
      file:close()
      local details = core.get_plugin_details(path)
      manager.addons = {{ id = "version_fixture", version = "1.0", mod_version = version }}
      test.equal(manager:get_addon("version_fixture").success, details.version_match,
        "mod-version " .. version)
    end
  end)

  test.test("suggests only available addons compatible with the full runtime version", function()
    manager.addons = {
      { id = "compatible", version = "1.0", mod_version = MOD_VERSION_STRING, status = "available" },
      { id = "installed", version = "1.0", mod_version = MOD_VERSION_STRING, status = "installed" },
      { id = "no_version", version = "1.0", status = "installed" },
      { id = "future", version = "1.0", mod_version = string.format("%d.%d.0",
        MOD_VERSION_MAJOR, MOD_VERSION_MINOR + 1), status = "available" }
    }
    local options
    core.command_view.enter = function(_, _, value) options = value end
    command.map["plugin-manager:install"].perform()
    test.same(options.suggest(""), { "compatible:1.0" })
  end)
end)
