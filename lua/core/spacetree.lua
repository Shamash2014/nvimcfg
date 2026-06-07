-- space-tree: nestable, ephemeral, unscoped workspaces for Neovim.
--
-- Each space is backed by a native tabpage (Neovim's built-in window
-- configuration). The plugin layers a *tree* over those flat tabpages and
-- never touches the buffer list, so every buffer stays reachable from every
-- space. See docs/space-tree.md for the design rationale.

local M = {}

local map = vim.keymap.set

-- in-memory only; nothing is written to disk (requirement: no persistence)
local state = {
  nodes = {}, -- id -> node { id, name?, parent?, children = {id}, tab }
  by_tab = {}, -- tabid -> id
  root = nil, -- root id
  prev = nil, -- tabid of the last space we left (for toggle)
  next_id = 1,
}

local function node_of_tab(tab)
  local id = state.by_tab[tab]
  return id and state.nodes[id] or nil
end

local function new_node(parent_id, tab)
  local id = state.next_id
  state.next_id = id + 1
  local node = { id = id, name = nil, parent = parent_id, children = {}, tab = tab }
  state.nodes[id] = node
  state.by_tab[tab] = id
  if parent_id then
    table.insert(state.nodes[parent_id].children, id)
  end
  return node
end

-- Adopt whatever tabpage is current as the root (called once on setup, and
-- as a fallback whenever the tree has drifted from reality).
local function adopt_root()
  local tab = vim.api.nvim_get_current_tabpage()
  state.root = new_node(nil, tab).id
  return state.nodes[state.root]
end

-- The node for the active tabpage. If the active tab is unknown (e.g. created
-- by :tabnew outside the plugin) adopt it as a child of the last known node.
function M.current()
  local tab = vim.api.nvim_get_current_tabpage()
  local node = node_of_tab(tab)
  if node then
    return node
  end
  if not state.root or not vim.api.nvim_tabpage_is_valid(state.nodes[state.root].tab) then
    return adopt_root()
  end
  -- attach the orphan tab under the root so the tree stays whole
  return new_node(state.root, tab)
end

function M.label(node)
  return node.name or ("#" .. node.id)
end

-- root > #2 > work : breadcrumb for the active space (for statuslines, etc.)
function M.breadcrumb()
  local node = M.current()
  local parts = {}
  while node do
    table.insert(parts, 1, M.label(node))
    node = node.parent and state.nodes[node.parent] or nil
  end
  return table.concat(parts, " ❯ ")
end

local function goto_tab(tab)
  if tab and vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    return true
  end
  return false
end

-- Unlink a node from its current parent's children list (without destroying it).
local function detach(node)
  local parent = node.parent and state.nodes[node.parent]
  if not parent then
    return
  end
  for i, c in ipairs(parent.children) do
    if c == node.id then
      table.remove(parent.children, i)
      return
    end
  end
end

local function spawn_under(parent_id)
  -- Suppress the TabNew autocmd while we create the tab: spawn_under parents
  -- the new space itself, so the autocmd's "adopt orphan under root" must not
  -- race us (it fires synchronously and would mis-parent the new tab to root).
  state.spawning = true
  vim.cmd("tabnew")
  state.spawning = false
  local tab = vim.api.nvim_get_current_tabpage()
  local existing = node_of_tab(tab)
  if existing then
    -- a racing adopt may have already parented it elsewhere; reparent cleanly
    if existing.parent ~= parent_id then
      detach(existing)
      existing.parent = parent_id
      if parent_id then
        table.insert(state.nodes[parent_id].children, existing.id)
      end
    end
    return existing
  end
  return new_node(parent_id, tab)
end

-- create a child space of the current one and jump into it
function M.child()
  local cur = M.current()
  local node = spawn_under(cur.id)
  goto_tab(node.tab)
  M.echo("＋ child " .. M.label(node))
  return node
end

-- Snapshot the active tabpage's window layout as a plain table: the winlayout
-- tree with each leaf carrying the buffer it shows and its cursor position.
local function capture_layout()
  local function annotate(node)
    if node[1] == "leaf" then
      local win = node[2]
      return {
        "leaf",
        {
          buf = vim.api.nvim_win_get_buf(win),
          cursor = vim.api.nvim_win_get_cursor(win),
        },
      }
    end
    local out = { node[1], {} }
    for _, child in ipairs(node[2]) do
      table.insert(out[2], annotate(child))
    end
    return out
  end
  return annotate(vim.fn.winlayout())
end

-- Rebuild a captured layout inside `win` by recursively splitting. A "row"
-- container becomes side-by-side vsplits, a "col" stacked splits.
local function rebuild_layout(node, win)
  if node[1] == "leaf" then
    local leaf = node[2]
    vim.api.nvim_win_set_buf(win, leaf.buf)
    pcall(vim.api.nvim_win_set_cursor, win, leaf.cursor)
    return
  end
  local cmd = node[1] == "row" and "rightbelow vsplit" or "rightbelow split"
  local children = node[2]
  local wins = { win }
  for i = 2, #children do
    vim.api.nvim_set_current_win(wins[i - 1])
    vim.cmd(cmd)
    wins[i] = vim.api.nvim_get_current_win()
  end
  for i, child in ipairs(children) do
    rebuild_layout(child, wins[i])
  end
end

-- Duplicate the current space (layout + shown buffers) into a new sibling.
function M.clone()
  local layout = capture_layout()
  local cur = M.current()
  local node = spawn_under(cur.parent or cur.id)
  if cur.name then
    node.name = cur.name .. " (copy)"
  end
  goto_tab(node.tab)
  rebuild_layout(layout, vim.api.nvim_get_current_win())
  M.echo("⧉ cloned " .. M.label(cur) .. " → " .. M.label(node))
  return node
end

-- create a sibling (child of the current node's parent)
function M.sibling()
  local cur = M.current()
  local parent_id = cur.parent or cur.id
  local node = spawn_under(parent_id)
  goto_tab(node.tab)
  M.echo("＋ sibling " .. M.label(node))
  return node
end

function M.up()
  local cur = M.current()
  if cur.parent and goto_tab(state.nodes[cur.parent].tab) then
    M.echo("▲ " .. M.label(state.nodes[cur.parent]))
  else
    M.echo("at root")
  end
end

function M.down()
  local cur = M.current()
  local first = cur.children[1]
  if first and goto_tab(state.nodes[first].tab) then
    M.echo("▼ " .. M.label(state.nodes[first]))
  else
    M.echo("no children")
  end
end

local function sibling_step(delta)
  local cur = M.current()
  if not cur.parent then
    M.echo("root has no siblings")
    return
  end
  local sibs = state.nodes[cur.parent].children
  for i, id in ipairs(sibs) do
    if id == cur.id then
      local target = sibs[i + delta]
      if target and goto_tab(state.nodes[target].tab) then
        M.echo((delta > 0 and "▶ " or "◀ ") .. M.label(state.nodes[target]))
      end
      return
    end
  end
end

-- Toggle to the space we were last in (ping-pong). state.prev is kept current
-- by the TabLeave autocmd, so leaving here immediately records this space as
-- the next toggle target — flipping back and forth between two spaces.
function M.toggle()
  local prev = state.prev
  if prev and prev ~= vim.api.nvim_get_current_tabpage() and goto_tab(prev) then
    local node = node_of_tab(prev)
    M.echo("⇄ " .. (node and M.label(node) or "previous"))
  else
    M.echo("no previous space")
  end
end

function M.next_sibling()
  sibling_step(1)
end
function M.prev_sibling()
  sibling_step(-1)
end

function M.rename(name)
  local cur = M.current()
  if name and name ~= "" then
    cur.name = name
  else
    vim.ui.input({ prompt = "Space name: ", default = cur.name or "" }, function(input)
      if input then
        cur.name = input ~= "" and input or nil
      end
    end)
  end
end

-- close the current space and its whole subtree (depth-first), then land on
-- the parent. The active root is never closed.
function M.close()
  local cur = M.current()
  if not cur.parent then
    M.echo("won't close root")
    return
  end
  local parent = state.nodes[cur.parent]

  local function destroy(id)
    local n = state.nodes[id]
    for _, c in ipairs(vim.deepcopy(n.children)) do
      destroy(c)
    end
    if vim.api.nvim_tabpage_is_valid(n.tab) then
      pcall(vim.cmd, "tabclose! " .. vim.api.nvim_tabpage_get_number(n.tab))
    end
    state.by_tab[n.tab] = nil
    state.nodes[id] = nil
  end

  goto_tab(parent.tab)
  destroy(cur.id)
  for i, c in ipairs(parent.children) do
    if c == cur.id then
      table.remove(parent.children, i)
      break
    end
  end
  M.echo("✕ closed, now " .. M.label(parent))
end

function M.echo(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = "space-tree", timeout = 1200 })
end

-- Flatten the tree to indented lines for the picker / navigator float.
function M.tree_lines()
  local lines = {}
  local cur_id = M.current().id
  local function walk(id, depth)
    local n = state.nodes[id]
    if not n then
      return
    end
    local mark = id == cur_id and "● " or "○ "
    table.insert(lines, {
      id = id,
      tab = n.tab,
      text = string.rep("  ", depth) .. mark .. M.label(n),
      current = id == cur_id,
    })
    for _, c in ipairs(n.children) do
      walk(c, depth + 1)
    end
  end
  if state.root then
    walk(state.root, 0)
  end
  return lines
end

-- The spaces sharing the current space's level: its siblings (children of the
-- same parent). At the root level that set is just the root itself.
local function level_ids(cur)
  if cur.parent and state.nodes[cur.parent] then
    return state.nodes[cur.parent].children
  end
  return { state.root }
end

-- A native tabline that shows ONLY same-level spaces. Drilling into a child
-- swaps the tabline to that child's siblings, so each level is its own strip of
-- tabs instead of Neovim's default flat list of every tabpage in the tree.
function M.tabline()
  local cur = M.current()

  -- dim breadcrumb of ancestors so you still know where this level sits
  local crumbs = {}
  local p = cur.parent and state.nodes[cur.parent] or nil
  while p do
    table.insert(crumbs, 1, M.label(p))
    p = p.parent and state.nodes[p.parent] or nil
  end
  local prefix = #crumbs > 0 and ("%#TabLineFill# " .. table.concat(crumbs, " ❯ ") .. " ❯ ") or ""

  local parts = {}
  for _, id in ipairs(level_ids(cur)) do
    local n = state.nodes[id]
    if n and vim.api.nvim_tabpage_is_valid(n.tab) then
      local num = vim.api.nvim_tabpage_get_number(n.tab)
      local hl = id == cur.id and "%#TabLineSel#" or "%#TabLine#"
      -- %{num}T makes the label clickable (switches to that tabpage)
      parts[#parts + 1] = hl .. "%" .. num .. "T " .. M.label(n) .. " "
    end
  end
  return prefix .. table.concat(parts) .. "%#TabLineFill#%T"
end

-- Jump to any space via the snacks picker (already used elsewhere in config).
function M.pick()
  local lines = M.tree_lines()
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and snacks.picker and snacks.picker.select then
    snacks.picker.select(lines, {
      prompt = "Spaces",
      format_item = function(item)
        return item.text
      end,
    }, function(choice)
      if choice then
        goto_tab(choice.tab)
      end
    end)
    return
  end
  vim.ui.select(lines, {
    prompt = "Spaces",
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if choice then
      goto_tab(choice.tab)
    end
  end)
end

local function reconcile()
  -- drop nodes whose tabpage was closed outside the plugin
  for id, n in pairs(state.nodes) do
    if not vim.api.nvim_tabpage_is_valid(n.tab) then
      state.by_tab[n.tab] = nil
      local parent = n.parent and state.nodes[n.parent]
      if parent then
        for i, c in ipairs(parent.children) do
          if c == id then
            table.remove(parent.children, i)
            break
          end
        end
        -- promote orphaned children to the grandparent
        for _, c in ipairs(n.children) do
          state.nodes[c].parent = n.parent
          table.insert(parent.children, c)
        end
      end
      state.nodes[id] = nil
      if state.root == id then
        state.root = nil
      end
    end
  end
  if not state.root then
    M.current()
  end
end

-- Persistence is opt-in via core.sessions, not a property of space-tree
-- itself. The tree is serialized by tabpage *ordinal* (1-based position),
-- because tabpage handles don't survive a restart but mksession restores
-- tabpages in the same order.
local function child_index(parent, id)
  for i, c in ipairs(parent.children) do
    if c == id then
      return i
    end
  end
end

function M.serialize()
  local pos_of = {}
  for i, tab in ipairs(vim.api.nvim_list_tabpages()) do
    pos_of[tab] = i
  end
  local records = {}
  local root_pos = nil
  for id, n in pairs(state.nodes) do
    local pos = pos_of[n.tab]
    if pos then
      local parent = n.parent and state.nodes[n.parent]
      records[#records + 1] = {
        pos = pos,
        parent = parent and pos_of[parent.tab] or nil,
        -- sibling rank within the parent: tab ordinal doesn't encode it
        -- (`:tabnew` inserts after the current tab), so it must be stored.
        order = parent and child_index(parent, id) or nil,
        name = n.name,
      }
      if id == state.root then
        root_pos = pos
      end
    end
  end
  return { root = root_pos, nodes = records }
end

-- Rebuild the tree from serialize() output against the freshly restored
-- tabpages. Replaces all in-memory state.
function M.rebuild(data)
  if not data or type(data.nodes) ~= "table" then
    return
  end
  local tabs = vim.api.nvim_list_tabpages()
  state.nodes, state.by_tab, state.root, state.next_id = {}, {}, nil, 1

  table.sort(data.nodes, function(a, b)
    return a.pos < b.pos
  end)

  local id_of_pos = {}
  for _, rec in ipairs(data.nodes) do
    local tab = tabs[rec.pos]
    if tab then
      local node = { id = state.next_id, name = rec.name, parent = nil, children = {}, tab = tab }
      state.next_id = state.next_id + 1
      state.nodes[node.id] = node
      state.by_tab[tab] = node.id
      id_of_pos[rec.pos] = node.id
    end
  end
  local links = {}
  for _, rec in ipairs(data.nodes) do
    local id = id_of_pos[rec.pos]
    if id then
      local pid = rec.parent and id_of_pos[rec.parent]
      if pid then
        state.nodes[id].parent = pid
        -- older sidecars (pre-order field) fall back to tab ordinal
        links[#links + 1] = { id = id, pid = pid, order = rec.order or rec.pos }
      elseif rec.pos == data.root then
        state.root = id
      end
    end
  end
  -- attach children in their saved sibling order, not tab ordinal, so
  -- down()/next_sibling()/the tabline match the tree that was saved
  table.sort(links, function(a, b)
    return a.order < b.order
  end)
  for _, l in ipairs(links) do
    table.insert(state.nodes[l.pid].children, l.id)
  end
  if not state.root then
    for _, rec in ipairs(data.nodes) do
      local id = id_of_pos[rec.pos]
      if id and not state.nodes[id].parent then
        state.root = id
        break
      end
    end
  end
  if not state.root then
    M.current()
  end
end

function M.setup()
  adopt_root()

  -- space-aware tabline: only same-level spaces, not every tabpage
  _G._nvim3_spacetree_tabline = M.tabline
  vim.o.tabline = "%!v:lua._nvim3_spacetree_tabline()"
  vim.o.showtabline = 2

  local grp = vim.api.nvim_create_augroup("SpaceTree", { clear = true })
  -- entering a space may change which level the tabline shows — redraw it
  vim.api.nvim_create_autocmd("TabEnter", {
    group = grp,
    callback = function()
      vim.cmd("redrawtabline")
    end,
  })
  vim.api.nvim_create_autocmd("TabNew", {
    group = grp,
    callback = function()
      -- adopt :tabnew-created tabs as children of the active space, but never
      -- when spawn_under is mid-flight (it parents its own tab explicitly)
      if state.spawning then
        return
      end
      vim.schedule(M.current)
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = grp,
    callback = function()
      vim.schedule(reconcile)
    end,
  })
  vim.api.nvim_create_autocmd("TabLeave", {
    group = grp,
    -- remember the space being left so M.toggle() can ping-pong back to it
    callback = function()
      state.prev = vim.api.nvim_get_current_tabpage()
    end,
  })

  -- <leader>z = "zones" (space-tree). <leader>s/t/w are already taken.
  map("n", "<leader>zc", M.child, { desc = "Space: new child" })
  map("n", "<leader>zs", M.sibling, { desc = "Space: new sibling" })
  map("n", "<leader>zk", M.up, { desc = "Space: up (parent)" })
  map("n", "<leader>zj", M.down, { desc = "Space: down (first child)" })
  map("n", "<leader>zl", M.next_sibling, { desc = "Space: next sibling" })
  map("n", "<leader>zh", M.prev_sibling, { desc = "Space: prev sibling" })
  map("n", "<leader>zr", function()
    M.rename()
  end, { desc = "Space: rename" })
  map("n", "<leader>zd", M.close, { desc = "Space: close subtree" })
  map("n", "<leader>zz", M.pick, { desc = "Space: pick/jump" })
  map("n", "<leader><Tab>", M.toggle, { desc = "Space: toggle last" })
  map("n", "<leader>zy", M.clone, { desc = "Space: clone (dup layout)" })
  map("n", "<leader>z?", function()
    M.echo(M.breadcrumb())
  end, { desc = "Space: where am I" })
end

return M
