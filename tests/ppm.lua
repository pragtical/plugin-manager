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

local function set_addon_version(context, id, version, suffix)
  for _, entry in ipairs(context.manifest.addons) do
    if entry.id == id then
      entry.version = version
      write(context.repo .. PATHSEP .. entry.path,
        "-- mod-version: " .. entry.mod_version .. "\nreturn {}\n" .. (suffix or ""))
    end
  end
  write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
end

local function receipt(context, id)
  local path = context.root .. PATHSEP .. "config/installations.json"
  if not system.get_file_info(path) then return end
  local ledger = json.decode(read(path))
  test.equal(ledger.schema_version, 1)
  for path, record in pairs(ledger.installations) do
    if record.id == id then return record, path, ledger end
  end
end

local function remove_receipts(context)
  for _, suffix in ipairs({ "", ".bak" }) do
    local path = context.root .. PATHSEP .. "config/installations.json" .. suffix
    if system.get_file_info(path) then test.ok(os.remove(path)) end
  end
end

local function git(context, ...)
  local code, stdout, stderr = execute(context, { "git", "-C", context.repo, ... })
  test.equal(code, 0, stderr)
  return stdout:gsub("%s+$", "")
end

local function commit_repository(context, label)
  git(context, "add", ".")
  git(context, "-c", "user.name=ppm tests", "-c", "user.email=ppm-tests@example.invalid",
    "-c", "commit.gpgsign=false", "commit", "-m", label)
  return git(context, "rev-parse", "HEAD")
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

  test.test("stages dependencies and merges selections without installing until apply", function(context)
    local token = ppm(context, { "stage", "new", "install", "lsp" }).token
    ppm(context, { "stage", token, "install", "editorconfig" })
    ppm(context, { "stage", token, "install", "unknown_fixture" }, { failure = true })
    test.is_nil(receipt(context, "widget"))
    test.is_nil(system.get_file_info(context.userdir .. "/plugins/lsp"))
    ppm(context, { "apply-pending", token })
    for _, id in ipairs { "widget", "lintplus", "lsp", "editorconfig" } do test.ok(receipt(context, id)) end

    token = ppm(context, { "stage", "new", "uninstall", "lsp" }).token
    write(context.userdir .. "/plugins/lsp/.local", "changed after staging")
    test.contains(ppm(context, { "apply-pending", token }, { failure = true }).error, "changed since staging")
    test.ok(receipt(context, "lintplus"))
    assert(os.remove(context.userdir .. "/plugins/lsp/.local"))
    ppm(context, { "apply-pending", token })
    test.is_nil(receipt(context, "widget"))
    test.is_nil(system.get_file_info(context.userdir .. "/plugins/lsp"))
    test.ok(receipt(context, "editorconfig"))
  end)

  test.test("queues and withdraws selections offline without preparing any files", function(context)
    assert(os.rename(context.repo, context.repo .. ".offline"))
    local offline = "--ssl-certs=" .. context.root .. "/missing-certs"
    local token = ppm(context, { "queue", "new", "install", "lsp:1.0", "editorconfig:1.0", offline }).token
    local dir = context.userdir .. "/ppm-updates/" .. token
    test.same(system.list_dir(dir), { "plan.json" })
    local result = ppm(context, { "queue", token, "undo", "lsp", offline })
    test.equal(result.pending["install:editorconfig:1.0"], "install")
    test.is_nil(result.pending["install:lsp:1.0"])
    test.same(system.list_dir(dir), { "plan.json" })
    assert(os.rename(context.repo .. ".offline", context.repo))
    test.equal(ppm(context, { "list", "editorconfig", "--pending=" .. token }).addons[1].pending_action, "install")
    ppm(context, { "apply-pending", token })
    test.ok(receipt(context, "editorconfig"))
    for _, id in ipairs { "lsp", "widget", "lintplus" } do test.is_nil(receipt(context, id)) end
  end)

  test.test("failed preparation keeps the live profile intact and the queue editable", function(context)
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "lsp" then
        entry.files = { { url = "https://example.invalid/server.zip", checksum = string.rep("0", 64) } }
      end
    end
    write(context.repo .. "/manifest.json", json.encode(context.manifest))
    local token = ppm(context, { "queue", "new", "install", "bracketmatch", "lsp" }).token
    local file = context.userdir .. "/ppm-updates/" .. token .. "/plan.json"
    local original = read(file)
    test.equal(ppm(context, { "apply-pending", token, "--no-network" }, { failure = true }).code, "prepare_failed")
    test.equal(read(file), original)
    test.is_nil(system.get_file_info(context.userdir .. "/plugins/bracketmatch.lua"))
    test.is_nil(receipt(context, "widget"))
    ppm(context, { "queue", token, "undo", "lsp" })
    ppm(context, { "apply-pending", token })
    test.ok(receipt(context, "bracketmatch"))
  end)

  test.test("retry applies the complete prepared selection without the catalog", function(context)
    ppm(context, { "install", "editorconfig", "bracketmatch" })
    set_addon_version(context, "bracketmatch", "2.0")
    set_addon_version(context, "editorconfig", "2.0")
    local token = ppm(context, { "queue", "new", "upgrade" }).token
    ppm(context, { "queue", token, "undo", "bracketmatch" })
    local dir = context.userdir .. "/ppm-updates/" .. token
    write(dir .. "/old/plugins", "block the backup move")
    ppm(context, { "apply-pending", token }, { failure = true })
    test.equal(json.decode(read(dir .. "/plan.json")).prepared, true)
    local published = read(dir .. "/plan.json")
    ppm(context, { "queue", token, "undo", "bracketmatch" })
    test.equal(read(dir .. "/plan.json"), published)
    test.equal(receipt(context, "editorconfig").version, "1.0")
    assert(os.remove(dir .. "/old/plugins"))
    assert(os.rename(context.repo, context.repo .. ".offline"))
    ppm(context, { "apply-pending", token, "--ssl-certs=" .. context.root .. "/missing-certs" })
    test.equal(receipt(context, "bracketmatch").version, "1.0")
    test.equal(receipt(context, "editorconfig").version, "2.0")
  end)

  test.test("an uninstall-only selection applies without setting up TLS", function(context)
    ppm(context, { "install", "lsp" })
    local token = ppm(context, { "queue", "new", "uninstall", "lsp" }).token
    ppm(context, { "apply-pending", token, "--ssl-certs=" .. context.root .. "/missing-certs" })
    for _, id in ipairs { "lsp", "widget", "lintplus" } do test.is_nil(receipt(context, id)) end
  end)

  test.test("a conflicting install and uninstall cannot partially apply", function(context)
    ppm(context, { "install", "widget" })
    local token = ppm(context, { "queue", "new", "uninstall", "widget" }).token
    ppm(context, { "queue", token, "install", "lsp" })
    local failure = ppm(context, { "apply-pending", token }, { failure = true })
    test.equal(failure.code, "prepare_failed")
    test.contains(failure.error, "another queued plugin requires it")
    test.ok(receipt(context, "widget"))
    test.is_nil(receipt(context, "lsp"))
    ppm(context, { "queue", token, "undo", "widget" })
    ppm(context, { "apply-pending", token })
    test.ok(receipt(context, "widget"))
    test.ok(receipt(context, "lsp"))
  end)

  test.test("appending preserves prepared payloads and does not replay downloads", function(context)
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "gitblame" then entry.dependencies = { widget = {} } end
    end
    write(context.repo .. "/manifest.json", json.encode(context.manifest))
    local token = ppm(context, { "stage", "new", "install", "lsp:1.0" }).token
    local file = context.userdir .. "/ppm-updates/" .. token .. "/plan.json"
    local first = json.decode(read(file))
    -- The originally selected version is no longer in the catalog.
    set_addon_version(context, "lsp", "2.0", "-- replacement")
    local result = ppm(context, { "stage", token, "install", "gitblame" })
    local second = json.decode(read(file))
    for rel, target in pairs(first.targets) do test.same(second.targets[rel], target) end
    for _, row in ipairs(ppm(context, { "list", "--pending=" .. token }).addons) do
      test.equal(row.pending_action, result.pending[row.pending_key] or result.pending[row.pending_source_key])
    end
    local published = read(file)
    -- Fail after writing a replacement for an already-published target.
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "minimap" then entry.dependencies = { missing_fixture = {} } end
    end
    write(context.repo .. "/manifest.json", json.encode(context.manifest))
    local failure = ppm(context, { "stage", token, "install", "lsp:2.0", "minimap" }, { failure = true })
    test.contains(failure.error, "missing_fixture")
    test.equal(read(file), published)
    ppm(context, { "apply-pending", token })
    test.equal(receipt(context, "lsp").version, "1.0")
    test.ok(receipt(context, "widget"))
    test.ok(receipt(context, "gitblame"))
  end)

  test.test("an earlier single-slot batch can append and apply a replacement", function(context)
    local token = ppm(context, { "stage", "new", "install", "bracketmatch", "minimap" }).token
    local file = context.userdir .. "/ppm-updates/" .. token .. "/plan.json"
    local old = json.decode(read(file))
    old.schema, old.slot = 1, "a"
    for _, target in pairs(old.targets) do target.slot = nil end
    write(file, json.encode(old))
    set_addon_version(context, "minimap", "2.0", "-- replacement")
    ppm(context, { "stage", token, "install", "minimap:2.0" })
    local plan = json.decode(read(file))
    test.equal(plan.targets["plugins/bracketmatch.lua"].slot, "a")
    test.equal(plan.targets["plugins/minimap.lua"].slot, "b")
    ppm(context, { "apply-pending", token })
    test.equal(receipt(context, "bracketmatch").version, "1.0")
    test.equal(receipt(context, "minimap").version, "2.0")
  end)

  test.test("apply still rejects a damaged reused payload before touching live files", function(context)
    local token = ppm(context, { "stage", "new", "install", "editorconfig" }).token
    local dir = context.userdir .. "/ppm-updates/" .. token
    local plan = json.decode(read(dir .. "/plan.json"))
    write(dir .. "/" .. plan.targets["plugins/editorconfig"].slot .. "/plugins/editorconfig/init.lua", "damaged")
    ppm(context, { "stage", token, "install", "bracketmatch" })
    local failure = ppm(context, { "apply-pending", token }, { failure = true })
    test.contains(failure.error, "damaged staged addon")
    test.is_nil(system.get_file_info(context.userdir .. "/plugins/bracketmatch.lua"))
    test.is_nil(receipt(context, "editorconfig"))
  end)

  test.test("stages a repository-root addon with a deep source path", function(context)
    local repo = context.root .. PATHSEP .. "standalone"
    local dir = "subprojects" .. PATHSEP .. "packagefiles"
    local leaf = string.rep("x", math.max(1, 247 - #repo - #dir - 6)) .. ".lib"
    local rel = dir .. PATHSEP .. leaf
    write(repo .. PATHSEP .. rel, "nested asset")
    write(repo .. "/manifest.json", json.encode({ addons = {
      { id = "root_fixture", path = ".", version = "1.0" }
    } }))
    ppm(context, { "repo", "add", repo })
    if PLATFORM == "Windows" then
      ppm(context, { "exec", "assert(assert(system.stat(arg[1])).abs_path == assert(system.stat(arg[2])).abs_path)",
        repo .. PATHSEP .. rel, repo .. PATHSEP .. PATHSEP .. rel })
    end
    local token = ppm(context, { "stage", "new", "install", "root_fixture" }).token
    ppm(context, { "apply-pending", token })
    test.equal(read(context.userdir .. "/plugins/root_fixture/" .. rel), "nested asset")
  end)

  test.test("lists and undoes individual staged changes without touching installed files", function(context)
    ppm(context, { "install", "minimap", "bracketmatch", "editorconfig" })
    for _, id in ipairs({ "minimap", "bracketmatch" }) do set_addon_version(context, id, "2.0", "-- new") end
    local token = ppm(context, { "stage", "new", "upgrade" }).token
    local function queued()
      local actions = {}
      for _, row in ipairs(ppm(context, { "list", "--pending=" .. token }).addons) do
        if row.pending_action then actions[row.id] = row.pending_action end
      end
      return actions
    end
    ppm(context, { "stage", token, "uninstall", "editorconfig" })
    ppm(context, { "stage", token, "install", "lsp", "gitblame" })
    local expected = { minimap = "upgrade", bracketmatch = "upgrade", editorconfig = "uninstall",
      lsp = "install", lintplus = "install", widget = "install", gitblame = "install" }
    test.same(queued(), expected)
    test.contains(ppm(context, { "stage", token, "undo", "widget" }, { failure = true }).error, "requires it")
    test.same(queued(), expected)
    for _, id in ipairs({ "bracketmatch", "editorconfig", "lsp" }) do ppm(context, { "stage", token, "undo", id }) end
    test.same(queued(), { minimap = "upgrade", gitblame = "install" })
    test.equal(receipt(context, "minimap").version, "1.0")
    test.is_nil(receipt(context, "gitblame"))
    ppm(context, { "apply-pending", token })
    test.equal(receipt(context, "bracketmatch").version, "1.0")
    test.equal(receipt(context, "minimap").version, "2.0")
    test.ok(receipt(context, "editorconfig"))
    test.ok(receipt(context, "gitblame"))
    test.same(queued(), {})
    token = ppm(context, { "stage", "new", "uninstall", "gitblame" }).token
    test.ok(ppm(context, { "stage", token, "undo", "gitblame" }).empty)
    test.same(queued(), {})
    test.contains(ppm(context, { "stage", token, "install", "lsp" }, { failure = true }).error, "batch is empty")
  end)

  test.test("undo edits the saved batch offline and preserves a shared dependency", function(context)
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "gitblame" then entry.dependencies = { widget = {} } end
    end
    write(context.repo .. "/manifest.json", json.encode(context.manifest))
    local token = ppm(context, { "stage", "new", "install", "lsp", "gitblame" }).token
    local path = context.userdir .. "/ppm-updates/" .. token .. "/plan.json"
    local original = read(path)
    local plan = json.decode(original)
    assert(os.rename(context.repo, context.repo .. ".offline"))
    local args = { "stage", token, "undo", "widget", "--ssl-certs=" .. context.root .. "/missing-cert" }
    test.contains(ppm(context, args, { failure = true }).error, "requires it")
    test.equal(read(path), original)
    args[4] = "lsp"
    test.same(ppm(context, args).removed, { "lintplus", "lsp" })
    local edited = json.decode(read(path))
    test.same(edited.targets["libraries/widget"], plan.targets["libraries/widget"])
    test.same(edited.targets["plugins/gitblame.lua"], plan.targets["plugins/gitblame.lua"])
    ppm(context, { "apply-pending", token })
    test.ok(receipt(context, "widget"))
    test.ok(receipt(context, "gitblame"))
    test.is_nil(receipt(context, "lsp"))
    test.is_nil(receipt(context, "lintplus"))
    -- Undoing one uninstall must likewise preserve the shared library for the restored consumer.
    assert(os.rename(context.repo .. ".offline", context.repo))
    ppm(context, { "install", "lsp" })
    token = ppm(context, { "stage", "new", "uninstall", "lsp", "gitblame" }).token
    test.same(ppm(context, { "stage", token, "undo", "lsp" }).removed, { "lintplus", "lsp", "widget" })
    ppm(context, { "apply-pending", token })
    test.ok(receipt(context, "widget"))
    test.ok(receipt(context, "lsp"))
    test.is_nil(receipt(context, "gitblame"))
    local settings = json.decode(read(context.root .. "/config/settings.json"))
    test.contains(settings.installed, "lsp")
  end)

  test.test("offline undo keeps an upgrade required by the remaining plugin version", function(context)
    ppm(context, { "install", "encoding" })
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "encodings" then entry.dependencies.encoding.version = ">=2.0" end
    end
    set_addon_version(context, "encoding", "2.0", "-- new")
    local token = ppm(context, { "stage", "new", "upgrade" }).token
    ppm(context, { "stage", token, "install", "encodings" })
    assert(os.rename(context.repo, context.repo .. ".offline"))
    test.contains(ppm(context, { "stage", token, "undo", "encoding" }, { failure = true }).error, "requires it")
    test.same(ppm(context, { "stage", token, "undo", "encodings" }).removed, { "encodings" })
    ppm(context, { "apply-pending", token })
    test.equal(receipt(context, "encoding").version, "2.0")
    test.is_nil(receipt(context, "encodings"))
  end)

  test.test("stages, replaces and removes an addon beyond MAX_PATH", function(context)
    while #context.userdir < 190 do context.userdir = context.userdir .. PATHSEP .. "portable-profile" end
    local rel = "plugins/editorconfig/runtime/" .. string.rep("x", 55) .. ".lib"
    test.ok(#context.userdir + #rel > 260)
    write(context.repo .. "/" .. rel, "old")
    local entry
    for _, addon in ipairs(context.manifest.addons) do
      if addon.id == "editorconfig" then entry = addon; break end
    end
    entry.path = "plugins/editorconfig"
    write(context.repo .. "/manifest.json", json.encode(context.manifest))
    ppm(context, { "install", "editorconfig" })
    entry.version = "2.0"
    write(context.repo .. "/manifest.json", json.encode(context.manifest))
    write(context.repo .. "/" .. rel, "new")
    local token = ppm(context, { "stage", "new", "install", "editorconfig" }).token
    local before = receipt(context, "editorconfig")
    ppm(context, { "apply-pending", token })
    local after = receipt(context, "editorconfig")
    test.equal(after.version, "2.0")
    local file = rel:sub(#"plugins/editorconfig/" + 1)
    test.ok(after.files[file] and before.files[file] ~= after.files[file])
    token = ppm(context, { "stage", "new", "uninstall", "editorconfig" }).token
    ppm(context, { "apply-pending", token })
    test.is_nil(receipt(context, "editorconfig"))
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

  test.test("reports a Windows file lock and preserves the batch for retry", function(context)
    test.skip_if(PLATFORM ~= "Windows", "requires Windows delete sharing")
    ppm(context, { "install", "bracketmatch" })
    local token = ppm(context, { "stage", "new", "uninstall", "bracketmatch" }).token
    local path = context.userdir .. "/plugins/bracketmatch.lua"
    local handle = assert(io.open(path, "rb"))
    local err = ppm(context, { "apply-pending", token }, { failure = true })
    handle:close()
    test.equal(err.code, "file_in_use")
    test.contains(err.error, "bracketmatch.lua")
    exists(path)
    test.ok(receipt(context, "bracketmatch"))
    ppm(context, { "apply-pending", token })
    test.is_nil(system.get_file_info(path))
    test.is_nil(receipt(context, "bracketmatch"))
  end)

  test.test("restores earlier addon moves if a later move fails", function(context)
    ppm(context, { "install", "lsp" })
    local token = ppm(context, { "stage", "new", "uninstall", "lsp" }).token
    -- The library sorts before plugins. Prevent only the later backup move.
    local blocked = context.userdir .. "/ppm-updates/" .. token .. "/old/plugins"
    write(blocked, "not a directory")
    ppm(context, { "apply-pending", token }, { failure = true })
    exists(context.userdir .. "/libraries/widget/init.lua")
    exists(context.userdir .. "/plugins/lsp/init.lua")
    test.ok(receipt(context, "widget"))
    assert(os.remove(blocked))
    ppm(context, { "discard-pending", token })
    exists(context.userdir .. "/plugins/lintplus/init.lua")
  end)

  test.test("streams byte counts with or without a download size", function(context)
    local fixture = context.root .. "/progress.lua"
    write(fixture, [[
      local now = 0
      system.time = function() now = now + 1; return now end
      write_progress_bar(1024, 3072)
      write_progress_bar(2048, 3072)
      write_progress_bar(true)
      write_progress_bar(1024)
      write_progress_bar(2048)
      write_progress_bar(true)
      write_progress_bar(2048, 4, 0, 1)
    ]])
    local code, stdout, stderr = execute(context, { context.binary, "exec", fixture,
      "--json", "--progress", "--quiet", "--no-network", "--cachedir=" .. context.root .. "/cache" })
    test.equal(code, 0, stderr)
    local events = {}
    for line in stdout:gmatch("[^\r\n]+") do events[#events + 1] = json.decode(line).progress end
    test.equal(#events, 7)
    test.same(events[1], { percent = 0.333, detail = "1.0 KiB / 3.0 KiB" })
    test.equal(events[2].percent, 0.666)
    test.equal(events[3].percent, 1)
    test.same(events[4], { detail = "1.0 KiB" })
    test.same(events[5], { detail = "2.0 KiB" })
    test.equal(events[6].percent, 1)
    test.same(events[7], { percent = 0.25, detail = "2.0 KiB" })
  end)

  test.test("cold startup invokes the packaged handler and acknowledges ppm apply", function(context)
    local module = DATADIR .. "/core/transactions.lua"
    test.skip_if(not system.get_file_info(module), "editor does not support startup transactions")
    local dir = context.userdir .. "/plugins/plugin_manager"
    write(dir .. "/apply_updates.lua", read(context.cwd .. "/plugins/plugin_manager/apply_updates.lua"))
    if PLATFORM == "Windows" then write(dir .. "/ppm.exe", read(context.binary))
    else test.equal(execute(context, { "ln", "-s", context.binary, dir .. "/ppm.exe" }), 0) end
    local token = ppm(context, { "queue", "new", "install", "lsp" }).token
    local tx = assert(loadfile(module, "t", setmetatable({ USERDIR = context.userdir }, { __index = _G })))()
    local handler = "plugins.plugin_manager.apply_updates"
    test.ok(tx.register(handler, { title = "Apply plugin changes", payload = { name = "ppm.exe", token = token } }))
    local code, stdout, stderr = execute(context, { EXEFILE, "--version" }, {
      PRAGTICAL_USERDIR = context.userdir, PPM_CONFIG = context.root .. "/config",
      PPM_CACHE = context.root .. "/cache", SDL_VIDEO_DRIVER = "dummy", PRAGTICAL_RENDERER = "surface"
    })
    test.equal(code, 0, stderr .. stdout)
    test.contains(stdout, "Applying plugins/lsp")
    test.is_nil(tx.get(handler))
    exists(context.userdir .. "/plugins/lsp/init.lua")
    test.ok(receipt(context, "lsp"))
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

  test.test("bundled Lua ignores checkout line endings but not source changes", function(context)
    table.insert(context.manifest.addons, {
      id = "monokai", type = "color", path = "colors/monokai.lua", version = "0.3"
    })
    write(context.repo .. "/manifest.json", json.encode(context.manifest))
    for _, fixture in ipairs {
      { "monokai", "colors/monokai.lua", "\n", "\r\n" },
      { "language_ts", "plugins/language_ts.lua", "\r\n", "\n" },
    } do
      local id, path, repo_eol, bundled_eol = table.unpack(fixture)
      local source = "-- mod-version: " .. MOD_VERSION_STRING .. "\nreturn {}\n"
      write(context.repo .. "/" .. path, (source:gsub("\n", repo_eol)))
      local bundled = context.datadir .. "/" .. path
      write(bundled, (source:gsub("\n", bundled_eol)))
      local rows = ppm(context, { "list", id }).addons
      test.equal(#rows, 1, id)
      test.equal(rows[1].status, "bundled")
      write(bundled, read(bundled) .. "-- different source")
      addon(context, id, "available")
    end
  end)

  test.test("bundled directories still compare non-Lua assets byte for byte", function(context)
    local path = "plugins/language_pack"
    table.insert(context.manifest.addons, { id = "language_pack", path = path })
    write(context.repo .. "/manifest.json", json.encode(context.manifest))
    for _, root in ipairs { context.repo, context.datadir } do
      write(root .. "/" .. path .. "/init.lua", "return {}" .. (root == context.repo and "\n" or "\r\n"))
      write(root .. "/" .. path .. "/parser.bin", "\0A\nB")
    end
    local rows = ppm(context, { "list", "language_pack" }).addons
    test.equal(#rows, 1)
    test.equal(rows[1].status, "bundled")
    write(context.datadir .. "/" .. path .. "/parser.bin", "\0A\r\nB")
    addon(context, "language_pack", "available")
  end)

  test.test("reinstalls a modified singleton", function(context)
    ppm(context, { "install", "bracketmatch" })
    local installed = addon(context, "bracketmatch", "installed")
    write(installed.path, read(installed.path) .. "-- changed checksum\n")
    addon(context, "bracketmatch", "modified")
    addon(context, "bracketmatch", "available")
    test.contains(ppm(context, { "install", "bracketmatch" }, { failure = true }).error, "protected")
    ppm(context, { "install", "bracketmatch", "--reinstall" })
    addon(context, "bracketmatch", "installed")
    test.equal(read(installed.path), read(context.repo .. PATHSEP .. "plugins/bracketmatch.lua"))
  end)

  test.test("preserves real pre-1.0 versions across repository updates", function(context)
    set_addon_version(context, "bracketmatch", "0.3")
    ppm(context, { "install", "bracketmatch" })
    test.equal(receipt(context, "bracketmatch").version, "0.3")
    local installed = addon(context, "bracketmatch", "installed")
    local original = read(installed.path)
    set_addon_version(context, "bracketmatch", "0.4", "-- updated upstream\n")
    ppm(context, { "repo", "update" })
    local updating = addon(context, "bracketmatch", "upgradable")
    test.equal(updating.version, "0.3")
    test.equal(updating.installed_version, "0.3")
    test.equal(updating.available_version, "0.4")
    test.equal(updating.version_display, "0.3 -> 0.4")
    test.equal(read(installed.path), original)
    ppm(context, { "upgrade" })
    test.equal(addon(context, "bracketmatch", "installed").version, "0.4")
    test.equal(receipt(context, "bracketmatch").version, "0.4")
    ppm(context, { "uninstall", "bracketmatch" })
    test.is_nil(receipt(context, "bracketmatch"))
  end)

  test.test("recovers a legacy pre-1.0 installation from cached Git history offline", function(context)
    git(context, "init", "--initial-branch=master")
    set_addon_version(context, "bracketmatch", "0.3")
    local old = commit_repository(context, "Old addon")
    ppm(context, { "install", "bracketmatch" })
    set_addon_version(context, "bracketmatch", "0.4", "-- updated upstream\n")
    local head = commit_repository(context, "New addon")
    remove_receipts(context)
    local updating = addon(context, "bracketmatch", "upgradable")
    test.equal(updating.version, "0.3")
    test.equal(updating.available_version, "0.4")
    test.equal(receipt(context, "bracketmatch").commit, old)
    test.equal(git(context, "rev-parse", "HEAD"), head)
    ppm(context, { "upgrade", "--no-network" })
    test.equal(addon(context, "bracketmatch", "installed").version, "0.4")
  end)

  test.test("protects legacy unknown copies even when assume-yes or force is used", function(context)
    local path = context.userdir .. PATHSEP .. "plugins/bracketmatch.lua"
    local custom = "-- mod-version: " .. MOD_VERSION_STRING .. "\nreturn { local_copy = true }\n"
    write(path, custom)
    local local_copy = addon(context, "bracketmatch", "local")
    test.is_nil(local_copy.version)
    test.equal(local_copy.version_display, "unknown")
    test.equal(local_copy.protected, true)
    ppm(context, { "upgrade" })
    test.equal(read(path), custom)
    test.contains(ppm(context, { "install", "bracketmatch", "--force" }, { failure = true }).error, "protected")
    ppm(context, { "install", "bracketmatch", "--reinstall" })
    addon(context, "bracketmatch", "installed")
  end)

  test.test("does not guess versions when cached history is ambiguous", function(context)
    git(context, "init", "--initial-branch=master")
    set_addon_version(context, "bracketmatch", "0.2")
    commit_repository(context, "First version")
    set_addon_version(context, "bracketmatch", "0.3")
    commit_repository(context, "Identical payload with another version")
    ppm(context, { "install", "bracketmatch" })
    remove_receipts(context)
    set_addon_version(context, "bracketmatch", "0.4", "-- new payload\n")
    commit_repository(context, "Latest version")
    local entry = addon(context, "bracketmatch", "local")
    test.is_nil(entry.version)
    test.equal(entry.protected, true)
    test.is_nil(receipt(context, "bracketmatch"))
  end)

  test.test("protects old copies when rewritten history cannot identify them", function(context)
    git(context, "init", "--initial-branch=master")
    set_addon_version(context, "bracketmatch", "0.3")
    commit_repository(context, "Old version")
    ppm(context, { "install", "bracketmatch" })
    remove_receipts(context)
    git(context, "checkout", "--orphan", "rewritten")
    set_addon_version(context, "bracketmatch", "0.4", "-- rewritten payload\n")
    commit_repository(context, "New root")
    local old = read(context.userdir .. PATHSEP .. "plugins/bracketmatch.lua")
    addon(context, "bracketmatch", "local")
    ppm(context, { "upgrade", "--no-network" })
    test.equal(read(context.userdir .. PATHSEP .. "plugins/bracketmatch.lua"), old)
  end)

  test.test("backfills legacy receipts before fetching remote repository changes", function(context)
    git(context, "init", "--initial-branch=master")
    set_addon_version(context, "bracketmatch", "0.3")
    commit_repository(context, "Old version")
    ppm(context, { "repo", "rm", common.relative_path(context.cwd, context.repo) })
    ppm(context, { "repo", "add", "file://" .. context.repo .. ":master" })
    ppm(context, { "install", "bracketmatch" })
    remove_receipts(context)
    set_addon_version(context, "bracketmatch", "0.4", "-- new payload\n")
    commit_repository(context, "New version")
    ppm(context, { "update" })
    local updating = addon(context, "bracketmatch", "upgradable")
    test.equal(updating.version, "0.3")
    test.equal(updating.available_version, "0.4")
    test.equal(receipt(context, "bracketmatch").version, "0.3")
  end)

  test.test("requires all platform payloads before adopting legacy installations", function(context)
    local path = context.userdir .. PATHSEP .. "plugins/editorconfig/init.lua"
    write(path, read(context.repo .. PATHSEP .. "plugins/editorconfig/init.lua"))
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "editorconfig" then
        entry.files = { { url = "https://example.invalid/parser.so", checksum = string.rep("0", 64) } }
      end
    end
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    test.equal(addon(context, "editorconfig", "local").protected, true)
    test.is_nil(receipt(context, "editorconfig"))
  end)

  test.test("does not overwrite tracked modifications during bulk upgrades", function(context)
    ppm(context, { "install", "bracketmatch" })
    local path = addon(context, "bracketmatch", "installed").path
    local custom = read(path) .. "-- local modification\n"
    write(path, custom)
    set_addon_version(context, "bracketmatch", "1.1", "-- upstream update\n")
    local modified = addon(context, "bracketmatch", "modified")
    test.equal(modified.version, "1.0")
    test.equal(modified.available_version, "1.1")
    ppm(context, { "upgrade" })
    test.equal(read(path), custom)
    test.equal(receipt(context, "bracketmatch").version, "1.0")
    ppm(context, { "reinstall", "bracketmatch" })
    test.equal(addon(context, "bracketmatch", "installed").version, "1.1")
  end)

  test.test("preserves modified dependencies during automatic uninstall cleanup", function(context)
    ppm(context, { "install", "lsp" })
    local path = context.userdir .. PATHSEP .. "libraries/widget/init.lua"
    local custom = read(path) .. "-- custom dependency\n"
    write(path, custom)
    ppm(context, { "uninstall", "lsp" })
    test.equal(read(path), custom)
    addon(context, "widget", "modified")
    ppm(context, { "uninstall", "widget" })
    test.is_nil(system.get_file_info(path))
  end)

  test.test("distinguishes missing repositories from unknown and modified copies", function(context)
    set_addon_version(context, "bracketmatch", "0.3")
    ppm(context, { "install", "bracketmatch" })
    ppm(context, { "repo", "rm", common.relative_path(context.cwd, context.repo) })
    local orphan = addon(context, "bracketmatch", "orphan")
    test.equal(orphan.version, "0.3")
    test.equal(orphan.protected, true)
    ppm(context, { "uninstall", "bracketmatch" })
  end)

  test.test("does not downgrade newer installed versions", function(context)
    set_addon_version(context, "bracketmatch", "0.5")
    ppm(context, { "install", "bracketmatch" })
    set_addon_version(context, "bracketmatch", "0.4", "-- older repository contents\n")
    ppm(context, { "upgrade" })
    test.equal(addon(context, "bracketmatch", "installed").version, "0.5")
    test.equal(receipt(context, "bracketmatch").version, "0.5")
  end)

  test.test("recognizes same-version updates without treating unrelated files as changes", function(context)
    ppm(context, { "install", "editorconfig" })
    local path = context.userdir .. PATHSEP .. "plugins/editorconfig"
    write(path .. PATHSEP .. "generated-cache", "runtime data\n")
    addon(context, "editorconfig", "installed")
    set_addon_version(context, "editorconfig", "1.0", "-- changed payload\n")
    local updating = addon(context, "editorconfig", "upgradable")
    test.equal(updating.version_display, "1.0 (update available)")
    ppm(context, { "upgrade" })
    addon(context, "editorconfig", "installed")
  end)

  test.test("detects removed payload files in same-version updates", function(context)
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "editorconfig" then entry.path = "plugins/editorconfig" end
    end
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    local extra = context.repo .. PATHSEP .. "plugins/editorconfig/extra.lua"
    write(extra, "return {}\n")
    ppm(context, { "install", "editorconfig" })
    test.ok(os.remove(extra))
    addon(context, "editorconfig", "upgradable")
    ppm(context, { "upgrade" })
    addon(context, "editorconfig", "installed")
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "plugins/editorconfig/extra.lua"))
  end)

  test.test("detects dependency changes without a version bump", function(context)
    ppm(context, { "install", "editorconfig" })
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "editorconfig" then entry.dependencies = { encoding = {} } end
    end
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    addon(context, "editorconfig", "upgradable")
    ppm(context, { "upgrade" })
    addon(context, "editorconfig", "installed")
    addon(context, "encoding", "installed")
  end)

  test.test("failed downloads preserve installed files and their receipts", function(context)
    ppm(context, { "install", "editorconfig" })
    local path = context.userdir .. PATHSEP .. "plugins/editorconfig/init.lua"
    local contents = read(path)
    local record = receipt(context, "editorconfig")
    set_addon_version(context, "editorconfig", "1.1", "-- replacement\n")
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "editorconfig" then
        entry.files = { { url = "https://example.invalid/missing.bin", checksum = string.rep("0", 64) } }
      end
    end
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    ppm(context, { "upgrade", "--no-network" }, { failure = true })
    test.equal(read(path), contents)
    test.same(receipt(context, "editorconfig"), record)
    addon(context, "editorconfig", "upgradable")
  end)

  test.test("scopes installation receipts to profiles sharing a configuration directory", function(context)
    set_addon_version(context, "bracketmatch", "0.3")
    ppm(context, { "install", "bracketmatch" })
    local original_profile = context.userdir
    context.userdir = context.root .. PATHSEP .. "second-user"
    test.ok(common.mkdirp(context.userdir))
    set_addon_version(context, "bracketmatch", "0.4", "-- new version\n")
    ppm(context, { "install", "bracketmatch" })
    test.equal(addon(context, "bracketmatch", "installed").version, "0.4")
    context.userdir = original_profile
    test.equal(addon(context, "bracketmatch", "upgradable").version, "0.3")
    local ledger = json.decode(read(context.root .. PATHSEP .. "config/installations.json"))
    local count = 0
    for _, record in pairs(ledger.installations) do
      if record.id == "bracketmatch" then count = count + 1 end
    end
    test.equal(count, 2)
  end)

  test.test("records final bottle paths only after successful construction", function(context)
    ppm(context, { "bottle", "add", "tracked", "system", "bracketmatch" })
    local record, path = receipt(context, "bracketmatch")
    test.not_nil(record)
    test.contains(path, "/bottles/named/tracked/user/plugins/bracketmatch.lua")
    ppm(context, { "bottle", "rm", "tracked" })
    test.is_nil(receipt(context, "bracketmatch"))
  end)

  test.test("cache purges do not erase managed installation versions", function(context)
    set_addon_version(context, "bracketmatch", "0.3")
    ppm(context, { "install", "bracketmatch" })
    ppm(context, { "cache", "purge" })
    test.equal(receipt(context, "bracketmatch").version, "0.3")
    set_addon_version(context, "bracketmatch", "0.4", "-- new payload\n")
    test.equal(addon(context, "bracketmatch", "upgradable").version, "0.3")
  end)

  test.test("recovers the previous valid ledger after a corrupted write", function(context)
    ppm(context, { "install", "bracketmatch" })
    ppm(context, { "install", "editorconfig" })
    write(context.root .. PATHSEP .. "config/installations.json", "invalid JSON")
    test.equal(addon(context, "bracketmatch", "installed").version, "1.0")
  end)

  test.test("ignores malformed individual receipts without losing valid records", function(context)
    ppm(context, { "install", "bracketmatch", "editorconfig" })
    local _, _, ledger = receipt(context, "editorconfig")
    for _, record in pairs(ledger.installations) do
      if record.id == "bracketmatch" then record.metadata.version = {} end
    end
    write(context.root .. PATHSEP .. "config/installations.json", json.encode(ledger))
    addon(context, "editorconfig", "installed")
    addon(context, "bracketmatch", "installed")
    test.equal(receipt(context, "bracketmatch").version, "1.0")
  end)

  test.test("failed bottle construction does not publish staged receipts", function(context)
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "editorconfig" then
        entry.files = { { url = "https://example.invalid/missing.bin", checksum = string.rep("0", 64) } }
      end
    end
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    ppm(context, { "bottle", "dump", context.root .. PATHSEP .. "bottles/named/failed",
      "system", "bracketmatch", "editorconfig", "--no-network" }, { failure = true })
    test.is_nil(receipt(context, "bracketmatch"))
    test.is_nil(receipt(context, "editorconfig"))
    test.is_nil(system.get_file_info(context.root .. PATHSEP .. "bottles/named/failed"))
  end)

  test.test("unknown copies cannot satisfy constrained dependencies or be implicitly replaced", function(context)
    local path = context.userdir .. PATHSEP .. "plugins/bracketmatch.lua"
    local contents = "return { custom = true }\n"
    write(path, contents)
    for _, entry in ipairs(context.manifest.addons) do
      if entry.id == "editorconfig" then entry.dependencies = { bracketmatch = { version = ">=1.0" } } end
    end
    write(context.repo .. PATHSEP .. "manifest.json", json.encode(context.manifest))
    ppm(context, { "reinstall", "editorconfig" }, { failure = true })
    test.equal(read(path), contents)
    test.is_nil(system.get_file_info(context.userdir .. PATHSEP .. "plugins/editorconfig"))
  end)

  test.test("refuses mutations when the ledger and its backup are corrupted", function(context)
    ppm(context, { "install", "bracketmatch" })
    local path = context.userdir .. PATHSEP .. "plugins/bracketmatch.lua"
    local contents = read(path)
    write(context.root .. PATHSEP .. "config/installations.json", "invalid JSON")
    write(context.root .. PATHSEP .. "config/installations.json.bak", "invalid backup")
    ppm(context, { "uninstall", "bracketmatch" }, { failure = true })
    ppm(context, { "reinstall", "bracketmatch" }, { failure = true })
    test.equal(read(path), contents)
  end)

  test.test("reconciles a symlink whose repository payload has already changed", function(context)
    test.skip_if(PLATFORM == "Windows", "local symlinks require developer mode on Windows")
    set_addon_version(context, "bracketmatch", "0.3")
    ppm(context, { "install", "bracketmatch", "--symlink" })
    set_addon_version(context, "bracketmatch", "0.4", "-- new linked payload\n")
    test.equal(addon(context, "bracketmatch", "installed").version, "0.4")
    test.equal(receipt(context, "bracketmatch").version, "0.4")
    ppm(context, { "uninstall", "bracketmatch" })
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
        local plugin = core.get_plugin_details(root .. PATHSEP .. entry.path)
        test.equal(entry.mod_version, plugin.version_string)
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
