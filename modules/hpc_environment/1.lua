--[[
Copyright 2021 Laurence Alexander Hurst

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]--

-- OS variables
local os_fullname = "UNKNOWN"
local os_shortname = "UNKNOWN"
local os_version = "UNKNOWN"
local os_version_major = "UNKNOWN"
local os_distribution = "UNKNOWN"
-- Architecture variables
local arch_platform = "UNKNOWN"
local arch_cpu_fullname = "UNKNOWN"
local arch_cpu_shortname = "UNKNOWN"
local arch_cpu_compat = ""

function file_exists(file_name)
	local file_found = io.open(file_name, "r")
	if file_found == nil then
		return false
	else
		return true
	end
end

function get_command_ouput(command)
	-- Run a command and return the ouput with whitespace stripped from the end
	return string.gsub(capture(command), '%s+$', '')
end

function load_os_release()
    -- Open the os-release file
    local file = io.open("/etc/os-release", "r")
    if not file then
        LmodError("Failed to open /etc/os-release - cannot detect OS information")
        return
    end

    -- Parse each line and set environment variables
    for line in file:lines() do
        -- Skip comments and empty lines
        if not line:match("^#") and line:find("=") then
            -- Split into key and value
            local key, value = line:match("^([^=]+)=['\"]?(.-)['\"]?$")
            
            -- Remove any remaining quotes from value
            value = value:gsub("['\"]", "")
            
            -- Set as HPC_ prefixed environment variable
            if key and value then
                setenv("HPC_OS_RELEASE_"..key, value)
            end
        end
    end
    file:close()
end

function detect_arch()
	-- Detect architecture information
	local cpu_family = get_command_ouput("grep -m1 '^cpu family[[:space:]:]\\+' /proc/cpuinfo | sed 's/^cpu family[[:space:]:]\\+\\([0-9]\\+\\)$/\\1/'")
	local cpu_model = get_command_ouput("grep -m1 '^model[[:space:]:]\\+' /proc/cpuinfo | sed 's/^model[[:space:]:]\\+\\([0-9]\\+\\)$/\\1/'")
	local cpu_flags = get_command_ouput("grep -m1 '^flags[[:space:]:]\\+' /proc/cpuinfo | sed 's/^flags[[:space:]:]\\+\\(.\\+\\)$/\\1/'")

	-- We need to detect for Azure:
	--   Dv3: Haswell, Broadwell, Skylake or Cascade lake
	--   Fsv2: Skylake, Cascade Lake
	--   NCv2: Broadwell
	--   NCv3: Broadwell
	--   HB: AMD Zen 1
	--   HBv2: AMD Zen 2
	--   HC: Skylake
	
	-- Treat Broadwell as being Haswell due to compatible instruction sets
	local cpu_table = {
		["6"] = {
			["63"] = "has", -- Haswell
			["71"] = "has", -- Broadwell
			["79"] = "has", -- Broadwell
			["86"] = "has", -- Broadwell
			["85"] = "sky", -- Sylake or Cascade Lake
		},
		["23"] = {
			["1"] = "zen", -- AMD Zen 1
			["49"] = "zen2", -- AMD Zen 2
		},
	}
    -- Only care about the family to detect intel vs amd (vs arm)
    local cpu_plat_table = {
        ["6"] = "intel",
        ["23"] = "amd",
    }
	local cpu_names = {
		has = 'Haswell or Broadwell',
		sky = 'Skylake',
		cas = 'Cascade Lake',
		zen = 'AMD EPYC Zen',
		zen2 = 'AMD EPYC Zen 2',
	}
	-- List of compatible architectures (i.e. subset of same instruction set
	local backward_compat = {
		sky = {'has'},
		cas = {'sky', 'has'},
		zen2 = {'zen'},
	}

	local cpu_family_name = cpu_table[cpu_family][cpu_model]

	if cpu_family_name == "sky" then
		-- Skylake with avx512 VNNI is Cascade Lake
		-- see: https://en.wikipedia.org/wiki/AVX-512#CPUs_with_AVX-512
		if string.find(cpu_flags, 'avx512_vnni') then
			cpu_family_name = 'cas'
		end
	end

    arch_platform = cpu_plat_table[cpu_family]
	arch_cpu_shortname = cpu_family_name
	arch_cpu_fullname = cpu_names[arch_cpu_shortname]
	if backward_compat[arch_cpu_shortname] ~= nil then
		arch_cpu_compat = table.concat(backward_compat[arch_cpu_shortname], ' ')
	end
end

-- Detection is expensive, so only do it if we need to
if mode() == "load" then
	detect_os()
	detect_arch()
end

-- Export the architecture variables
setenv("HPC_ARCH_CPU_FULLNAME", arch_cpu_fullname)
setenv("HPC_ARCH_CPU_SHORTNAME", arch_cpu_shortname)
setenv("HPC_ARCH_CPU_COMPAT", arch_cpu_compat)
setenv("HPC_ARCH_PLATFORM", arch_platform)

