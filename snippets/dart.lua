local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- Stateless widget
  s("stl", fmt([[
class {} extends StatelessWidget {{
  const {}({{Key? key}}) : super(key: key);

  @override
  Widget build(BuildContext context) {{
    return {};
  }}
}}
]], { i(1, "WidgetName"), i(2, "WidgetName"), i(3, "Container()") })),

  -- Stateful widget
  s("stf", fmt([[
class {} extends StatefulWidget {{
  const {}({{Key? key}}) : super(key: key);

  @override
  State<{}> createState() => _{}State();
}}

class _{}State extends State<{}> {{
  @override
  Widget build(BuildContext context) {{
    return {};
  }}
}}
]], { i(1, "WidgetName"), i(2, "WidgetName"), i(3, "WidgetName"), i(4, "WidgetName"), i(5, "WidgetName"), i(6, "WidgetName"), i(7, "Container()") })),

  -- Main function
  s("main", fmt([[
void main() {{
  runApp(const {}());
}}
]], { i(1, "MyApp") })),

  -- Print statement
  s("pr", fmt("print('{}');", { i(1, "message") })),

  -- For loop
  s("for", fmt([[
for (int {} = {}; {} < {}; {}++) {{
  {}
}}
]], { i(1, "i"), i(2, "0"), i(3, "i"), i(4, "length"), i(5, "i"), i(6, "// body") })),

  -- If statement
  s("if", fmt([[
if ({}) {{
  {}
}}
]], { i(1, "condition"), i(2, "// body") })),

  -- Function
  s("fn", fmt([[
{} {}({}) {{
  {}
}}
]], { c(1, { t("void"), t("String"), t("int"), t("bool"), t("Widget") }), i(2, "functionName"), i(3, "parameters"), i(4, "// body") })),

  -- Container widget
  s("cont", fmt([[
Container(
  {}
  child: {},
)
]], { i(1, "// properties"), i(2, "widget") })),

  -- Column widget
  s("col", fmt([[
Column(
  children: [
    {},
  ],
)
]], { i(1, "// children") })),

  -- Row widget
  s("row", fmt([[
Row(
  children: [
    {},
  ],
)
]], { i(1, "// children") })),

  -- Text widget
  s("txt", fmt("Text('{}',{})", { i(1, "text"), i(2, "") })),

  -- Future builder
  s("fb", fmt([[
FutureBuilder<{}>(
  future: {},
  builder: (context, snapshot) {{
    if (snapshot.hasData) {{
      return {};
    }} else if (snapshot.hasError) {{
      return Text('Error: ${{snapshot.error}}');
    }}
    return const CircularProgressIndicator();
  }},
)
]], { i(1, "Type"), i(2, "future"), i(3, "widget") })),

  -- StreamBuilder
  s("sb", fmt([[
StreamBuilder<{}>(
  stream: {},
  builder: (context, snapshot) {{
    if (snapshot.hasData) {{
      return {};
    }} else if (snapshot.hasError) {{
      return Text('Error: ${{snapshot.error}}');
    }}
    return const CircularProgressIndicator();
  }},
)
]], { i(1, "Type"), i(2, "stream"), i(3, "widget") })),
}