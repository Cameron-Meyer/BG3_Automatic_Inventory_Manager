--- @module "Processors._CoreProcessor"

Ext.Require("AIM/Processors/_FilterProcessors.lua")
Ext.Require("AIM/Processors/_ModifierProcessors.lua")

--- Distributes the item stack according to the winners of the processed filters
--- @param partyMembersWithAmountWon table<CHARACTER, number>
--- @param item GUIDSTRING
--- @param root GUIDSTRING
--- @param inventoryHolder CHARACTER
local function ProcessWinners(partyMembersWithAmountWon, item, root, inventoryHolder)
	Osi.SetTag(item, TAG_AIM_PROCESSED)
	if Logger:IsLogLevelEnabled(Logger.PrintTypes.DEBUG) then
		Logger:BasicDebug("Final results are: " .. Ext.Json.Stringify(partyMembersWithAmountWon))
	end
	for target, amount in pairs(partyMembersWithAmountWon) do
		if amount > 0 then
			if target == inventoryHolder then
				Logger:BasicInfo(string.format("Target %s was determined to be inventoryHolder for %d of %s"
				, inventoryHolder
				, amount
				, item))
			elseif target == "camp" then
				Osi.SendToCampChest(item, inventoryHolder)
				Logger:BasicInfo(string.format("Moved %s of %s to CAMP from %s"
				, amount
				, item
				, inventoryHolder))
			else
				Osi.SetOriginalOwner(item, inventoryHolder)

				-- This method generates a new uuid for the item upon moving it without forcing us to destroy it and generate a new one from the template
				-- Need to make sure we don't clear the original owner here so our tracker logic in itemEvents knows
				Osi.ToInventory(item, target, amount, 0, 0)

				if not TEMPLATES_BEING_TRANSFERRED[root] then
					TEMPLATES_BEING_TRANSFERRED[root] = { [target] = amount }
				else
					TableUtils:AddItemToTable_AddingToExistingAmount(TEMPLATES_BEING_TRANSFERRED[root], target, amount)
				end

				Logger:BasicInfo(string.format("Moved %s of %s to %s from %s"
				, amount
				, item
				, target
				, inventoryHolder))
			end
		end
	end
end

-- If there's a stack limit, returns all the party members that are <, or nil if no members are
---
--- @param itemFilter ItemFilter
--- @param eligiblePartyMembers GUIDSTRING[]
--- @param targetsWithAmountWon table<GUIDSTRING, number>
--- @param root GUIDSTRING
--- @param item GUIDSTRING
--- @param inventoryHolder CHARACTER
---@return table|nil # All party members that have fewer than the stack limit, or nil if no members do
local function FilterInitialTargets_ByStackLimit(itemFilter,
												 eligiblePartyMembers,
												 targetsWithAmountWon,
												 root,
												 item,
												 inventoryHolder)
	if itemFilter.Modifiers and itemFilter.Modifiers[ItemFilters.ItemFields.FilterModifiers.STACK_LIMIT] then
		local filteredSurvivors = {}
		for _, partyMember in pairs(eligiblePartyMembers) do
			local totalFutureStackSize = ProcessorUtils:CalculateTotalItemCount(
				targetsWithAmountWon, partyMember, inventoryHolder, root, item)

			Logger:BasicTrace(string.format("Found %d on %s, against stack limit %d",
				totalFutureStackSize,
				partyMember,
				itemFilter.Modifiers[ItemFilters.ItemFields.FilterModifiers.STACK_LIMIT]))

			if totalFutureStackSize < itemFilter.Modifiers[ItemFilters.ItemFields.FilterModifiers.STACK_LIMIT] then
				table.insert(filteredSurvivors, partyMember)
			end
		end

		if Logger:IsLogLevelEnabled(Logger.PrintTypes.DEBUG) then
			Logger:BasicDebug("After processing STACK_LIMIT modifier, surviving partyMembers are: %s " ..
				Ext.Json.Stringify(filteredSurvivors))
		end
		return #filteredSurvivors > 0 and filteredSurvivors or nil
	end

	return { table.unpack(eligiblePartyMembers) }
end

---
---@param item GUIDSTRING
---@param eligiblePartyMembers CHARACTER[]
---@return table|nil # All party members that won't be encumbered by the item, or nil if all members will
local function FilterInitialTargets_ByEncumbranceRisk(item, eligiblePartyMembers)
	local filteredSurvivors = {}
	local itemWeight = tonumber(Ext.Entity.Get(item).Data.Weight)

	for _, partyMember in pairs(eligiblePartyMembers) do
		local partyMemberEntity = Ext.Entity.Get(partyMember)
		-- If not encumbered
		if tonumber(partyMemberEntity.EncumbranceState.State) == 0 then
			local unencumberedLimit = tonumber(partyMemberEntity.EncumbranceStats.UnencumberedWeight)
			local inventoryWeight = tonumber(partyMemberEntity.InventoryWeight["Weight"])
			if (inventoryWeight + itemWeight) <= unencumberedLimit then
				Logger:BasicTrace(string.format("Item weight %d will not encumber %s, with %d more room!",
					itemWeight,
					partyMember,
					unencumberedLimit - (inventoryWeight + itemWeight)))
				table.insert(filteredSurvivors, partyMember)
			end
		end
	end

	if Logger:IsLogLevelEnabled(Logger.PrintTypes.DEBUG) then
		Logger:BasicDebug("After filtering by EncumbranceRisk, remaining members are: "
			.. Ext.Json.Stringify(filteredSurvivors))
	end

	return #filteredSurvivors > 0 and filteredSurvivors or nil
end

Processor = {}

--- Processes the filters on the given params, moving the item(s) to the identified targets after all items in the stack have been processed
---@param item GUIDSTRING
---@param root GUIDSTRING
---@param inventoryHolder CHARACTER
---@param itemFilter ItemFilter
function Processor:ProcessFiltersForItemAgainstParty(item, root, inventoryHolder, itemFilter)
	local targetsWithAmountWon = {}
	local currentItemStackSize = Osi.GetStackAmount(item)
	local partyMembers = {}

	if (#Osi.DB_Players:Get(nil) < 1) then
		Logger:BasicDebug("The party has one or fewer members - skipping processing")
		return
	end
	for _, player in pairs(Osi.DB_Players:Get(nil)) do
		table.insert(partyMembers, player[1])
	end

	partyMembers = ModifierProcessors:ProcessPerStackModifiers(itemFilter.Modifiers,
		itemFilter,
		partyMembers,
		nil,
		item,
		currentItemStackSize,
		root,
		inventoryHolder)

	for _, partyMember in pairs(partyMembers) do
		targetsWithAmountWon[partyMember] = 0
	end

	local numberOfFiltersToProcess = #itemFilter.Filters
	local customItemFilterFields = {}
	for key, val in pairs(itemFilter) do
		local loweredKey = string.lower(key)
		if loweredKey ~= "filters" and loweredKey ~= "modifiers" then
			customItemFilterFields[key] = val
		end
	end

	for _ = 1, currentItemStackSize do
		local eligiblePartyMembers = FilterInitialTargets_ByStackLimit(itemFilter,
				partyMembers,
				targetsWithAmountWon,
				root,
				item,
				inventoryHolder)
			or partyMembers

		eligiblePartyMembers = FilterInitialTargets_ByEncumbranceRisk(item, eligiblePartyMembers)
			or eligiblePartyMembers

		for i, filter in ipairs(itemFilter.Filters) do
			eligiblePartyMembers = FilterProcessor:ExecuteFilterAgainstEligiblePartyMembers(filter,
				itemFilter.Modifiers,
				customItemFilterFields,
				eligiblePartyMembers,
				targetsWithAmountWon,
				inventoryHolder,
				item,
				root)

			if #eligiblePartyMembers == 1 or i == numberOfFiltersToProcess then
				local target
				if #eligiblePartyMembers > 0 then
					target = #eligiblePartyMembers == 1 and eligiblePartyMembers[1] or
						eligiblePartyMembers[Osi.Random(#eligiblePartyMembers) + 1]
				else
					target = targetsWithAmountWon[Osi.Random(#targetsWithAmountWon) + 1]
				end

				TableUtils:AddItemToTable_AddingToExistingAmount(targetsWithAmountWon, target, 1)

				if Logger:IsLogLevelEnabled(Logger.PrintTypes.TRACE) then
					Logger:BasicTrace("Winning command: " .. Ext.Json.Stringify(filter))
				end
				break
			end
		end
	end

	ProcessWinners(targetsWithAmountWon, item, root, inventoryHolder)
end
