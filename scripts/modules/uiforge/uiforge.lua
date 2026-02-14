-- WARNING: DO NOT REQUIRE THIS FILE -- IT WILL LIKELY BREAK THE ENVIRONMENT
-- FOR INTELLISENSE USE ONLY

UiForge = {}

UiForge.scripts_path    = ""    -- Contains the path to the `scripts` directory
UiForge.modules_path    = ""    -- Contains the path to the `modules` directory
UiForge.resources_path  = ""    -- Contains the path to the `resources` directory

UiForge.CallbackType = {
    Settings = 0,
    DisableScript = 1,
}

UiForge.IGraphicsApi = {}

--- Create a texture compatible with ImGui.Image
--- @param path_to_image string an absolute path to an image or a relative path from the target application
--- @return userdata|nil texture A pointer to the created texture. To be used directly with ImGui.Image.
function UiForge.IGraphicsApi.CreateTextureFromFile(path_to_image)
    return nil
end

--- Register a script callback (settings, disable, etc) for the currently running script.
--- @param callback_type integer One of `UiForge.CallbackType`.
--- @param callback function The callback function to register.
function UiForge.RegisterCallback(callback_type, callback)
end

return UiForge
