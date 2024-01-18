Config = {}

local INITIAL_CONFIGS =  {
		ENABLED = 1,
		LOG_LEVEL = 3,
		RESET_CONFIGS = 0,
		SYNC_CONFIGS = 1,
		SORT_ITEMS_ON_LOAD = 1,
		FILTERS_DIR = 'filters/',
		FILTER_TABLES = {},
		SYNC_FILTERS = 1
	}

PersistentVars = {
	---@type ItemFilterMap
	ItemFilters = {}
}

function Config:InitializeConfigurations()
	PersistentVars.Config.RESET_CONFIGS = 0
	
	for mapName, mapValues in pairs(ItemFilters.ItemMaps) do
		table.insert(INITIAL_CONFIGS.FILTER_TABLES, mapName)
		Utils:SaveTableToFile(PersistentVars.Config.FILTERS_DIR .. mapName .. ".json", mapValues)
	end
	
	PersistentVars.Config = INITIAL_CONFIGS
	Utils:SaveTableToFile("config.json", PersistentVars.Config)
end

function Config.SyncConfigsAndFilters()
	local config = Utils:LoadFile("config.json")

	if config then
		config = Ext.Json.Parse(config)
	end

	if not config or config.RESET_CONFIGS == 1 then
		Config:InitializeConfigurations()
		Logger:BasicInfo("Initalizing all the configs!")
		
		config = PersistentVars.Config
	end

	if config.SYNC_CONFIGS == 1 then
		PersistentVars.Config = config
		Logger:BasicInfo("Syncing the config file!")
		for mapName, _ in pairs(ItemFilters.ItemMaps) do
			local hasTableRecorded = false
			for _, filterTable in pairs(PersistentVars.Config.FILTER_TABLES) do
				if filterTable == mapName then
					hasTableRecorded = true
					break
				end
			end

			if not hasTableRecorded then
				table.insert(PersistentVars.Config.FILTER_TABLES, mapName)
			end
		end
		
		PersistentVars.Config = PersistentVars.Config
	end

	if PersistentVars.Config.SYNC_FILTERS == 1 then
		Logger:BasicInfo("Syncing the filters")
		for _, filterTableName in pairs(PersistentVars.Config.FILTER_TABLES) do
			local filterTableFilePath = PersistentVars.Config.FILTERS_DIR .. "/" .. filterTableName .. ".json"
			local filterTable = Utils:LoadFile(filterTableFilePath)

			if filterTable then
				local success, result = pcall(function()
					---@type ItemFilterMap
					local loadedFilterTable = Ext.Json.Parse(filterTable)
					
					if ItemFilters.ItemMaps[filterTableName] then
						for key, itemFilter in pairs(ItemFilters.ItemMaps[filterTableName]) do
							if not loadedFilterTable[key] then
								loadedFilterTable[key] = itemFilter
							end
						end
					end
					ItemFilters.ItemMaps[filterTableName] = loadedFilterTable

					PersistentVars.ItemFilters[filterTableName] = ItemFilters.ItemMaps[filterTableName]
				end)

				if not success then
					Logger:BasicError(string.format("Could not parse table %s due to error [%s]", filterTableName,
						result))
				else
					Utils:SaveTableToFile(PersistentVars.Config.FILTERS_DIR .. filterTableName .. ".json", PersistentVars.ItemFilters[filterTableName])
				end
			else
				Logger:BasicWarning("Could not find filter table file " .. filterTableFilePath)
			end
		end
	end

	for itemFilterTableName, itemFilterTable in pairs(PersistentVars.ItemFilters) do
		ItemFilters.ItemMaps[itemFilterTableName] = itemFilterTable
	end
end
