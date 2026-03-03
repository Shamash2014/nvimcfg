local M = {}

local LAST_MODEL_PATH = vim.fn.stdpath("data") .. "/ai_repl_opencode_model"

function M.list_models()
  local result = vim.fn.systemlist({ "opencode", "models" })
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local models = {}
  for _, line in ipairs(result) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed and trimmed ~= "" then
      local provider = trimmed:match("^([^/]+)/")
      table.insert(models, {
        id = trimmed,
        provider = provider or "unknown",
      })
    end
  end

  table.sort(models, function(a, b)
    return a.id < b.id
  end)

  return models
end

function M.build_args(model_id)
  if not model_id or model_id == "" then
    return {}
  end
  return { "-m", model_id }
end

function M.get_last_model()
  local f = io.open(LAST_MODEL_PATH, "r")
  if f then
    local model = f:read("*l")
    f:close()
    return model ~= "" and model or nil
  end
  return nil
end

function M.set_last_model(model_id)
  local f = io.open(LAST_MODEL_PATH, "w")
  if f then
    f:write(model_id or "")
    f:close()
  end
end

function M.format_model_label(model)
  return model.id
end

return M
