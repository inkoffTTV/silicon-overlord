--!strict
local GameConfig = {}

GameConfig.SchemaVersion = 4
GameConfig.DataStoreName = "SHO_v1"
GameConfig.MemoryStoreName = "SHO_sessions"
GameConfig.AutosaveSeconds = 120
GameConfig.SessionLockSeconds = 300
GameConfig.MaxAuditEntries = 300
GameConfig.MaxNewsItems = 60
GameConfig.MaxReviewsPerProduct = 6
GameConfig.MaxSalesHistory = 26
GameConfig.MaxBlueprintHistory = 30
GameConfig.MaxCompaniesPerServer = 6
GameConfig.PlotSpacingStuds = 420
GameConfig.PlotSizeStuds = 320

GameConfig.Sounds = {
	Click = "rbxasset://sounds/button.wav",
	Hover = "rbxasset://sounds/clickfast.wav",
	Open = "rbxasset://sounds/swoosh.wav",
	Success = "rbxasset://sounds/electronicpingshort.wav",
	Cash = "rbxasset://sounds/snap.wav",
	Error = "rbxasset://sounds/uuhhh.mp3",
	Research = "rbxasset://sounds/victory.wav",
	Build = "rbxasset://sounds/collide.wav",
	Launch = "rbxasset://sounds/flashbulb.wav",
	Machine = "rbxasset://sounds/action_falling.mp3",
	Alert = "rbxasset://sounds/HalloweenLightning.wav",
}

GameConfig.SoundGroups = { "Master", "UI", "Factory", "Music", "Notifications" }

GameConfig.TutorialSteps = {
	{ id = "CreateCompany", title = "Основание компании", body = "Придумайте название и логотип. Это ваша будущая империя.", titleEn = "Found the company", bodyEn = "Pick a name and a logo. This is the start of your empire." },
	{ id = "OpenDesigner", title = "Первое устройство", body = "Откройте Product Designer (клавиша D или панель внизу) и соберите первый смартфон из доступных компонентов.", titleEn = "First device", bodyEn = "Open the Product Designer (key D or the bottom bar) and assemble a first smartphone from available components." },
	{ id = "FixCompatibility", title = "Совместимость", body = "Красные предупреждения — несовместимые детали. Исправьте их, пока индикатор не станет зелёным.", titleEn = "Compatibility", bodyEn = "Red warnings are incompatible parts. Fix them until the indicator turns green." },
	{ id = "SetPrice", title = "Цена", body = "Установите цену. Ориентир: себестоимость × 1.6 для массового рынка.", titleEn = "Price", bodyEn = "Set a price. Rule of thumb: unit cost x 1.6 for the mass market." },
	{ id = "Publish", title = "Публикация проекта", body = "Опубликуйте Blueprint — он станет продуктом в стадии разработки.", titleEn = "Publish the blueprint", bodyEn = "Publish the blueprint: it becomes a product in Development." },
	{ id = "Produce", title = "Производство", body = "На экране «Производство» запустите партию. Сборочная линия ограничивает объём в неделю.", titleEn = "Production", bodyEn = "On the Production screen queue a batch. The assembly line limits weekly output; hire workers to raise it." },
	{ id = "Launch", title = "Запуск", body = "Проведите презентацию (Keynote). После неё начнутся продажи.", titleEn = "Launch", bodyEn = "Hold the keynote. Sales start after it." },
	{ id = "FirstSales", title = "Первые продажи", body = "Рынок обновляется каждую неделю. Смотрите экран Market: регионы, сегменты и конкуренты.", titleEn = "First sales", bodyEn = "The market updates every week. Watch the Market screen: regions, segments and competitors." },
	{ id = "Research", title = "Исследования", body = "Откройте Research и запустите первую технологию. Исследователи ускоряют прогресс.", titleEn = "Research", bodyEn = "Open Research and start the first technology. Researchers speed it up." },
	{ id = "Expand", title = "Расширение", body = "Нанимайте персонал, стройте комнаты и улучшайте штаб-квартиру. Следите за квартальным отчётом.", titleEn = "Expansion", bodyEn = "Hire staff, build rooms and upgrade the headquarters. Read the quarterly report." },
}

return GameConfig
