local HttpService = game:GetService('HttpService')

local SaveManager = {} do
	SaveManager.Folder = 'RedzLibSettings'
	SaveManager.Ignore = {}
	SaveManager.Library = nil
	
	-- Parser for different element types
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, value) 
				return { type = 'Toggle', idx = idx, value = value } 
			end,
			Load = function(idx, data, library)
				if library.Flags[idx] then 
					-- Find the toggle element and set its value
					for _, element in pairs(library.Elements) do
						if element.Flag == idx and element.Set then
							element:Set(data.value)
							break
						end
					end
				end
			end,
		},
		Slider = {
			Save = function(idx, value)
				return { type = 'Slider', idx = idx, value = tonumber(value) }
			end,
			Load = function(idx, data, library)
				if library.Flags[idx] then 
					for _, element in pairs(library.Elements) do
						if element.Flag == idx and element.Set then
							element:Set(tonumber(data.value))
							break
						end
					end
				end
			end,
		},
		Dropdown = {
			Save = function(idx, value)
				return { type = 'Dropdown', idx = idx, value = value }
			end,
			Load = function(idx, data, library)
				if library.Flags[idx] then 
					for _, element in pairs(library.Elements) do
						if element.Flag == idx and element.Set then
							element:Set(data.value)
							break
						end
					end
				end
			end,
		},
		TextBox = {
			Save = function(idx, value)
				return { type = 'TextBox', idx = idx, value = value }
			end,
			Load = function(idx, data, library)
				if library.Flags[idx] and type(data.value) == 'string' then
					for _, element in pairs(library.Elements) do
						if element.Flag == idx and element.Set then
							element:Set(data.value)
							break
						end
					end
				end
			end,
		},
	}

	function SaveManager:SetIgnoreIndexes(list)
		for _, key in next, list do
			self.Ignore[key] = true
		end
	end

	function SaveManager:SetFolder(folder)
		self.Folder = folder
		self:BuildFolderTree()
	end

	function SaveManager:SetLibrary(library)
		self.Library = library
		
		-- Automatically use the SaveFolder from the library if it exists
		-- Check both library.Settings.ScriptFile and the global Settings table
		local saveFolder = nil
		
		if library.Settings and library.Settings.ScriptFile then
			saveFolder = library.Settings.ScriptFile
		end
		
		if saveFolder and saveFolder ~= false then
			self:SetFolder(saveFolder)
		else
			-- If no SaveFolder is set, use default
			print("[SaveManager] Warning: No SaveFolder specified in Window. Using default: " .. self.Folder)
		end
	end

	function SaveManager:Save(name)
		if (not name) then
			return false, 'no config file is selected'
		end
		
		if not self.Library then
			return false, 'library not set'
		end

		local fullPath = self.Folder .. '/configs/' .. name .. '.json'

		local data = {
			objects = {}
		}

		-- Save all flags
		local flagCount = 0
		for idx, value in pairs(self.Library.Flags) do
			if self.Ignore[idx] then continue end
			
			-- Determine type based on value
			local valueType = type(value)
			local saveType = 'TextBox' -- default
			
			if valueType == 'boolean' then
				saveType = 'Toggle'
			elseif valueType == 'number' then
				saveType = 'Slider'
			elseif valueType == 'string' then
				saveType = 'Dropdown'
			elseif valueType == 'table' then
				saveType = 'Dropdown' -- for multi-select dropdowns
			end

			if self.Parser[saveType] then
				table.insert(data.objects, self.Parser[saveType].Save(idx, value))
				flagCount = flagCount + 1
			end
		end
		
		-- Debug info
		print(string.format("[SaveManager] Saving %d flags to: %s", flagCount, fullPath))

		local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
		if not success then
			return false, 'failed to encode data: ' .. tostring(encoded)
		end
		
		local writeSuccess, writeError = pcall(function()
			writefile(fullPath, encoded)
		end)
		
		if not writeSuccess then
			return false, 'failed to write file: ' .. tostring(writeError)
		end

		return true
	end

	function SaveManager:Load(name)
		if (not name) then
			return false, 'no config file is selected'
		end
		
		local file = self.Folder .. '/configs/' .. name .. '.json'
		if not isfile(file) then 
			return false, 'invalid file' 
		end

		local success, decoded = pcall(HttpService.JSONDecode, HttpService, readfile(file))
		if not success then 
			return false, 'decode error' 
		end

		for _, option in pairs(decoded.objects) do
			if self.Parser[option.type] then
				task.spawn(function() 
					self.Parser[option.type].Load(option.idx, option, self.Library) 
				end)
			end
		end

		return true
	end

	function SaveManager:Delete(name)
		if (not name) then
			return false, 'no config file is selected'
		end
		
		local file = self.Folder .. '/configs/' .. name .. '.json'
		if not isfile(file) then 
			return false, 'file does not exist' 
		end

		delfile(file)
		return true
	end

	function SaveManager:BuildFolderTree()
		local paths = {
			self.Folder,
			self.Folder .. '/configs'
		}

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function SaveManager:RefreshConfigList()
		local list = listfiles(self.Folder .. '/configs')

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == '.json' then
				local pos = file:find('.json', 1, true)
				local start = pos

				local char = file:sub(pos, pos)
				while char ~= '/' and char ~= '\\' and char ~= '' do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == '/' or char == '\\' then
					table.insert(out, file:sub(pos + 1, start - 1))
				end
			end
		end
		
		return out
	end

	function SaveManager:LoadAutoloadConfig()
		if isfile(self.Folder .. '/configs/autoload.txt') then
			local name = readfile(self.Folder .. '/configs/autoload.txt')

			local success, err = self:Load(name)
			if not success then
				self.Library:Notify('Failed to load autoload: ' .. err, 3)
				return false
			end

			self.Library:Notify('Auto loaded: ' .. name, 2)
			return true
		end
		return false
	end

	function SaveManager:BuildConfigSection(tab)
		assert(self.Library, 'Must set SaveManager.Library first')

		local ConfigSection = tab:AddSection('Configuration Manager')
		
		-- Config name input
		local ConfigNameBox = tab:AddTextBox({
			Name = 'Config Name',
			Description = 'Enter config name',
			PlaceholderText = 'MyConfig',
			Flag = 'SaveManager_ConfigName'
		})
		
		-- Config list dropdown
		local ConfigList = tab:AddDropdown({
			Name = 'Config List',
			Description = 'Select a config',
			Options = self:RefreshConfigList(),
			Default = nil,
			MultiSelect = false,
			Flag = 'SaveManager_ConfigList'
		})

		-- Create config button
		tab:AddButton({
			Name = 'Create Config',
			Description = 'Save current settings',
			Callback = function()
				local name = self.Library.Flags.SaveManager_ConfigName
				
				if not name or name:gsub(' ', '') == '' then 
					return self.Library:Notify('Invalid config name', 3)
				end

				local success, err = self:Save(name)
				if not success then
					return self.Library:Notify('Failed to save: ' .. err, 3)
				end

				self.Library:Notify('Created config: ' .. name, 2)
				
				-- Refresh the list
				local newList = self:RefreshConfigList()
				ConfigList:Set(newList)
			end
		})
		
		-- Load config button
		tab:AddButton({
			Name = 'Load Config',
			Description = 'Load selected config',
			Callback = function()
				local name = self.Library.Flags.SaveManager_ConfigList
				
				if not name or name == '' then
					return self.Library:Notify('No config selected', 3)
				end

				local success, err = self:Load(name)
				if not success then
					return self.Library:Notify('Failed to load: ' .. err, 3)
				end

				self.Library:Notify('Loaded config: ' .. name, 2)
			end
		})
		
		-- Overwrite config button
		tab:AddButton({
			Name = 'Overwrite Config',
			Description = 'Overwrite selected config',
			Callback = function()
				local name = self.Library.Flags.SaveManager_ConfigList
				
				if not name or name == '' then
					return self.Library:Notify('No config selected', 3)
				end

				local success, err = self:Save(name)
				if not success then
					return self.Library:Notify('Failed to overwrite: ' .. err, 3)
				end

				self.Library:Notify('Overwrote config: ' .. name, 2)
			end
		})
		
		-- Delete config button
		tab:AddButton({
			Name = 'Delete Config',
			Description = 'Delete selected config',
			Callback = function()
				local name = self.Library.Flags.SaveManager_ConfigList
				
				if not name or name == '' then
					return self.Library:Notify('No config selected', 3)
				end

				local success, err = self:Delete(name)
				if not success then
					return self.Library:Notify('Failed to delete: ' .. err, 3)
				end

				self.Library:Notify('Deleted config: ' .. name, 2)
				
				-- Refresh the list
				local newList = self:RefreshConfigList()
				ConfigList:Set(newList)
			end
		})
		
		-- Refresh list button
		tab:AddButton({
			Name = 'Refresh List',
			Description = 'Refresh config list',
			Callback = function()
				local newList = self:RefreshConfigList()
				ConfigList:Set(newList)
				self.Library:Notify('Config list refreshed', 2)
			end
		})
		
		-- Set autoload button
		tab:AddButton({
			Name = 'Set as Autoload',
			Description = 'Auto load on startup',
			Callback = function()
				local name = self.Library.Flags.SaveManager_ConfigList
				
				if not name or name == '' then
					return self.Library:Notify('No config selected', 3)
				end
				
				writefile(self.Folder .. '/configs/autoload.txt', name)
				self.Library:Notify('Set autoload: ' .. name, 2)
			end
		})

		-- Ignore the SaveManager flags
		self:SetIgnoreIndexes({ 'SaveManager_ConfigList', 'SaveManager_ConfigName' })
	end

	-- Initialize folder structure
	SaveManager:BuildFolderTree()
end

return SaveManager
