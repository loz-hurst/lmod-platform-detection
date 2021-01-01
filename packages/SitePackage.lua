local hook = require("Hook")

local function load_hook(t)
	LmodMessage(t.modFullName)
end

hook.register("load", load_hook)
