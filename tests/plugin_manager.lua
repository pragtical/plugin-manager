local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local json = require "libraries.json"
local manager = require "plugins.plugin_manager"
local test = require "core.test"

local originals, threads, responses, errors

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
      restart = config.plugins.plugin_manager.restart_on_change
    }
    threads, responses, errors = {}, {}, {}
    config.plugins.plugin_manager.restart_on_change = false
    process.start = function()
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
    local view = setmetatable({ plugin_manager = manager }, { __index = manager.view })
    local result = view:install({ id = "lsp_emmet" })
    test.equal(view.loading, true)
    run_threads()
    test.equal(result.success, false)
    test.equal(view.loading, false)
  end)
end)

test.describe("plugin_manager view state", function()
  test.before_each(function(context)
    context.originals = {
      refresh = manager.refresh,
      addons = manager.addons,
      valid_addons = manager.valid_addons,
      add_thread = core.add_thread
    }
    threads = {}
    core.add_thread = function(fn)
      table.insert(threads, coroutine.create(fn))
    end
    manager.addons = {
      { id = "other", name = "Other", version = "1.0", type = "plugin",
        status = "available", tags = { "language" } },
      { id = "terminal", name = "Terminal", version = "1.0", type = "plugin",
        status = "installed", tags = { "utility" } },
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
    view.filter_text = "terminal"
    view.sort = { column = 1, asc = false }
    view.selected_plugin_idx = 2
    view.scroll = { x = 12, y = 24, to = { x = 12, y = 32 } }
    test.same(view:get_state(), state("terminal"))
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
    test.same(view:get_state(), saved)
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
    command.map["plugin-manager:clear-filter"].perform()
    test.is_nil(view:get_state().filter_text)
    local restored = manager.view.from_state(view:get_state())
    run_threads()
    test.is_nil(restored.filter_text)
    test.equal(#restored:get_sorted_plugins(), 3)
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
