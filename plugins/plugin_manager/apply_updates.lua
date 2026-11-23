-- Loaded directly by core.transactions, before plugin initialization.
return function(_, payload, ctx)
  local json = require "core.json"

  if type(payload) ~= "table"
    or type(payload.token) ~= "string"
    or #payload.token ~= 64
    or not payload.token:match("^%x+$")
    or (payload.name ~= "ppm." .. ARCH .. ".exe" and payload.name ~= "ppm.exe")
  then
    return nil, { message = "Invalid Plugin Manager startup request" }
  end

  local root = payload.bundled and DATADIR or USERDIR
  local argv = {
    root .. PATHSEP .. "plugins" .. PATHSEP .. "plugin_manager" .. PATHSEP .. payload.name,
    "apply-pending", payload.token,
    "--userdir=" .. USERDIR, "--datadir=" .. DATADIR,
    "--binary=" .. EXEFILE, "--mod-version=" .. MOD_VERSION_STRING,
    "--assume-yes", "--json", "--quiet", "--progress"
  }

  if payload.cachedir then argv[#argv + 1] = "--cachedir=" .. payload.cachedir end
  if payload.ssl_certs then argv[#argv + 1] = "--ssl-certs=" .. payload.ssl_certs end
  if payload.force then argv[#argv + 1] = "--force" end

  ctx:progress("Processing queued plugin changes")
  local proc, err = process.start(argv, { stderr = process.REDIRECT_STDOUT })
  if not proc then return nil, { message = tostring(err) } end

  -- ppm writes one JSON message per line; a read may stop halfway through one.
  local buffer, message, code = "", nil, nil
  repeat
    local chunk = proc:read_stdout(8192)
    buffer = buffer .. (chunk or "")

    while buffer:find("\n", 1, true) do
      local line, rest = buffer:match("^([^\n]*)\n(.*)$")
      buffer = rest

      local ok, value = pcall(json.decode, line)
      if ok and type(value) == "table" and value.progress then
        ctx:progress(
          value.progress.label,
          value.progress.percent,
          value.progress.detail
        )
      elseif ok and type(value) == "table" and value.error then
        message, code = value.error, value.code
      elseif not message then
        message = line
      end
    end

    if (not chunk or chunk == "") and proc:running() then
      system.sleep(0.01)
      ctx:yield()
    end
  until not chunk and not proc:running()

  if proc:returncode() == 0 then return true end

  -- A remaining "applying" marker means it is unsafe to retry automatically.
  local recovery = system.get_file_info(
    USERDIR .. "/ppm-updates/" .. payload.token .. "/applying"
  ) ~= nil

  if code == "prepare_failed" and not recovery then
    return nil, {
      retry = true,
      message = message ..
        "\nNo plugin changes were applied. Edit or cancel the selection in Plugin Manager, or reopen Pragtical to retry."
    }
  end

  if code == "file_in_use" and not recovery then
    return nil, {
      retry = true,
      message = message ..
        "\nAnother Pragtical instance, language server, or media player may still be using this file." ..
        "\nClose the program using it, quit all Pragtical instances, then reopen Pragtical." ..
        "\nYour update is still queued and will retry automatically on the next full launch."
    }
  end

  return nil, {
    message = message
      or (buffer ~= "" and buffer)
      or "ppm could not apply the staged changes",
    recovery_required = recovery
  }
end
