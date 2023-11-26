-- https://github.com/Norbyte/bg3se/blob/main/Docs/API.md#getting-started
-- https://github.com/LaughingLeader/BG3ModdingTools/wiki
-- https://github.com/ShinyHobo/BG3-Modders-Multitool/wiki/

-- Development Outline:
--  ✅ OnPickup, move item to Lae'Zal (S_Player_Laezel_58a69333-40bf-8358-1d17-fff240d7fb12)
--  ✅ OnPickup, don't move item if not in table
--  ✅ OnPickup, move item to party member designated in table (S_Player_Gale_ad9af97d-75da-406a-ae13-7071c563f604)
--  ✅ Create Custom Tag to identify sorted items
--  ✅ Remove Custom Tag on drop
--  ❎ Reason: There's no reliable way to have BG3 tag an item as junk - no idea have Osi.IsJunk works. Gonna just point people to AUTO_SELL_LOOT
--			|-- Original item: OnPickup, tag item as junk if designated
-- 			|-- New Item: Implement adding optional tags. No use-cases yet, re-evaluate if needed later
--  ✅ Clear my item tags on Script Extender reset
--  ✅ OnPickup, move item designated as "best fit" to party member round-robin (e.g. distribute potions evenly)
--            ✅  Add weighted distribution by health
-- 	OnPickup, move item to designated class, with backup
--  ✅ Execute sort on game start
--  OnContainerOpen, optionally execute distribution according to config
--  Add option to have party members move to the item for "realism" - intercept on RequestCanPickup
--  SkillActivate - trigger distribution for all party members
--					stretch: anti-annoying measure for online play
--  OnPartyMemberSwap, redistribute from party member being left in camp
--  Add confirmation box to choose second-best fit if best fit will be encumbered (and so on)

-- Useful functions: MoveItemTo, GetItemByTagInInventory, GetStackAmount, ItemTagIsInInventory, UserTransferTaggedItems, SendToCampChest, IterateTagsCategory
-- Useful events: TemplateAddedTo, CharacterJoinedParty, CharacterLeftParty
-- Make a symblink: mklink /J "D:\GOG\Baldurs Gate 3\Data\Mods\Automatic_Inventory_Manager" "D:\Mods\BG3 Modder MultiTool\My Mods\Automatic_Inventory_Manager\Mods\Automatic_Inventory_Manager"
-- _D(Ext.Entity.Get("S_GLO_Orin_Bhaalist_Dagger_51c312d5-ce5e-4f8c-a5ad-edc2beced3e6"):GetAllComponents())

-- 569b0f3d-abcd-4b01-aaf0-979091288163 RootTemplateId
-- IsEquipable -> _D(Ext.StaticData.GetAll("EquipmentType")) -> _D(Ext.Entity.Get("51c312d5-ce5e-4f8c-a5ad-edc2beced3e6").ServerItem.Item.OriginalTemplate.EquipmentTypeID)
-- _D(Ext.Types.Serialize(Ext.StaticData.Get("7490e5d0-d346-4b0e-80c6-04e977160863", "Tag")).Name)


-- Chops off the UUID <br/>
-- @returns <br/>the 36 character UUID,<br/>the Human-Readable part of the id
function SplitUUIDAndName(item)
	return string.sub(item, -36), string.sub(item, 1, -38)
end

function GetItemDisplayName(item)
	-- Allows fallback
	local success, translatedName = pcall(function()
		---@diagnostic disable-next-line: param-type-mismatch
		return Osi.ResolveTranslatedString(Osi.GetDisplayName(item))
	end)
	if not success then return "NO HANDLE" else return translatedName end
end

function ApplyOptionalTags(root, item)
	local opt_tags = OPTIONAL_TAGS[item]
	if not opt_tags then opt_tags = OPTIONAL_TAGS[root] end
	if opt_tags then
		for _, tag in pairs(opt_tags) do
			if Osi.IsTagged(item, tag) == 0 then
				Osi.SetTag(item, tag)
				_P("Set tag " .. tag .. " on " .. item)
			end
		end
	end
end

-- Includes moving from container to other inventories etc...
Ext.Osiris.RegisterListener("TemplateAddedTo", 4, "after", function(root, item, inventoryHolder, addType)
	Osi.ClearTag(item, TAG_AIM_MARK_FOR_DELETION)

	_P("STARTED Processing item " ..
		item ..
		" with root " ..
		root ..
		" on character " .. inventoryHolder .. " with addType " .. addType .. " and amount " .. Osi.GetStackAmount(item))

	_P("----------------------------------------------------------")

	if Osi.IsTagged(item, TAG_AIM_PROCESSED) == 1 then
		_P("----------------------------------------------------------")
		_P("Item was already processed, skipping!\n")
		return
	end

	ApplyOptionalTags(root, item)

	local processingCommand
	if Osi.IsEquipable(item) then
		local equipmentTypeUUID = Ext.Entity.Get(item).ServerItem.Item.OriginalTemplate.EquipmentTypeID
		processingCommand = ITEMS_TO_PROCESS_MAP[EQUIPTYPE_UUID_TO_NAME_MAP[equipmentTypeUUID]]
	end

	for _, tag in pairs(Ext.Entity.Get(item).Tag.Tags) do
		local tagCommand = ITEMS_TO_PROCESS_MAP[TAG_UUID_TO_NAME_MAP[tag]]
		if tagCommand then
			processingCommand = tagCommand
		end
	end

	if processingCommand then
		ProcessCommand(item, root, inventoryHolder, processingCommand)
	else
		Ext.Utils.Print("No command could be found for " ..
		item .. " with root " .. root .. " on " .. inventoryHolder)
	end
	
	Osi.SetTag(item, TAG_AIM_PROCESSED)
	_P("----------------------------------------------------------")
	_P("FINISHED Processing item " ..
		item ..
		" with root " ..
		root ..
		" on character " .. inventoryHolder .. " with addType " .. addType .. " and amount " .. Osi.GetStackAmount(item) .. "\n")
end)

Ext.Osiris.RegisterListener("DroppedBy", 2, "after", function(object, inventoryHolder)
	Osi.ClearTag(object, TAG_AIM_PROCESSED)
end)

function ResetItemStacks()
	for _, player in pairs(Osi.DB_Players:Get(nil)) do
		_P("Cleaning up item stacks on " .. player[1])
		Osi.IterateInventory(player[1],
			EVENT_ITERATE_ITEMS_TO_REBUILD_THEM_START .. player[1],
			EVENT_ITERATE_ITEMS_TO_REBUILD_THEM_END .. player[1])
		ITEMS_TO_DELETE[player[1]] = {}
	end
end

Ext.Events.ResetCompleted:Subscribe(function(_)
	ResetItemStacks()
end)

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function(level, _)
	if level == "SYS_CC_I" then return end
	if Config.resetAllStacks then
		ResetItemStacks()
		Config.resetAllStacks = false
	end
end)

Ext.Osiris.RegisterListener("EntityEvent", 2, "before", function(guid, event)
	if string.find(event, EVENT_CLEAR_CUSTOM_TAGS_START) then
		_P("Cleared tag " ..
			string.sub(event, string.len(EVENT_CLEAR_CUSTOM_TAGS_START) + 1) ..
			" off item " .. guid .. " on stack " .. Osi.GetStackAmount(guid))
		Osi.ClearTag(guid, string.sub(event, string.len(EVENT_CLEAR_CUSTOM_TAGS_START) + 1))
	elseif string.find(event, EVENT_ITERATE_ITEMS_TO_REBUILD_THEM_START) then
		if Osi.GetMaxStackAmount(guid) > 1 then
			local itemTemplate = Osi.GetTemplate(guid)
			local currentStackSize, _ = Osi.GetStackAmount(guid)
			local character = string.sub(event, string.len(EVENT_ITERATE_ITEMS_TO_REBUILD_THEM_START) + 1)
			-- The alternative, TemplateRemoveFrom, can delete members of other stacks if they have different UUIDs (e.g. were split)
			Osi.SetTag(guid, TAG_AIM_MARK_FOR_DELETION)

			local itemsToDelete = ITEMS_TO_DELETE[character]
			if not itemsToDelete[itemTemplate] then
				itemsToDelete[itemTemplate] = currentStackSize;
			else
				itemsToDelete[itemTemplate] = itemsToDelete[itemTemplate] + currentStackSize
			end
		end
	elseif string.find(event, EVENT_ITERATE_ITEMS_TO_REBUILD_THEM_END) then
		local character = string.sub(event, string.len(EVENT_ITERATE_ITEMS_TO_REBUILD_THEM_END) + 1)
		Osi.PartyRemoveTaggedItems(character, TAG_AIM_MARK_FOR_DELETION,
			Osi.TaggedItemsGetCountInMagicPockets(TAG_AIM_MARK_FOR_DELETION, character))

		if ITEMS_TO_DELETE[character] then
			for itemTemplate, amount in pairs(ITEMS_TO_DELETE[character]) do
				Osi.TemplateAddTo(itemTemplate, character, amount)
				_P("Added " .. amount .. " of " .. itemTemplate .. " to " .. character)
			end
		end
	end
end)
