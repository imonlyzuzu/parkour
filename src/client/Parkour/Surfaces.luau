-- Surfaces.luau
-- Single source of truth for which parkour actions a part allows. Permissions
-- are authored as CollectionService tags on the real parts; an untagged part
-- allows no special actions. The tag-checker is injectable so the core
-- predicate can be unit-tested with a fake.

local CollectionService = game:GetService("CollectionService")

-- Action name (as used by the states) -> CollectionService tag on the part.
local ACTION_TAG = {
	Wallrun = "Wallrunnable",
	Vault = "Vaultable",
	Grab = "Grabbable",
	Grapple = "Grappleable",
}

local Surfaces = {}

-- Core predicate with an injected `hasTag(instance, tag) -> boolean`. Exposed
-- for testing; production code calls Surfaces.allows.
function Surfaces._allowsWith(hasTag, instance: Instance?, action: string): boolean
	if not instance then
		return false
	end
	local tag = ACTION_TAG[action]
	if not tag then
		return false
	end
	return hasTag(instance, tag)
end

-- True only if `instance` exists and carries the tag mapped to `action`.
function Surfaces.allows(instance: Instance?, action: string): boolean
	return Surfaces._allowsWith(function(inst, tag)
		return CollectionService:HasTag(inst, tag)
	end, instance, action)
end

return Surfaces
