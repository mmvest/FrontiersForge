-- WARNING: DO NOT REQUIRE THIS FILE -- IT WILL LIKELY BREAK THE ENVIRONMENT
-- FOR INTELLISENSE USE ONLY

UiForge = {}

UiForge.scripts_path    = ""    -- Contains the path to the `scripts` directory
UiForge.modules_path    = ""    -- Contains the path to the `modules` directory
UiForge.resources_path  = ""    -- Contains the path to the `resources` directory

UiForge.IGraphicsApi = {}

--- Create a texture compatible with ImGui.Image
--- @param path_to_image string an absolute path to an image or a relative path from the target application
--- @return userdata|nil texture A pointer to the created texture. To be used directly with ImGui.Image.
function UiForge.IGraphicsApi.CreateTextureFromFile(path_to_image)
    return nil
end

--- Register a settings callback function that is used to display script settings
--- in the UiForge control panel (settings menu)
--- @param callback function The callback function to execute to display the settings in the control panel.
function UiForge.RegisterScriptSettings(callback)
end

return UiForge