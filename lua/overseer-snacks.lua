local M = {}

-- Function to get all available templates
function M.get_templates()
  local overseer = require("overseer")
  local ok, result = pcall(function()
    -- Try different ways to get templates
    if overseer.list_templates then
      return overseer.list_templates()
    elseif overseer.get_templates then
      return overseer.get_templates()
    else
      -- Fallback: trigger overseer run to get templates
      local templates = {}
      vim.ui.select = function(items, opts, on_choice)
        -- Intercept the select call to get templates
        templates = items
        on_choice(nil) -- Cancel the selection
      end
      
      -- This will trigger the template selection
      pcall(vim.cmd, "OverseerRun")
      
      -- Restore original vim.ui.select
      vim.ui.select = require("snacks").picker.ui_select
      
      return templates
    end
  end)
  
  if ok then
    return result or {}
  else
    return {}
  end
end

-- Function to run task picker with snacks
function M.run_task_picker()
  local templates = M.get_templates()
  
  if #templates == 0 then
    vim.notify("No overseer templates found", vim.log.levels.WARN)
    vim.cmd("OverseerRun") -- Fallback to default
    return
  end
  
  local items = {}
  for _, template in ipairs(templates) do
    local name = type(template) == "string" and template or template.name or tostring(template)
    table.insert(items, {
      text = name,
      template = template,
    })
  end
  
  Snacks.picker.pick({
    items = items,
    prompt = "Run task:",
    preview = { enabled = false },
    layout = "vscode",
    on_select = function(choice)
      if choice and choice.template then
        local overseer = require("overseer")
        if type(choice.template) == "string" then
          -- If it's just a string, run the command directly
          overseer.run_template({ name = choice.template })
        else
          overseer.run_template(choice.template)
        end
      end
    end
  })
end

return M