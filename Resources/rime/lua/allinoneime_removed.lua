-- AllInOneIME's own filter of the candidates the user removed (a right-click on one): left out by their text as shown.
-- Last of the schema's filters (rime_ice.custom.yaml, which AllInOneIME writes: PersonalDictionaryStore), after rime-ice's
-- own; librime then lays its pages out from what is left, each one full. The input method gives the texts as the context
-- property "allinoneime_removed", one per line (RimeSession.setRemovedCandidates); a change lays out anew what is being
-- typed (`init`). It also tells, before one is removed, whether librime's delete of it would delete the word it shows
-- (`derived`). Never raises: no property, or one that can't be read, leaves nothing out.

local property = "allinoneime_removed"
-- The input method puts the place on the page of the candidate it is about to delete here (RimeSession.deleteCandidate);
-- the answer goes on `derived_property` at once: "1" (`derived`), "0", or "" when it can't be told.
local asked_property = "allinoneime_delete_asked"
local derived_property = "allinoneime_derived"

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

-- "1" when the candidate at `index` on the page shown (as librime's delete_candidate_on_current_page counts) is one a
-- filter made from a word and put beside it: rime-ice's emoji filter (simplifier@emoji) puts 👏 after 鼓掌, a radical
-- after its name (讠 after 言部), January after 一月, each a shadow of the word's candidate, and librime's delete works on
-- the candidate's genuine one (Memory::OnDeleteEntry): it would forget what librime learned of the word. Told from what
-- librime has of it: the entry its delete would delete (`get_genuine`, a phrase), that entry's text, and the candidates
-- before it. One with its entry's text is that word. So is the first one of its entry with another text: the word in
-- other characters (simplifier@traditionalize, which puts it in the word's place: 紐幣 is the word 纽币, and forgetting
-- 纽币 is right). One after that, of the same entry (a candidate's own, or one merged into it by the uniquifier), or
-- whose entry's text the user removed (left out here, so not before it), was put beside the word: "1" (an emoji after
-- 開心 in Traditional, a second form: 髮 after 發). Any other "0"; librime deletes nothing of one that isn't a phrase's.
local function derived(env, ctx, index)
  local composition = ctx.composition
  if not index or composition:empty() then return "0" end
  local segment = composition:back()
  local page_size = env.engine.schema.page_size
  local at = segment.selected_index - segment.selected_index % page_size + index
  local cand = segment:get_candidate_at(at)
  if not cand then return "0" end
  local entry = cand:get_genuine()
  local kind = entry:get_dynamic_type()
  if cand.text == entry.text or (kind ~= "Phrase" and kind ~= "Sentence") then return "0" end
  if removed(env)[entry.text] then return "1" end
  for i = 0, at - 1 do
    for _, other in ipairs(segment:get_candidate_at(i):get_genuines()) do
      if other.text == entry.text and other._start == entry._start and other._end == entry._end then return "1" end
    end
  end
  return "0"
end

-- The list changed (one just removed): what is being typed laid out anew at once, without it, its page full again, as
-- the next key would. librime's own delete does that only for a word of its user dictionary, not for an English word,
-- a custom phrase or a Lua translator's candidate, whose page would show one less until then. Asked about a candidate
-- (`asked_property`): the answer.
local function init(env)
  pcall(function()
    env.connection = env.engine.context.property_update_notifier:connect(function(ctx, name)
      if name == property then
        pcall(function() ctx:refresh_non_confirmed_composition() end)
      elseif name == asked_property then
        local ok, answer = pcall(derived, env, ctx, tonumber(ctx:get_property(asked_property)))
        pcall(function() ctx:set_property(derived_property, ok and answer or "") end)
      end
    end)
  end)
end

local function fini(env)
  if env.connection then pcall(function() env.connection:disconnect() end) end
end

return { init = init, func = filter, fini = fini }
