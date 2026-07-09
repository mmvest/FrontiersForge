-- WARNING: DO NOT REQUIRE THIS FILE -- IT WILL LIKELY BREAK THE ENVIRONMENT
-- FOR INTELLISENSE USE ONLY

UiForge = {}

UiForge.scripts_path            = ""    -- Contains the path to the `scripts` directory
UiForge.modules_path            = ""    -- Contains the path to the `modules` directory
UiForge.resources_path          = ""    -- Contains the path to the `resources` directory
UiForge.UiForge.profiles_path   = ""    -- Contains the path to the `profiles` directory

UiForge.CallbackType = {
    Settings = 0,       -- Renders the script settings UI inside the UiForge Settings panel
    DisableScript = 1,  -- Runs once when the script transitions from enabled to disabled
    Save = 2,           -- Returns a plain data table captured into the profile on File > Save Profile
    Load = 3,           -- Receives the saved table back when a profile is applied
    OnEject = 4,        -- Runs once for every script right before UiForge unloads
}

UiForge.IGraphicsApi = {}

--- Create a texture compatible with ImGui.Image
--- @param path_to_image string an absolute path to an image or a relative path from the target application
--- @return userdata|nil texture A pointer to the created texture. To be used directly with ImGui.Image.
function UiForge.IGraphicsApi.CreateTextureFromFile(path_to_image)
    return nil
end

--- Load an image into a texture handle usable with ImGui.Image.
--- Relative paths resolve against the calling script package's resources folder
--- first (when the script is packaged), then the shared resources directory.
--- @param path string absolute path, or path relative to the resources directories
--- @return userdata|nil texture A texture handle, or nil on failure.
function UiForge.LoadTexture(path)
    return nil
end

--- Create a texture from raw 32 bit RGBA pixel bytes (row major, no row padding).
--- Pass the pixels as a Lua string, for example ffi.string(buf, len).
--- @param rgba_pixels string the pixel bytes, must be width * height * 4 bytes
--- @param width integer image width in pixels
--- @param height integer image height in pixels
--- @return userdata|nil texture A texture handle usable with ImGui.Image, or nil on failure.
function UiForge.CreateTextureFromMemory(rgba_pixels, width, height)
    return nil
end

--- Release a texture created by LoadTexture, CreateTextureFromMemory, or CreateTextureFromFile.
--- @param texture userdata the texture handle to release
function UiForge.ReleaseTexture(texture)
end

--- Register a script callback for the currently running script.
function UiForge.RegisterCallback(callback_type, callback)
end

return UiForge
