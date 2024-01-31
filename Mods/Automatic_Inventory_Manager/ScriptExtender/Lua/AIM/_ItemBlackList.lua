--- @module 'ItemBlackList'

ItemBlackList = {}

local blackListTable = {}

local fileName = "ItemBlackList"

local initialized = false


local function AddNonDuplicateEntries(currentTable, newTable)
	for _, newEntry in pairs(newTable) do
		local foundEntry = false
		for _, currentEntry in pairs(currentTable) do
			if newEntry == currentEntry then
				foundEntry = true
				break
			end
		end

		if not foundEntry then
			table.insert(currentTable, newEntry)
		end
	end
end

local function AddBlacklistTables(blackList)
	if blackList.Items then
		if blackListTable.Items then
			AddNonDuplicateEntries(blackListTable.Items, blackList.Items)
		else
			blackListTable.Items = blackList.Items
		end
	end

	if blackList.RootTemplates then
		if blackListTable.RootTemplates then
			AddNonDuplicateEntries(blackListTable.RootTemplates, blackList.RootTemplates)
		else
			blackListTable.RootTemplates = blackList.RootTemplates
		end
	end
end

function ItemBlackList:InitializeBlackList()
	local filePath = FileUtils:BuildRelativeJsonFileTargetPath(fileName)
	local blackList = FileUtils:LoadTableFile(filePath)

	if blackList then
		AddBlacklistTables(blackList)

		FileUtils:SaveTableToFile(filePath, blackListTable)
		-- Don't wipe out the Blacklist file if they just messed up the json syntax
	elseif not FileUtils:LoadFile(filePath) then
		FileUtils:SaveTableToFile(filePath, { ["RootTemplates"] = {}, ["Items"] = {} })
	end

	if not blackListTable.Items then
		blackListTable.Items = {}
	end

	if not blackListTable.RootTemplates then
		blackListTable.RootTemplates = {}
	end

	initialized = true

	Logger:BasicInfo("ItemBlackList set to: " .. Ext.Json.Stringify(blackListTable))
end

function ItemBlackList:AddEntriesToBlackList(modUUID, blackListEntries)
	local modInfo = ModUtils:GetModInfoFromUUID(modUUID)

	if not modInfo then
		return false
	else
		modInfo = modInfo.Name
	end

	AddBlacklistTables(blackListEntries)

	Logger:BasicInfo(string.format("Mod %s successfully added blackList entries: %s",
		modInfo,
		Ext.Json.Stringify(blackListTable)))

	-- not sure if mods would be able to add their values before we load from the file - so just a sanity check to make sure we only update the file
	-- if it's been loaded in already. Initialization takes this into account as well
	if initialized then
		FileUtils:SaveTableToFile(FileUtils:BuildRelativeJsonFileTargetPath(fileName), blackListTable)
	end

	return true
end

--- Checks to see if the item or rootTemplate is in the user-provided blacklist.
---@param item GUIDSTRING optional
---@param rootTemplate GUIDSTRING optional
---@treturn boolean true if the item or rootTemplate is in the blacklist
function ItemBlackList:IsItemOrTemplateInBlacklist(item, rootTemplate)
	if item then
		for _, itemUUID in pairs(blackListTable.Items) do
			if item == itemUUID then
				Logger:BasicInfo(string.format("Item %s was found in the blacklist!", item))
				return true
			end
		end
	end

	if rootTemplate then
		for _, rootUUID in pairs(blackListTable.RootTemplates) do
			if rootTemplate == rootUUID then
				Logger:BasicInfo(string.format("RootTemplate %s was found in the blacklist!", rootTemplate))
				return true
			end
		end
	end

	return false
end
