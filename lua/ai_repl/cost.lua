local M = {}

local PRICING = {
  ["claude-sonnet-4"] = { input = 3.0, output = 15.0 },
  ["claude-sonnet-4-20250514"] = { input = 3.0, output = 15.0 },
  ["claude-sonnet-3.5"] = { input = 3.0, output = 15.0 },
  ["claude-sonnet-3-5-sonnet-20241022"] = { input = 3.0, output = 15.0 },
  ["claude-opus-4"] = { input = 15.0, output = 75.0 },
  ["claude-opus-4-20250514"] = { input = 15.0, output = 75.0 },
  ["claude-haiku-3.5"] = { input = 0.80, output = 4.0 },
  ["claude-3-5-haiku-20241022"] = { input = 0.80, output = 4.0 },
  ["gpt-4o"] = { input = 2.50, output = 10.0 },
  ["gpt-4o-mini"] = { input = 0.15, output = 0.60 },
  ["gpt-4.1"] = { input = 2.0, output = 8.0 },
  ["gpt-4.1-mini"] = { input = 0.40, output = 1.60 },
  ["gpt-4.1-nano"] = { input = 0.10, output = 0.40 },
  ["o3"] = { input = 2.0, output = 8.0 },
  ["o3-mini"] = { input = 1.10, output = 4.40 },
  ["o4-mini"] = { input = 1.10, output = 4.40 },
  ["gemini-2.5-pro"] = { input = 1.25, output = 10.0 },
  ["gemini-2.5-flash"] = { input = 0.15, output = 0.60 },
  ["gemini-2.0-flash"] = { input = 0.10, output = 0.40 },
  ["deepseek-chat"] = { input = 0.27, output = 1.10 },
  ["deepseek-reasoner"] = { input = 0.55, output = 2.19 },
}

function M.find_pricing(model_id)
  if not model_id then return nil end
  if PRICING[model_id] then return PRICING[model_id] end
  for key, pricing in pairs(PRICING) do
    if model_id:find(key, 1, true) or key:find(model_id, 1, true) then
      return pricing
    end
  end
  return nil
end

function M.calculate(model_id, input_tokens, output_tokens)
  local pricing = M.find_pricing(model_id)
  if not pricing then return nil end
  local cost = (input_tokens * pricing.input + output_tokens * pricing.output) / 1e6
  return cost
end

function M.format(cost)
  if not cost then return nil end
  if cost < 0.01 then return string.format("$%.4f", cost) end
  if cost < 1.0 then return string.format("$%.2f", cost) end
  return string.format("$%.2f", cost)
end

return M
