-- AllInOneIME's own filter of the candidates the user removed (a right-click on one): left out by their text as shown.
-- Last of the schema's filters (rime_ice.custom.yaml, which AllInOneIME writes: PersonalDictionaryStore), after rime-ice's
-- own; librime then lays its pages out from what is left, each one full. The input method gives the texts as the context
-- property "allinoneime_removed", one per line (RimeSession.setRemovedCandidates). Never raises: no property, or one
-- that can't be read, leaves nothing out.

local property = "allinoneime_removed"

-- The texts removed, as a set: parsed again only when the property changed since (kept on env).
local function removed(env)
  local text = env.engine.context:get_property(property) or ""
  if text ~= env.removed_text then
    local set = {}
    for line in text:gmatch("[^\n]+") do set[line] = true end
    env.removed_text, env.removed = text, set
  end
  return env.removed
end

-- The candidates but those removed, in order, as librime pulls them: its pages need only the first few.
local function filter(input, env)
  local ok, set = pcall(removed, env)
  if not ok then set = {} end
  for cand in input:iter() do
    if not set[cand.text] then yield(cand) end
  end
end

return filter
