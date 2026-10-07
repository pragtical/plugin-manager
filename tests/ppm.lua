local core = require "core"
local common = require "core.common"
local config = require "core.config"
local json = require "core.json"
local test = require "core.test"

local function write(path, contents)
  local directory = common.dirname(path)
  if not system.get_file_info(directory) then test.ok(common.mkdirp(directory)) end
  local file = assert(io.open(path, "wb"))
  file:write(contents)
  file:close()
end

local function read(path)
  local file = assert(io.open(path, "rb"))
  local contents = file:read("*a")
  file:close()
  return contents
end

local function exists(path, kind)
  local info = system.get_file_info(path)
  test.not_nil(info, "missing " .. path)
  if kind then test.equal(info.type, kind) end
end

local function execute(context, argv, environment)
  local proc, err = process.start(argv, {
    cwd = context.cwd,
    stdout = process.REDIRECT_PIPE,
    stderr = process.REDIRECT_PIPE,
    env = function(env)
      env = common.merge(env, environment)
      local entries = {}
      for key, value in pairs(env) do
        if not key:upper():find("^PPM_") or environment and environment[key] then
          table.insert(entries, key .. "=" .. value)
        end
      end
      return table.concat(entries, "\0") .. "\0\0"
    end
  })
  test.not_nil(proc, err)
  context.proc = proc
  local stdout, stderr = {}, {}
  local started = system.get_time()
  while true do
    local out = proc:read_stdout(8192)
    local errout = proc:read_stderr(8192)
    if out and #out > 0 then table.insert(stdout, out) end
    if errout and #errout > 0 then table.insert(stderr, errout) end
    if not proc:running() and out == nil and errout == nil then break end
    test.ok(system.get_time() - started < 30,
      "timed out: " .. table.concat(argv, " "))
    coroutine.yield(0.01)
  end
  context.proc = nil
  return proc:returncode(), table.concat(stdout), table.concat(stderr)
end

local function ppm(context, args, options)
  options = options or {}
  local argv = {
    context.binary, "--quiet", "--json", "--assume-yes",
    "--mod-version=" .. MOD_VERSION_STRING,
    "--binary=" .. EXEFILE,
    "--datadir=" .. context.datadir,
    "--userdir=" .. context.userdir,
    "--cachedir=" .. context.root .. PATHSEP .. "cache",
    "--configdir=" .. context.root .. PATHSEP .. "config",
    "--tmpdir=" .. context.root .. PATHSEP .. "tmp",
    "--bottledir=" .. context.root .. PATHSEP .. "bottles"
  }
  if not options.install_optional then
    table.insert(argv, "--no-install-optional")
  end
  for _, arg in ipairs(args) do table.insert(argv, arg) end
  local code, stdout, stderr = execute(context, argv)
  if options.failure then
    test.not_equal(code, 0, "expected ppm to fail: " .. table.concat(args, " "))
    return json.decode(stderr)
  end
  test.equal(code, 0, table.concat(argv, " ") .. "\n" .. stderr)
  if stdout == "" then return {} end
  return json.decode(stdout)
end

local function addon(context, id, status)
  for _, entry in ipairs(ppm(context, { "list", id }).addons) do
    if entry.id == id and (not status or entry.status == status) then return entry end
  end
  test.fail("missing addon " .. id .. " with status " .. tostring(status))
end

local function create_repository(context)
  local repo = context.root .. PATHSEP .. "repo"
  local manifest = { addons = {} }
  local function add(id, path, extra)
    local entry = common.merge({
      id = id, path = path, version = "1.0", mod_version = MOD_VERSION_STRING
    }, extra)
    table.insert(manifest.addons, entry)
    write(repo .. PATHSEP .. path,
      "-- mod-version: " .. entry.mod_version .. "\nreturn {}\n")
    return entry
  end
  add("bracketmatch", "plugins/bracketmatch.lua")
  add("plugin_manager", "plugins/plugin_manager/init.lua", {
    organization = "complex", dependencies = { encoding = {} }, files = {
      { arch = "x86_64-linux", url = "https://example.invalid/ppm.x86_64-linux",
        checksum = "SKIP", optional = true },
      { arch = "x86_64-windows", url = "https://example.invalid/ppm.x86_64-windows.exe",
        checksum = "SKIP", optional = true }
    }
  })
  write(repo .. PATHSEP .. "ppm.x86_64-linux", "linux fixture\n")
  write(repo .. PATHSEP .. "ppm.x86_64-windows.exe", "windows fixture\n")
  add("editorconfig", "plugins/editorconfig/init.lua", { organization = "complex" })
  add("lintplus", "plugins/lintplus/init.lua", { organization = "complex" })
  add("widget", "libraries/widget/init.lua", { type = "library", organization = "complex" })
  add("lsp", "plugins/lsp/init.lua", {
    organization = "complex", dependencies = { lintplus = {}, widget = {} }
  })
  add("encoding", "libraries/encoding/init.lua", { type = "library", organization = "complex" })
  add("encodings", "plugins/encodings.lua", { dependencies = { encoding = {} } })
  for _, id in ipairs({ "gitblame", "gitstatus", "language_ts", "minimap" }) do
    add(id, "plugins/" .. id .. ".lua")
  end
  context.repo, context.manifest = repo, manifest
  write(repo .. PATHSEP .. "manifest.json", json.encode(manifest))
end

test.describe("ppm integration", function()
  test.before_each(function(context)
    local repo_root = common.dirname(common.dirname(context.file))
    context.cwd = repo_root
    context.binary = os.getenv("PPM_BINARY")
      or repo_root .. PATHSEP .. "build" .. PATHSEP
        .. (PLATFORM == "Windows" and "ppm.exe" or "ppm")
    if not os.getenv("PPM_BINARY") and not system.get_file_info(context.binary) then
      context.binary = config.plugins.plugin_manager.ppm_binary_path
    end
    exists(context.binary, "file")
    context.root = core.temp_filename("-ppm-tests")
    context.userdir = context.root .. PATHSEP .. "user"
    context.datadir = context.root .. PATHSEP .. "data"
    test.ok(common.mkdirp(context.userdir))
    test.ok(common.mkdirp(context.datadir .. PATHSEP .. "plugins"))
    create_repository(context)
    ppm(context, { "init", "none" })
    ppm(context, { "repo", "add", common.relative_path(repo_root, context.repo) })
  end)

  test.after_each(function(context)
    if context.proc and context.proc:running() then
      context.proc:kill()
      context.proc:wait(5000, 0.01)
    end
    if context.root and system.get_file_info(context.root) then
      test.ok(common.rm(context.root, true))
    end
  end)

  test.test("installs and uninstalls a singleton", function(context)
    test.equal(addon(context, "bracketmatch", "available").organization, "singleton")
    local actions = ppm(context, { "install", "bracketmatch" }).actions
    test.contains(actions[1], "Installing singleton")
    exists(context.userdir .. PATHSEP .. "plugins/bracketmatch.lua", "file")
    ppm(context, { "uninstall", "bracketmatch" })
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "plugins/bracketmatch.lua"))
  end)

  test.test("batch uninstall skips targets already removed by dependency cleanup", function(context)
    ppm(context, { "install", "lsp" })
    local result = ppm(context, { "uninstall", "lsp", "lintplus", "widget", "lsp" })
    test.ok(#result.actions >= 3)
    for _, path in ipairs({ "plugins/lsp", "plugins/lintplus", "libraries/widget" }) do
      test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. path))
    end
    test.equal(addon(context, "lsp").status, "available")
  end)

  test.test("batch uninstall handles dependency targets before their dependents", function(context)
    ppm(context, { "install", "lsp" })
    ppm(context, { "uninstall", "widget", "lsp", "lintplus" })
    for _, path in ipairs({ "plugins/lsp", "plugins/lintplus", "libraries/widget" }) do
      test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. path))
    end
  end)

  test.test("batch uninstall validates missing targets before removing files", function(context)
    ppm(context, { "install", "bracketmatch" })
    local result = ppm(context, { "uninstall", "bracketmatch", "missing_fixture" }, { failure = true })
    test.contains(result.error, "missing_fixture")
    exists(context.userdir .. PATHSEP .. "plugins/bracketmatch.lua", "file")
  end)

  test.test("batch uninstall preserves bundled dependencies and bundled targets", function(context)
    local bundled = context.datadir .. PATHSEP .. "libraries/widget/init.lua"
    local contents = read(context.repo .. PATHSEP .. "libraries/widget/init.lua")
    write(bundled, contents)
    ppm(context, { "install", "lsp" })
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "libraries/widget"))
    ppm(context, { "uninstall", "lsp", "widget" })
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "plugins/lsp"))
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "plugins/lintplus"))
    test.equal(read(bundled), contents)
    addon(context, "widget", "bundled")
  end)

  test.test("reinstalls a modified singleton", function(context)
    ppm(context, { "install", "bracketmatch" })
    local installed = addon(context, "bracketmatch", "installed")
    write(installed.path, read(installed.path) .. "-- changed checksum\n")
    addon(context, "bracketmatch", "orphan")
    addon(context, "bracketmatch", "available")
    ppm(context, { "install", "bracketmatch" })
    addon(context, "bracketmatch", "installed")
    test.equal(read(installed.path), read(context.repo .. PATHSEP .. "plugins/bracketmatch.lua"))
  end)

  test.test("installs and uninstalls a complex addon with a library", function(context)
    local entry = addon(context, "plugin_manager", "available")
    test.equal(entry.organization, "complex")
    test.not_nil(entry.dependencies.encoding)
    ppm(context, { "install", "plugin_manager" })
    exists(context.userdir .. PATHSEP .. "libraries/encoding/init.lua", "file")
    exists(context.userdir .. PATHSEP .. "plugins/plugin_manager/init.lua", "file")
    ppm(context, { "uninstall", "plugin_manager" })
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "plugins/plugin_manager"))
    ppm(context, { "install", "editorconfig" })
    exists(context.userdir .. PATHSEP .. "plugins/editorconfig/init.lua", "file")
  end)

  test.test("upgrades a complex addon when its repository changes", function(context)
    ppm(context, { "install", "editorconfig" })
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "editorconfig" then entry.version = "1.1" end
    end
    write(context.repo .. PATHSEP .. "plugins/editorconfig/init.lua",
      "-- mod-version: " .. MOD_VERSION_STRING .. "\nreturn { updated = true }\n")
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    addon(context, "editorconfig", "upgradable")
    ppm(context, { "upgrade" })
    test.equal(addon(context, "editorconfig", "installed").version, "1.1")
  end)

  test.test("lists repository addons and filters core addons", function(context)
    write(context.datadir .. PATHSEP .. "plugins/language_lua.lua",
      "-- mod-version: " .. MOD_VERSION_STRING .. "\nreturn {}\n")
    local entries = ppm(context, { "list" }).addons
    test.ok(#entries >= #context.manifest.addons + 1)
    for _, entry in ipairs(context.manifest.addons) do addon(context, entry.id, "available") end
    local entries_core = ppm(context, { "list", "language_lua", "--status", "core" }).addons
    test.equal(#entries_core, 1)
    test.equal(entries_core[1].id, "language_lua")
  end)

  test.test("installs a remote stub and singleton library dependency", function(context)
    local remote = context.root .. PATHSEP .. "remote"
    write(remote .. PATHSEP .. "init.lua",
      "-- mod-version: " .. MOD_VERSION_STRING .. "\nreturn {}\n")
    write(remote .. PATHSEP .. "manifest.json", json.encode({ addons = {{
      id = "lsp", version = "1.0", mod_version = MOD_VERSION_STRING,
      path = "init.lua", organization = "complex",
      dependencies = { lintplus = {}, widget = {} }
    }} }))
    local code, _, stderr = execute(context, { "git", "init", "--initial-branch=master", remote })
    test.equal(code, 0, stderr)
    code, _, stderr = execute(context, { "git", "-C", remote, "add", "." })
    test.equal(code, 0, stderr)
    code, _, stderr = execute(context, {
      "git", "-C", remote, "-c", "user.name=ppm tests",
      "-c", "user.email=ppm-tests@example.invalid", "-c", "commit.gpgsign=false",
      "commit", "-m", "Add fixture"
    })
    test.equal(code, 0, stderr)
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "lsp" then
        entry.path = nil
        local path = remote:gsub("\\", "/")
        if path:sub(1, 1) ~= "/" then path = "/" .. path end
        entry.remote = "file://" .. path .. ":master"
      end
    end
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    ppm(context, { "install", "lsp" })
    exists(context.userdir .. PATHSEP .. "plugins/lsp/init.lua", "file")
    exists(context.userdir .. PATHSEP .. "libraries/widget/init.lua", "file")
    ppm(context, { "install", "encodings" })
    exists(context.userdir .. PATHSEP .. "plugins/encodings.lua", "file")
    exists(context.userdir .. PATHSEP .. "libraries/encoding", "dir")
  end)

  test.test("validates the project manifest", function(context)
    local root = common.dirname(common.dirname(context.file))
    local manifest = json.decode(read(root .. PATHSEP .. "manifest.json"))
    test.equal(#manifest.remotes, 2)
    test.equal(#manifest.addons, 1)
    for _, entry in ipairs(manifest.addons) do
      test.type(entry.id, "string")
      test.type(entry.version, "string")
      exists(root .. PATHSEP .. entry.path)
      if entry.id == "plugin_manager" then
        test.equal(entry.mod_version, "3.10.0")
        test.is_nil(entry.dependencies and entry.dependencies.json)
      end
    end
  end)

  test.test("installs multiple addons in one command", function(context)
    local ids = { "encoding", "gitblame", "gitstatus", "language_ts", "lsp", "minimap" }
    ppm(context, { "install", table.unpack(ids) })
    for _, id in ipairs(ids) do addon(context, id, "installed") end
  end)

  test.test("updates repositories without upgrading installed addons", function(context)
    ppm(context, { "install", "bracketmatch" })
    local installed = addon(context, "bracketmatch", "installed")
    local contents = read(installed.path)
    context.manifest.addons[1].version = "1.1"
    write(context.repo .. PATHSEP .. "plugins/bracketmatch.lua",
      "-- mod-version: " .. MOD_VERSION_STRING .. "\nreturn { updated = true }\n")
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    ppm(context, { "update" })
    addon(context, "bracketmatch", "upgradable")
    test.equal(addon(context, "bracketmatch", "available").version, "1.1")
    test.equal(read(installed.path), contents)
    ppm(context, { "upgrade" })
    test.equal(addon(context, "bracketmatch", "installed").version, "1.1")
  end)

  test.test("installs files for multiple architectures", function(context)
    test.skip_if(PLATFORM == "Windows", "local symlinks require developer mode on Windows")
    ppm(context, {
      "install", "plugin_manager", "--symlink",
      "--arch", "x86_64-windows", "--arch", "x86_64-linux"
    }, { install_optional = true })
    local path = context.userdir .. PATHSEP .. "plugins/plugin_manager/"
    exists(path .. "ppm.x86_64-linux", "file")
    exists(path .. "ppm.x86_64-windows.exe", "file")
    exists(path .. "init.lua", "file")
    ppm(context, { "uninstall", "plugin_manager" })
  end)

  test.test("removes unused user dependencies on uninstall", function(context)
    ppm(context, { "install", "lsp" })
    exists(context.userdir .. PATHSEP .. "plugins/lsp", "dir")
    exists(context.userdir .. PATHSEP .. "plugins/lintplus", "dir")
    ppm(context, { "uninstall", "lsp" })
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "plugins/lsp"))
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "plugins/lintplus"))
  end)

  test.test("masks a dependency during installation", function(context)
    ppm(context, { "install", "lsp", "--mask", "lintplus" })
    exists(context.userdir .. PATHSEP .. "plugins/lsp", "dir")
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "plugins/lintplus"))
  end)

  test.test("adds and removes a repository", function(context)
    local other = context.root .. PATHSEP .. "other-repo"
    write(other .. PATHSEP .. "manifest.json", json.encode({ addons = {} }))
    local url = common.relative_path(context.cwd, other)
    ppm(context, { "repo", "add", url })
    test.equal(#ppm(context, { "repo", "list" }).repositories, 2)
    ppm(context, { "repo", "rm", url })
    test.equal(#ppm(context, { "repo", "list" }).repositories, 1)
  end)

  local archive_fixtures = {
    { extension = "zip", hex =
      "504b03041400000008002d74475dfa99493131000000500100000b000000" ..
      "7061796c6f61642e7478742b28c85548492d48cd4b49cd4bae54282d482f" ..
      "4a4c4955482c4acec82c4b5528cecdcf4e5528492d2ee12a185549844a00" ..
      "504b01021e031400000008002d74475dfa99493131000000500100000b00" ..
      "00000000000001000000a481000000007061796c6f61642e747874504b05" ..
      "060000000001000100390000005a0000000000"
    },
    { extension = "tar.gz", hex =
      "1f8b0800000000000003edd1c10ac2300cc6f19d7d8a3c8174aefa3e650d" ..
      "2abaadb49db8b7b7ece2f0e4652af8ff5d12c2070924b8e93a38bfcdf75c" ..
      "adc514076be75abc56b3df3dfb795e9bbab19598d52e5a185376b1acffc4" ..
      "ae1f1442275e83f65efb7692311ca3f32a2eb6a7f34d2575c345256bca1b" ..
      "92ef24bffd4f00000000000000000000000000ffe3017adab04100280000"
    },
    { extension = "tar.xz", hex =
      "fd377a585a00000ae1fb0ca104c1930180500b002101160000000000e5b9" ..
      "86e7e027ff008b5d0038184b99750f46086fd33a2097f4d96286eccbb0d4" ..
      "75d1a37515586bee0abe4064f17f24c5736da63b8a3c0377a13770f849bd" ..
      "31ac99921dc60f94e17dbfc882a718160d3e411a597a1a4bbbd0bd2a1070" ..
      "5189f25df55df60681df47d21038fcaaf90a44cf70f141d5ccae4a1b34af" ..
      "fc3147943896d3282204cf68952627f86098e75c075f03db741ef4690000" ..
      "805ea997865e6b343a521ec10726ace3613ad1b251c66fccfd9563ba630a" ..
      "04e00001c70180500000ea4b3d73b6e9df1c02000000000a595a"
    },
  }

  for _, fixture in ipairs(archive_fixtures) do
    test.test("extracts a " .. fixture.extension .. " archive", function(context)
      local path = context.root .. PATHSEP .. "fixture." .. fixture.extension
      local contents = fixture.hex:gsub("..", function(byte)
        return string.char(tonumber(byte, 16))
      end)
      write(path, contents)
      local destination = context.root .. PATHSEP .. "extracted"
      ppm(context, { "extract", path, destination })
      test.equal(read(destination .. PATHSEP .. "payload.txt"),
        string.rep("ppm dependency upgrade archive smoke test\n", 8))
    end)
  end

  test.test("reports an invalid ZIP archive without crashing", function(context)
    local path = context.root .. PATHSEP .. "invalid.zip"
    write(path, "not a zip archive")
    local result = ppm(context, { "extract", path, context.root .. PATHSEP .. "extracted" },
      { failure = true })
    test.contains(result.error, "can't open zip archive")
    test.contains(result.error, "Not a zip archive")
  end)

  test.test("matches Pragtical's semantic plugin compatibility rules", function(context)
    local versions = {
      tostring(MOD_VERSION_MAJOR), MOD_VERSION_STRING,
      string.format("%d.%d.%d", MOD_VERSION_MAJOR, MOD_VERSION_MINOR, MOD_VERSION_PATCH + 1),
      string.format("%d.%d.0", MOD_VERSION_MAJOR, MOD_VERSION_MINOR + 1),
      string.format("%d.0.0", MOD_VERSION_MAJOR + 1),
      string.format("%d.0.0", MOD_VERSION_MAJOR - 1)
    }
    if MOD_VERSION_MINOR > 0 then
      table.insert(versions, string.format("%d.%d.%d",
        MOD_VERSION_MAJOR, MOD_VERSION_MINOR - 1, MOD_VERSION_PATCH + 10))
    end
    for i, version in ipairs(versions) do
      local id = "version_fixture_" .. i
      local path = "plugins/" .. id .. ".lua"
      write(context.repo .. PATHSEP .. path, "-- mod-version: " .. version .. "\nreturn {}\n")
      table.insert(context.manifest.addons, {
        id = id, version = "1.0", mod_version = version, path = path
      })
    end
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    for i, version in ipairs(versions) do
      local id = "version_fixture_" .. i
      local details = core.get_plugin_details(context.repo .. PATHSEP .. "plugins/" .. id .. ".lua")
      local status = details.version_match and "available" or "incompatible"
      addon(context, id, status)
      if details.version_match then
        ppm(context, { "install", id })
        addon(context, id, "installed")
      else
        test.contains(ppm(context, { "install", id }, { failure = true }).error, "can't find")
      end
    end
  end)

  local function check_install_restart(context, batch_install)
    for _, filename in ipairs({ "init.lua", "plugin_view.lua" }) do
      write(context.userdir .. PATHSEP .. "plugins/plugin_manager/" .. filename,
        read(context.cwd .. PATHSEP .. "plugins/plugin_manager/" .. filename))
    end
    write(context.userdir .. PATHSEP .. "init.lua", string.format([[
local config = require "core.config"
config.plugins.ipc = false
config.plugins.plugin_manager = { ppm_binary_path = %q, restart_on_change = true }
package.preload["libraries.json"] = function() error("legacy JSON module is unavailable") end
]], context.binary))
    write(context.userdir .. PATHSEP .. "session.lua",
      "return " .. common.serialize({ recents = { context.root } }))
    -- A non-embedded developer binary reads its source from the current directory.
    write(context.root .. PATHSEP .. "src/ppm.lua", read(context.cwd .. PATHSEP .. "src/ppm.lua"))
    local script = context.root .. PATHSEP .. "restart.lua"
    write(script, "local batch_install = " .. tostring(batch_install) .. "\n" .. [=[
local core = require "core"
local command = require "core.command"
local common = require "core.common"
local manager = require "plugins.plugin_manager"
local phase = USERDIR .. PATHSEP .. "installed-phase"
local restarted = system.get_file_info(phase) ~= nil
local function wait_for(predicate, message)
  local deadline = system.get_time() + 10
  while not predicate() do
    assert(system.get_time() < deadline, message)
    coroutine.yield(0.01)
  end
end
local function find_view()
  for _, view in ipairs(core.root_view.root_node:get_children()) do
    if view:is(manager.view) then return view end
  end
end
core.add_thread(function()
  local ok, err = xpcall(function()
    coroutine.yield(0.1)
    if not restarted then
      assert(command.perform("plugin-manager:show"))
      local view = assert(find_view(), "Plugin Manager did not open")
      wait_for(function() return view.initialized and not view.loading end, "initial listing stalled")
      if batch_install then
        for _, addon in ipairs(view:get_plugins()) do
          if addon.id == "minimap" and addon.status == "available" then view:set_checked(addon, true) end
        end
      end
      assert(command.perform("plugin-manager:filter"))
      view.search:set_text("editorconfig")
      view.category_box:set_selected(2)
      view.details_ratio = 0.35
      wait_for(function() return not view.loading end, "filtered listing stalled")
      assert(view.filter_text == "editorconfig", "filter command did not set the query")
      for i, addon in ipairs(view:get_sorted_plugins()) do
        if addon.id == "editorconfig" and addon.status == "available" then
          view:focus_plugin(addon)
          break
        end
      end
      assert(view.selected_plugin, "editorconfig is not available")
      if batch_install then view:set_checked(view.selected_plugin, true) end
      local file = assert(io.open(phase, "wb"))
      file:write(tostring(system.get_process_id()))
      file:close()
      if batch_install then
        -- Initialize geometry explicitly when the headless run has not drawn a frame.
        core.root_view.size.x, core.root_view.size.y = core.window:get_size()
        core.root_view.root_node:update_layout()
        core.root_view:update()
        core.root_view:update()
        local row
        for _, addon, item in view.list:each_item() do
          if addon == view.selected_plugin then row = item; break end
        end
        assert(row, "focused row is missing")
        local x = row.position.x + row.checkbox:get_width() + 40
        local y = row.position.y + row.size.y / 2
        core.root_view:on_mouse_moved(x, y, 0, 0)
        assert(view.hovered_plugin and view.hovered_plugin.id == "editorconfig",
          "mouse is not over the editorconfig row: " .. common.serialize({
            position = view.position, size = view.size, scroll = view.scroll,
            x = x, y = y,
            overlapping = core.root_view.overlapping_view
              and core.root_view.overlapping_view:get_name()
          }))
        core.root_view:on_mouse_pressed("left", x, y, 1)
        core.root_view:on_mouse_released("left", x, y)
        core.root_view:on_mouse_pressed("left", x, y, 2)
        core.root_view:on_mouse_released("left", x, y)
        coroutine.yield(0.05)
        assert(not core.restart_request, "double-click changed a plugin")
        assert(not system.get_file_info(USERDIR .. PATHSEP .. "plugins/editorconfig/init.lua"),
          "double-click installed editorconfig")
        assert(not row.checkbox.checked and not view.checked.editorconfig,
          "double-click did not clear the editorconfig checkmark")
        assert(#view:get_checked_plugins("install") == 1, "hidden checked plugin was lost")
        for _, clicks in ipairs({ 1, 2 }) do
          core.root_view:on_mouse_pressed("left", x, y, clicks)
          core.root_view:on_mouse_released("left", x, y)
        end
        assert(row.checkbox.checked and view.checked.editorconfig,
          "double-click did not restore the editorconfig checkmark")
        assert(#view:get_checked_plugins("install") == 2, "hidden checked plugin was lost")
        local button = view.batch_buttons.install
        core.root_view:update()
        x, y = button.position.x + button.size.x / 2, button.position.y + button.size.y / 2
        core.root_view:on_mouse_moved(x, y, 0, 0)
        core.root_view:on_mouse_pressed("left", x, y, 1)
        core.root_view:on_mouse_released("left", x, y)
        assert(view.loading, "batch button did not start installation")
      else
        assert(command.perform("plugin-manager:install-selected"))
      end
      wait_for(function() return core.restart_request end, "installation did not restart the editor")
    else
      assert(RESTARTED, "installation did not create a new editor runtime")
      local file = assert(io.open(phase, "rb"))
      local pid = file:read("*a")
      file:close()
      assert(pid == tostring(system.get_process_id()), "installation did not perform a soft restart")
      assert(system.get_file_info(USERDIR .. PATHSEP .. "plugins/editorconfig/init.lua"),
        "editorconfig was not installed")
      if batch_install then
        assert(system.get_file_info(USERDIR .. PATHSEP .. "plugins/minimap.lua"), "minimap was not installed")
      end
      wait_for(find_view, "Plugin Manager was not restored after restart")
      local view = find_view()
      wait_for(function() return view.initialized and not view.loading end, "restored listing stalled")
      assert(view.filter_text == "editorconfig",
        "filter was not restored: " .. tostring(view.filter_text))
      assert(#view:get_sorted_plugins() == 1, "restored listing is not filtered")
      assert(view:get_sorted_plugins()[1].id == "editorconfig", "wrong restored addon")
      assert(view.search:get_text() == "editorconfig", "search control is not restored")
      assert(view.category == "type:plugin", "category is not restored")
      assert(view.details_ratio == 0.35, "details pane size is not restored")
      assert(#view:get_checked_plugins() == 0, "completed selections survived the restart")
      print("EDITORCONFIG RESTART FILTER OK")
      core.quit(true, 0)
    end
  end, debug.traceback)
  if not ok then
    print(err)
    local storage = require "core.storage"
    for _, key in ipairs(storage.keys("ws")) do
      print("WORKSPACE " .. key .. " " .. common.serialize(storage.load("ws", key)))
    end
    for _, item in ipairs(core.log_items) do
      if item.level == "ERROR" then print("LOG " .. tostring(item.text)) end
    end
    core.quit(true, 1)
  end
end)
]=])
    local code, stdout, stderr = execute(context, { EXEFILE, "run", "-n", script }, {
      PRAGTICAL_USERDIR = context.userdir,
      PRAGTICAL_RENDERER = "surface",
      SDL_VIDEO_DRIVER = "dummy", SDL_AUDIO_DRIVER = "dummy",
      PPM_CACHE = context.root .. PATHSEP .. "cache",
      PPM_CONFIG = context.root .. PATHSEP .. "config",
      PPM_TMPDIR = context.root .. PATHSEP .. "tmp",
      PPM_BOTTLEDIR = context.root .. PATHSEP .. "bottles"
    })
    test.equal(code, 0, stdout .. "\n" .. stderr)
    test.contains(stdout, "EDITORCONFIG RESTART FILTER OK")
  end

  test.test("restores the editorconfig filter after install and soft restart", function(context)
    check_install_restart(context, false)
  end)

  test.test("batch install button preserves filters and clears selections after one soft restart", function(context)
    check_install_restart(context, true)
  end)
end)
