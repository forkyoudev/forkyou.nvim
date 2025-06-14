local M = {}

local function hex_to_bytes(hex)
  return (hex:gsub('..', function(cc)
    return string.char(tonumber(cc, 16))
  end))
end

local function get_hmac_signature(message, key)
  local tmpfile = "/tmp/forkyou_payload.json"
  local f = io.open(tmpfile, "w")
  if f then
    f:write(message)
    f:close()
  else
    return nil
  end

  local cmd = string.format(
    'openssl dgst -sha256 -hmac "%s" -binary "%s" | xxd -p -c 256',
    key,
    tmpfile
  )

  return vim.trim(vim.fn.system(cmd))
end

local key = "a97a2ff02d16c0441ad150a6862352e643dd9c724efdbc85616afd3e6635cdaadd95d9c0b68b912b589781ffb58289a657785c51857479dc48a6860c0b025209548e536c83fce0d6971ab88cf1f90929c809dfa542ffdf5efe498db449e6c350e092eff61bb685ea6f850c509730f79601d864e1955afef42d3c5d5967a1eff4680fc300448c6a398059ff818a9a130c28f4401a7da97a0341032494f820b8b27fcca10893f8121df2c01c1bd25a6e179ace6ba4c1b3178728bd8b6c0aeffb776661ade293a2f503ea5a930b0f4c39f944a1b1a675f8ea7acaf9979a6c17f5c75e3385687caca8ccf1f6a5951b63ba1b7d14566b1bbfee73bac90909d2e3c979"
local raw_key = key

local config = {
  api_token = nil,
}

local activities = {}
local current = nil
local start_time = nil
local last_interaction = os.time()
local idle_timeout = 120

local function set_online(is_online, force)
  local token = config.api_token
  if not token then return end

  local body = vim.json.encode({ isOnline = is_online })

  local cmd = {
    "curl",
    "-s",
    "-X", "PUT",
    "https://forkyou.dev/api/user/status",
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. token,
    "-d", body,
  }

  if force then
    -- Synchronous call for shutdown
    vim.fn.system(cmd)
  else
    -- Background async call for normal usage
    vim.fn.jobstart(cmd, { on_exit = function() end })
  end
end

local function get_project()
  local cwd = vim.fn.getcwd()
  return vim.fn.fnamemodify(cwd, ":t")
end

local function count_line_changes(old_lines, new_lines)
  local added, removed = 0, 0
  local old_map = {}
  for _, line in ipairs(old_lines or {}) do
    old_map[line] = (old_map[line] or 0) + 1
  end

  for _, line in ipairs(new_lines or {}) do
    if old_map[line] then
      old_map[line] = old_map[line] - 1
    else
      added = added + 1
    end
  end

  for _, count in pairs(old_map) do
    if count > 0 then
      removed = removed + count
    end
  end

  return added, removed
end

local function flush_activity(_)
  if not current or not start_time then return end

  local now = os.time()
  local duration = now - start_time

  if duration > 0 then
    current.duration = duration
    local buf = vim.api.nvim_get_current_buf()
    local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local added, removed = count_line_changes(current.snapshot, new_lines)
    current.linesAdded = added
    current.linesRemoved = removed
    table.insert(activities, current)
  end

  current = nil
  start_time = nil
end

local function start_activity()
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then return end

  current = {
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    file = file,
    languageId = vim.bo[buf].filetype,
    project = get_project(),
    linesAdded = 0,
    linesRemoved = 0,
    duration = 0,
    snapshot = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
  }

  start_time = os.time()
  last_interaction = os.time()
end

local function sync(force)
  if #activities == 0 then return end

  local token = config.api_token
  if not token then return end

  local sanitized = {}
  for _, act in ipairs(activities) do
    local copy = vim.tbl_deep_extend("force", {}, act)
    copy.snapshot = nil
    table.insert(sanitized, copy)
  end

  local body = vim.json.encode(sanitized)
  activities = {}

  local hmac_hex = get_hmac_signature(body, raw_key)
  if not hmac_hex then return end

  local curl_cmd = {
    "curl",
    "-s",
    "-X", "POST",
    "https://forkyou.dev/api/activities/sync",
    "-H", "Content-Type: application/json",
    "-H", "Authorization: Bearer " .. token,
    "-H", "X-Signature: " .. hmac_hex,
    "-d", body,
  }

  if force then
    vim.fn.system(curl_cmd) -- silent sync on exit
  else
    vim.fn.jobstart(curl_cmd, { on_exit = function() end })
  end
end

local function check_idle()
  if not start_time then return end
  if os.difftime(os.time(), last_interaction) > idle_timeout then
    flush_activity("idle timeout")
  end
end

function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, user_config or {})
  if not config.api_token then
    vim.notify("Forkyou: Missing api_token in setup()", vim.log.levels.ERROR)
    return
  end

  set_online(true)

  vim.api.nvim_create_autocmd({ "BufWritePost", "TextChanged", "InsertLeave", "CursorMoved", "CursorMovedI" }, {
    callback = function()
      last_interaction = os.time()
      if not current then
        start_activity()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    callback = function()
      flush_activity("buffer leave")
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      flush_activity("vim leave")
      sync(true)
      set_online(false, true)
    end,
  })

  vim.defer_fn(function()
    vim.fn.timer_start(60000, function()
      sync()
    end, { ["repeat"] = -1 })
    vim.fn.timer_start(10000, function()
      check_idle()
    end, { ["repeat"] = -1 })
  end, 1000)
end

return M