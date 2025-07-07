local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- Function declaration
  s("fn", fmt([[
function {}({}) {{
  {}
}}
]], { i(1, "name"), i(2, "args"), i(3, "// body") })),

  -- Arrow function
  s("af", fmt("const {} = ({}) => {}", { i(1, "name"), i(2, "args"), i(3, "{}") })),

  -- Async function
  s("afn", fmt([[
async function {}({}) {{
  {}
}}
]], { i(1, "name"), i(2, "args"), i(3, "// body") })),

  -- Console log
  s("cl", fmt("console.log('{}:', {})", { i(1, "debug"), i(2, "variable") })),

  -- If statement
  s("if", fmt([[
if ({}) {{
  {}
}}
]], { i(1, "condition"), i(2, "// body") })),

  -- For loop
  s("for", fmt([[
for (let {} = {}; {} < {}; {}++) {{
  {}
}}
]], { i(1, "i"), i(2, "0"), i(3, "i"), i(4, "length"), i(5, "i"), i(6, "// body") })),

  -- For of loop
  s("fof", fmt([[
for (const {} of {}) {{
  {}
}}
]], { i(1, "item"), i(2, "array"), i(3, "// body") })),

  -- Try catch
  s("try", fmt([[
try {{
  {}
}} catch (error) {{
  {}
}}
]], { i(1, "// try block"), i(2, "console.error(error)") })),

  -- Import statement
  s("imp", fmt("import {} from '{}'", { i(1, "module"), i(2, "path") })),

  -- Export default
  s("exp", fmt("export default {}", { i(1, "value") })),

  -- React component
  s("rfc", fmt([[
import React from 'react'

const {} = ({}) => {{
  return (
    <div>
      {}
    </div>
  )
}}

export default {}
]], { i(1, "ComponentName"), i(2, "props"), i(3, "// content"), i(4, "ComponentName") })),

  -- useState hook
  s("us", fmt("const [{}, set{}] = useState({})", { 
    i(1, "state"), 
    f(function(args) 
      return args[1][1]:sub(1,1):upper() .. args[1][1]:sub(2) 
    end, {1}), 
    i(2, "initialValue") 
  })),

  -- useEffect hook
  s("ue", fmt([[
useEffect(() => {{
  {}
}}, [{}])
]], { i(1, "// effect"), i(2, "dependencies") })),
}