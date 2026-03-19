-- [[ JD_REBORN: UPDATER MODULE ]]
local dlstatus = require('moonloader').download_status
local ffi = require('ffi')

local Updater = {}

-- Твоя текущая версия скрипта
Updater.current_version = 1.1 
-- Ссылка на RAW файл update.json с твоего GitHub
Updater.manifest_url = "https://raw.githubusercontent.com/malibu011/judce-dredd/main/update.json"

function Updater.check(isManual, UI_Ref, GlobalsRef)
    lua_thread.create(function()
        local temp_path = os.getenv('TEMP') .. '\\jd_update.json'
        local done = false
        local success = false
        
        if isManual and GlobalsRef then GlobalsRef.addNotify("Поиск обновлений...", 3, 0) end
        
        downloadUrlToFile(Updater.manifest_url, temp_path, function(id, status, p1, p2)
            if status == dlstatus.STATUS_ENDDOWNLOADDATA then
                done = true; success = true
            elseif status == dlstatus.STATUS_ERRORDOWNLOAD then
                done = true; success = false
            end
        end)
        
        while not done do wait(10) end

        if success and doesFileExist(temp_path) then
            local f = io.open(temp_path, 'r')
            local content = f:read('*a')
            f:close()
            os.remove(temp_path)

            local data = decodeJson(content)
            if data and tonumber(data.version) > Updater.current_version then
                -- Передаем данные в Mimgui
                UI_Ref.UpdateInfo.new_version = tostring(data.version)
                UI_Ref.UpdateInfo.changelog = data.changelog or "Нет списка изменений."
                UI_Ref.UpdateInfo.files = data.files or {}
                UI_Ref.WinState.update_modal[0] = true

                if GlobalsRef then GlobalsRef.addNotify("Доступна новая версия: v" .. data.version, 6, 1) end
            else
                if isManual and GlobalsRef then GlobalsRef.addNotify("У вас установлена последняя версия.", 4, 1) end
            end
        else
            if isManual and GlobalsRef then GlobalsRef.addNotify("Ошибка соединения с GitHub.", 4, 2) end
        end
    end)
end

function Updater.performUpdate(UI_Ref)
    lua_thread.create(function()
        local files = UI_Ref.UpdateInfo.files
        UI_Ref.UpdateInfo.total_files = #files
        UI_Ref.UpdateInfo.download_progress = 0
        
        for i, file_data in ipairs(files) do
            UI_Ref.UpdateInfo.current_file = file_data.path
            local target_path = getWorkingDirectory() .. '\\' .. file_data.path
            
            local done = false
            downloadUrlToFile(file_data.url, target_path, function(id, status)
                if status == dlstatus.STATUS_ENDDOWNLOADDATA or status == dlstatus.STATUS_ERRORDOWNLOAD then
                    done = true
                end
            end)
            
            while not done do wait(10) end
            UI_Ref.UpdateInfo.download_progress = i
        end
        
        wait(1000)
        thisScript():reload()
    end)
end

-- Список твоих пресетов на GitHub (путь обновлен для папки lib/JD_Reborn/presets)
Updater.presets = {
    { 
        name = "legacy.lua", 
        url = "https://raw.githubusercontent.com/malibu011/judce-dredd/main/moonloader/lib/JD_Reborn/presets/legacy.lua" 
    }
}

function Updater.updatePresets(GlobalsRef)
    lua_thread.create(function()
        if GlobalsRef then GlobalsRef.addNotify("Проверка базы данных...", 3, 0) end
        
        local temp_path = os.getenv('TEMP') .. '\\jd_presets_check.json'
        local done = false
        
        -- 1. Сначала тихо качаем наш главный update.json
        downloadUrlToFile(Updater.manifest_url, temp_path, function(id, status)
            if status == dlstatus.STATUS_ENDDOWNLOADDATA or status == dlstatus.STATUS_ERRORDOWNLOAD then
                done = true
            end
        end)
        
        while not done do wait(10) end

        if doesFileExist(temp_path) then
            local f = io.open(temp_path, 'r')
            local content = f:read('*a')
            f:close()
            os.remove(temp_path)

            local data = decodeJson(content)
            local remote_ver = data and tonumber(data.presets_version) or 0.0

            -- [НОВОЕ]: Читаем глобальную версию из отдельного файла
            local global_cfg_path = getWorkingDirectory() .. '\\config\\JUDCE_DREDD_REBORN\\global.json'
            local global_cfg = { presets_version = 0.0 }
            
            if doesFileExist(global_cfg_path) then
                local f = io.open(global_cfg_path, 'r')
                if f then
                    local parsed = decodeJson(f:read('*a'))
                    f:close()
                    if parsed then global_cfg = parsed end
                end
            end
            
            local local_ver = tonumber(global_cfg.presets_version) or 0.0

            -- 2. СРАВНИВАЕМ ВЕРСИИ
            if remote_ver > local_ver then
                if GlobalsRef then GlobalsRef.addNotify("Найдена новая база данных (v" .. remote_ver .. "). Загрузка...", 4, 0) end
                
                local config_dir = getWorkingDirectory() .. '\\lib\\JD_Reborn\\presets\\'
                local success_count = 0

                -- 3. КАЧАЕМ ПРЕСЕТЫ
                for _, preset in ipairs(Updater.presets) do
                    local target_path = config_dir .. preset.name
                    local dl_done = false

                    downloadUrlToFile(preset.url, target_path, function(id, status)
                        if status == dlstatus.STATUS_ENDDOWNLOADDATA then
                            success_count = success_count + 1
                            dl_done = true
                        elseif status == dlstatus.STATUS_ERRORDOWNLOAD then
                            dl_done = true
                        end
                    end)
                    while not dl_done do wait(10) end
                end

                -- 4. СОХРАНЯЕМ И ПРИМЕНЯЕМ
                if success_count == #Updater.presets then
                    -- [НОВОЕ]: Сохраняем версию в наш глобальный файл!
                    global_cfg.presets_version = remote_ver
                    local f = io.open(global_cfg_path, 'w')
                    if f then
                        f:write(encodeJson(global_cfg))
                        f:close()
                    end
                    
                    if GlobalsRef then GlobalsRef.addNotify("Пресеты обновлены до v" .. remote_ver, 5, 1) end
                    
                    local Data = require 'lib.JD_Reborn.data'
                    -- Подгружаем пресет для текущего активного сервера
                    local Settings = require 'lib.JD_Reborn.settings'
                    local server_id = Settings.Active.Main[4] and Settings.Active.Main[4].server_id or 0
                    if Data.loadPreset then Data.loadPreset(server_id) end
                else
                    if GlobalsRef then GlobalsRef.addNotify("Ошибка при скачивании файлов.", 5, 2) end
                end
            else
                -- Версии совпадают (или локальная выше)
                if GlobalsRef then GlobalsRef.addNotify("У вас уже актуальная база пресетов (v" .. local_ver .. ").", 4, 1) end
            end
        else
            if GlobalsRef then GlobalsRef.addNotify("Ошибка соединения с GitHub.", 4, 2) end
        end
    end)
end

return Updater