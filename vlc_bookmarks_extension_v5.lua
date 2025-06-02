--[[
 VLC Video Bookmarks Extension
 Дозволяє навігацію по відео за допомогою часових міток з текстового файлу
 Підтримує macOS та Windows, кирилицю
--]]

-- Metadata для VLC extension
function descriptor()
    return {
        title = "Video Bookmarks",
        version = "1.0",
        author = "Video Navigator",
        url = "",
        shortdesc = "Navigate video using timestamps from text file",
        description = "Reads timestamps from text file and allows jumping to specific moments in video",
        capabilities = {"input-listener", "interface"}
    }
end

-- Глобальні змінні
local bookmarks = {}
local dialog = nil
local bookmark_list = nil
local file_path_input = nil
local current_file_path = ""

-- Функція активації extension
function activate()
    vlc.msg.info("Video Bookmarks extension activated")
    create_dialog()
end

-- Функція деактивації
function deactivate()
    if dialog then
        dialog:delete()
    end
end

-- Закриття діалогу хрестиком (викликається VLC)
function close()
    vlc.deactivate()
end

-- Створення діалогового вікна
function create_dialog()
    dialog = vlc.dialog("Video Bookmarks")
    
    -- Заголовок - розтягується на всю ширину
    dialog:add_label("Доступні мітки:", 1, 1, 4, 1)
    
    -- Випадаючий список - тепер займає всі 4 колонки для повної ширини
    bookmark_list = dialog:add_dropdown(1, 2, 4, 1)
    
    -- Порожній рядок для відступу
    dialog:add_label("", 1, 3, 4, 1)
    
    -- Кнопки - розміщуємо по краях з порожнім простором посередині
    dialog:add_button("Перейти до мітки", jump_to_bookmark, 1, 4, 1, 1)
    dialog:add_label("", 2, 4, 2, 1)  -- Розтягується для заповнення простору
    dialog:add_button("Закрити", close_dialog, 3, 4, 1, 1)
    
    -- Автоматичний пошук файлу при запуску
    auto_find_file()
end

-- Автоматичний пошук файлу з мітками
function auto_find_file()
    local input_item = vlc.input.item()
    if not input_item then
        vlc.msg.warn("Не знайдено активного медіафайлу")
        return
    end
    
    local media_path = input_item:uri()
    if not media_path then
        vlc.msg.warn("Не вдається отримати шлях до медіафайлу")
        return
    end
    
    vlc.msg.info("Оригінальний URI: " .. media_path)
    
    -- Конвертація URI в локальний шлях
    media_path = string.gsub(media_path, "file://", "")
    media_path = vlc.strings.decode_uri(media_path)
    
    vlc.msg.info("Декодований шлях: " .. media_path)
    
    -- Визначення ОС та корекція шляху
    local os_type = get_os_type()
    if os_type == "windows" then
        media_path = string.gsub(media_path, "/", "\\")
        if string.sub(media_path, 1, 1) == "\\" then
            media_path = string.sub(media_path, 2)
        end
    end
    
    -- Створення можливих шляхів до файлу міток
    local base_path = string.gsub(media_path, "([^/\\]+)$", "")
    local filename = string.match(media_path, "([^/\\]+)$")
    local name_without_ext = string.gsub(filename or "", "%.%w+$", "")
    
    vlc.msg.info("Базовий шлях: " .. (base_path or "nil"))
    vlc.msg.info("Ім'я файлу: " .. (filename or "nil"))
    vlc.msg.info("Ім'я без розширення: " .. (name_without_ext or "nil"))
    
    local possible_files = {
        base_path .. name_without_ext .. "_timestamps.txt",
        base_path .. name_without_ext .. "__uk_timestamps.txt",
        base_path .. name_without_ext .. "_bookmarks.txt",
        base_path .. name_without_ext .. ".txt",
        base_path .. "bookmarks.txt",
        base_path .. "timestamps.txt",
        base_path .. "chapters.txt"
    }
    
    -- Логування всіх можливих шляхів
    for i, file_path in ipairs(possible_files) do
        vlc.msg.info("Перевіряю файл " .. i .. ": " .. file_path)
    end
    
    -- Пошук файлу
    for _, file_path in ipairs(possible_files) do
        vlc.msg.info("Перевіряю існування: " .. file_path)
        if file_exists(file_path) then
            current_file_path = file_path
            if file_path_input then
                file_path_input:set_text(file_path)
            end
            load_bookmarks_from_file(file_path)
            vlc.msg.info("Автоматично знайдено файл міток: " .. file_path)
            return
        end
    end
    
    vlc.msg.info("Файл міток не знайдено автоматично. Спробуйте вказати шлях вручну.")
end

-- Визначення типу ОС
function get_os_type()
    local path_separator = package.config:sub(1,1)
    if path_separator == "\\" then
        return "windows"
    else
        return "unix" -- macOS, Linux
    end
end

-- Перевірка існування файлу
function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- Завантаження файлу міток
function load_bookmarks_file()
    if not file_path_input then
        return
    end
    
    local file_path = file_path_input:get_text()
    if file_path == "" then
        vlc.msg.warn("Будь ласка, вкажіть шлях до файлу")
        return
    end
    
    current_file_path = file_path
    load_bookmarks_from_file(file_path)
end

-- Завантаження міток з файлу
function load_bookmarks_from_file(file_path)
    bookmarks = {}
    
    vlc.msg.info("Спроба відкрити файл: " .. file_path)
    
    local file = io.open(file_path, "r")
    if not file then
        vlc.msg.error("Не вдається відкрити файл: " .. file_path)
        -- Спробуємо з різним кодуванням
        file = io.open(file_path, "rb")
        if not file then
            vlc.msg.error("Файл недоступний навіть в бінарному режимі")
            return
        end
    end
    
    local line_number = 0
    local content = file:read("*all")
    file:close()
    
    if not content or content == "" then
        vlc.msg.error("Файл порожній або не читається")
        return
    end
    
    vlc.msg.info("Файл прочитано, довжина: " .. string.len(content) .. " символів")
    
    -- Розбиваємо на рядки
    for line in string.gmatch(content .. "\n", "(.-)\n") do
        line_number = line_number + 1
        line = trim(line)
        
        vlc.msg.info("Обробляю рядок " .. line_number .. ": " .. line)
        
        if line ~= "" and not string.match(line, "^#") then
            local timestamp, description = parse_bookmark_line(line)
            if timestamp then
                table.insert(bookmarks, {
                    time = timestamp,
                    description = description or ("Мітка " .. line_number),
                    original_line = line
                })
                vlc.msg.info("Додано мітку: " .. format_time(timestamp) .. " - " .. (description or ""))
            else
                vlc.msg.warn("Не вдалося розпарсити рядок: " .. line)
            end
        end
    end
    
    vlc.msg.info("Завантажено " .. #bookmarks .. " міток з файлу")
    refresh_bookmarks()
end

-- Парсинг рядка з міткою
function parse_bookmark_line(line)
    vlc.msg.info("Парсинг рядка: '" .. line .. "'")
    
    -- Видаляємо зайві пробіли
    line = trim(line)
    
    -- Шукаємо час на початку рядка
    local time_pattern = "^(%d+):(%d+)%s+(.*)$"
    local minutes, seconds, description = string.match(line, time_pattern)
    
    if minutes and seconds then
        local total_seconds = tonumber(minutes) * 60 + tonumber(seconds)
        vlc.msg.info("Знайдено мітку: " .. minutes .. ":" .. seconds .. " = " .. total_seconds .. " секунд, опис: '" .. (description or "") .. "'")
        return total_seconds, description
    end
    
    -- Спробуємо інший формат з ведучими нулями
    time_pattern = "^0?(%d+):(%d+)%s+(.*)$"
    minutes, seconds, description = string.match(line, time_pattern)
    
    if minutes and seconds then
        local total_seconds = tonumber(minutes) * 60 + tonumber(seconds)
        vlc.msg.info("Знайдено мітку (формат 2): " .. minutes .. ":" .. seconds .. " = " .. total_seconds .. " секунд, опис: '" .. (description or "") .. "'")
        return total_seconds, description
    end
    
    -- Спробуємо формат H:MM:SS
    time_pattern = "^(%d+):(%d+):(%d+)%s+(.*)$"
    local hours, minutes_hms, seconds_hms, description_hms = string.match(line, time_pattern)
    
    if hours and minutes_hms and seconds_hms then
        local total_seconds = tonumber(hours) * 3600 + tonumber(minutes_hms) * 60 + tonumber(seconds_hms)
        vlc.msg.info("Знайдено мітку (H:M:S): " .. hours .. ":" .. minutes_hms .. ":" .. seconds_hms .. " = " .. total_seconds .. " секунд")
        return total_seconds, description_hms
    end
    
    vlc.msg.warn("Не вдалося розпарсити рядок: '" .. line .. "'")
    return nil, nil
end

-- Оновлення списку міток
function refresh_bookmarks()
    if not bookmark_list then
        vlc.msg.error("bookmark_list не ініціалізований")
        return
    end
    
    vlc.msg.info("Очищення списку міток")
    bookmark_list:clear()
    
    vlc.msg.info("Додавання " .. #bookmarks .. " міток до списку")
    
    for i, bookmark in ipairs(bookmarks) do
        local time_str = format_time(bookmark.time)
        local description = bookmark.description
        
        -- Обмежуємо довжину опису для гарного відображення
        if string.len(description) > 150 then
            description = string.sub(description, 1, 147) .. "..."
        end
        
        local display_text = time_str .. " - " .. description
        vlc.msg.info("Додаю до списку [" .. i .. "]: " .. display_text)
        
        -- Для dropdown використовуємо add_value з індексом
        bookmark_list:add_value(display_text, i)
    end
    
    vlc.msg.info("Список міток оновлено, всього елементів: " .. #bookmarks)
end

-- Форматування часу
function format_time(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, secs)
    else
        return string.format("%d:%02d", minutes, secs)
    end
end

-- Перехід до вибраної мітки
function jump_to_bookmark()
    if not bookmark_list then
        vlc.msg.warn("bookmark_list не ініціалізований")
        return
    end
    
    if #bookmarks == 0 then
        vlc.msg.warn("Немає завантажених міток")
        return
    end
    
    -- Спробуємо отримати вибраний елемент безпечно
    local selection_id = nil
    
    -- Безпечний виклик get_value
    local success, result1, result2 = pcall(bookmark_list.get_value, bookmark_list)
    
    if success and result2 and tonumber(result2) then
        selection_id = tonumber(result2)
        vlc.msg.info("Отримано вибір через get_value: id=" .. tostring(selection_id))
    elseif success and result1 and tonumber(result1) then
        selection_id = tonumber(result1)
        vlc.msg.info("Отримано вибір через get_value (перший результат): id=" .. tostring(selection_id))
    else
        vlc.msg.info("get_value не вдалося, спробуємо get_selection")
        
        -- Спробуємо get_selection
        local success2, selection_array = pcall(bookmark_list.get_selection, bookmark_list)
        
        if success2 and selection_array and type(selection_array) == "table" and #selection_array > 0 then
            selection_id = selection_array[1]
            vlc.msg.info("Отримано вибір через get_selection: id=" .. tostring(selection_id))
        end
    end
    
    -- Якщо нічого не вибрано, використовуємо першу мітку
    if not selection_id or selection_id < 1 or selection_id > #bookmarks then
        selection_id = 1
        vlc.msg.info("Використовуємо першу мітку за замовчуванням (id=1)")
    end
    
    local bookmark = bookmarks[selection_id]
    
    if bookmark then
        vlc.msg.info("Переходимо до мітки #" .. selection_id .. ": " .. bookmark.description .. " (час: " .. bookmark.time .. " сек)")
        
        -- Перевіряємо input
        local input = vlc.object.input()
        if not input then
            vlc.msg.error("❌ Немає активного input object - переконайтеся, що відео відтворюється")
            return
        end
        
        -- Конвертуємо секунди в мікросекунди для VLC
        local time_microseconds = bookmark.time * 1000000
        vlc.msg.info("Встановлюємо час: " .. bookmark.time .. " сек = " .. time_microseconds .. " мікросекунд")
        
        -- Встановлюємо час в мікросекундах
        local success_time = pcall(vlc.var.set, input, "time", time_microseconds)
        
        if success_time then
            vlc.msg.info("✅ Успішний перехід до мітки: " .. bookmark.description .. " (" .. format_time(bookmark.time) .. ")")
        else
            vlc.msg.error("❌ Помилка при встановленні часу відтворення")
        end
    else
        vlc.msg.error("❌ Не знайдено мітку з індексом: " .. tostring(selection_id))
    end
end

-- Допоміжна функція для обрізання пробілів
function trim(str)
    return string.match(str, "^%s*(.-)%s*$")
end

-- Закриття діалогу
function close_dialog()
    if dialog then
        dialog:delete()
        dialog = nil
    end
    vlc.deactivate()  -- Повністю зупиняємо extension
end