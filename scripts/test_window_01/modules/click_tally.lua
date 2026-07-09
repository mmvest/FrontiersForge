-- click_tally.lua
-- A deliberately simple module that lives inside this script package's own
-- modules folder. It is found by require("click_tally") because UiForge
-- prepends "test_window_01\modules" to package.path while this package's
-- script runs. A module with the same name in the shared scripts\modules
-- directory would be shadowed by this one.

local click_tally = {}

local total_clicks = 0
local last_label = "(nothing clicked yet)"

-- Record a click on a named widget
function click_tally.Record(label)
    total_clicks = total_clicks + 1
    last_label = label
end

-- Total clicks recorded since the module was loaded
function click_tally.GetTotal()
    return total_clicks
end

-- A friendly one line summary for display
function click_tally.GetSummary()
    if total_clicks == 0 then
        return "No clicks tallied yet."
    end
    return string.format("%d click(s) tallied. Last clicked widget was %q.", total_clicks, last_label)
end

-- Reset the tally
function click_tally.Reset()
    total_clicks = 0
    last_label = "(nothing clicked yet)"
end

return click_tally
