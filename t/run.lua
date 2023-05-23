local json = require "plugins.json"
local ppm
local function assert_exists(path) if not io.open(path, "rb")  then error("assertion failed: file " .. path .. " does not exist", 2) end end
local function assert_not_exists(path) if io.open(path, "rb") then error("assertion failed: file " .. path .. " exists", 2) end end
local tmpdir = os.getenv("TMPDIR") or "/tmp"
local fast = os.getenv("FAST")
local userdir = tmpdir .. "/ppmtest"
setmetatable(_G, { __index = function(t, k) if not rawget(t, k) then error("cannot get undefined global variable: " .. k, 2) end end, __newindex = function(t, k) error("cannot set global variable: " .. k, 2) end  })


local tests = {
  ["00_install_singleton"] = function()
    local plugins = ppm("list bracketmatch")["addons"]
    assert(#plugins == 1)
    assert(plugins[1].organization == "singleton")
    assert(plugins[1].status == "available")
    local actions = ppm("install bracketmatch")["actions"]
    assert(actions[1]:find("Installing singleton"))
    assert_exists(userdir .. "/plugins/bracketmatch.lua")
    actions = ppm("uninstall bracketmatch")["actions"]
    assert_not_exists(userdir .. "/plugins/bracketmatch.lua")
  end,
  ["01_upgrade_singleton"] = function()
    ppm("install bracketmatch")
    local plugins = ppm("list bracketmatch")["addons"]
    assert(#plugins == 1)
    assert(plugins[1].status == "installed")
    assert_exists(plugins[1].path)
    io.open(plugins[1].path, "ab"):write("-- this is a test comment to modify the checksum"):close()
    plugins = ppm("list bracketmatch")["addons"]
    assert(#plugins == 2)
    ppm("install bracketmatch")
    plugins = ppm("list bracketmatch")["addons"]
    assert(#plugins == 1)
    ppm("install console")
    assert_exists(userdir .. "/plugins/console/init.lua")
  end,
  ["02_install_complex"] = function()
    local plugins = ppm("list plugin_manager")["addons"]
    assert(#plugins == 1)
    assert(plugins[1].organization == "complex")
    assert(plugins[1].status == "available")
    assert(plugins[1].dependencies.json)
    local actions = ppm("install plugin_manager")["actions"]
    assert_exists(userdir .. "/libraries/json.lua")
    assert_exists(userdir .. "/plugins/plugin_manager")
    assert_exists(userdir .. "/plugins/plugin_manager/init.lua")
    actions = ppm("uninstall plugin_manager")["actions"]
    assert_not_exists(userdir .. "/plugins/plugin_manager")
    ppm("install editorconfig")
    assert_exists(userdir .. "/plugins/editorconfig")
    assert_exists(userdir .. "/plugins/editorconfig/init.lua")
  end,
  ["03_upgrade_complex"] = function()
    local actions = ppm("install plugin_manager")
    local plugins = ppm("list plugin_manager")["addons"]
    assert(#plugins == 1)
    assert(plugins[1].organization == "complex")
    assert(plugins[1].status == "installed")
  end,
  ["04_list_plugins"] = function()
    local plugins = ppm("list")["addons"]
    assert(#plugins > 20)
  end,
  ["05_install_url"] = function()
    local plugins = ppm("list eofnewline")["addons"]
    assert(#plugins == 1)
    assert(plugins[1].organization == "singleton")
    assert(plugins[1].status == "available")
    local actions = ppm("install eofnewline")
    assert_exists(userdir .. "/plugins/eofnewline.lua")
  end,
  ["06_install_stub"] = function()
    local plugins = ppm("list lsp")["addons"]
    assert(#plugins > 1)
    for i, plugin in ipairs(plugins) do
      if plugin.id == "lsp" then
        assert(plugins[1].organization == "complex")
        assert(plugins[1].status == "available")
        local actions = ppm("install lsp")
        assert_exists(userdir .. "/plugins/lsp/init.lua")
        assert_exists(userdir .. "/libraries/widget/init.lua")
        break
      end
    end
    local actions = ppm("install encodings")
    assert_exists(userdir .. "/plugins/encodings.lua")
    local stat = system.stat(userdir .. "/plugins/encodings.lua")
    assert(stat)
    assert(stat.type == "file")
    assert_exists(userdir .. "/libraries/encoding")
    stat = system.stat(userdir .. "/libraries/encoding")
    assert(stat)
    assert(stat.type == "dir")
  end,
  ["07_manifest"] = function()
   local results = json.decode(io.open("manifest.json", "rb"):read("*all"))
   assert(#results["remotes"] == 2)
   assert(#results["addons"] == 2)
  end,
  ["08_install_many"] = function()
    ppm("install encoding gitblame gitstatus language_ts lsp minimap")
  end,
  ["09_misc_commands"] = function()
    ppm("update")
    ppm("upgrade")
  end,
  ["10_install_multiarch"] = function()
    ppm("install plugin_manager --arch x86_64-windows --arch x86_64-linux")
    assert_exists(userdir .. "/plugins/plugin_manager/ppm.x86_64-linux")
    assert_exists(userdir .. "/plugins/plugin_manager/ppm.x86_64-windows.exe")
    assert_exists(userdir .. "/plugins/plugin_manager/init.lua")
  end,
  ["11_dependency_check"] = function()
    ppm("install lsp")
    assert_exists(userdir .. "/plugins/lsp")
    assert_exists(userdir .. "/plugins/lintplus")
    assert_exists(userdir .. "/plugins/settings.lua")
    ppm("uninstall lsp")
    assert_not_exists(userdir .. "/plugins/lsp")
    assert_not_exists(userdir .. "/plugins/lintplus")
    assert_not_exists(userdir .. "/plugins/settings.lua")
  end
}

local last_command_result, last_command
ppm = function(cmd)
  last_command = "./ppm --quiet --json --assume-yes --userdir=" .. userdir .. " " .. cmd
  local pipe = io.popen(last_command, "r")
  local result = pipe:read("*all")
  last_command_result = result ~= "" and json.decode(result) or nil
  local success = pipe:close()
  if not success then error("error calling ppm", 2) end
  return last_command_result
end

local function run_tests(tests, arg)
  local fail_count = 0
  local names = {}
  if #arg == 0 then
    for k,v in pairs(tests) do table.insert(names, k) end
  else
    names = arg
  end
  table.sort(names)
  local max_name = 0
  os.execute("rm -rf " .. tmpdir .. "/ppmtest && mkdir -p " .. tmpdir .. "/ppmtest");
  for i,k in ipairs(names) do max_name = math.max(max_name, #k) end
  for i,k in ipairs(names) do
    local v = tests[k]
    if fast then
      os.execute("rm -rf " .. tmpdir .. "/ppmtest/plugins && mkdir -p " .. tmpdir .. "/ppmtest");
    else
      os.execute("rm -rf " .. tmpdir .. "/ppmtest && mkdir -p " .. tmpdir .. "/ppmtest");
    end
    io.stdout:write(string.format("test %-" .. (max_name + 1) .. "s: ", k))
    local failed = false
    xpcall(v, function(err)
      print("[FAIL]: " .. debug.traceback(err, 2))
      if last_command then
        print("Last Command: " .. last_command)
        if last_command_result then
          print(json.encode(last_command_result))
        end
      end
      print()
      print()
      fail_count = fail_count + 1
      failed = true
    end)
    if not failed then
      print("[PASSED]")
    end
  end
  os.exit(fail_count)
end

run_tests(tests, arg)
