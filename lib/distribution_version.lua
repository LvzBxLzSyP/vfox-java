local strings = require("vfox.strings")
local foojay = require("foojay")

-- static aliases kept as fallback for common short names
local static_aliases = {
    ["open"] = "openjdk",
    ["bsg"] = "bisheng",
    ["amzn"] = "corretto",
    ["albba"] = "dragonwell",
    ["graal"] = "graalvm",
    ["graalce"] = "graalvm_community",
    ["oracle"] = "oracle",
    ["kona"] = "kona",
    ["librca"] = "liberica",
    ["nik"] = "liberica_native",
    ["mandrel"] = "mandrel",
    ["ms"] = "microsoft",
    ["sapmchn"] = "sap_machine",
    ["sem"] = "semeru",
    ["tem"] = "temurin",
    ["trava"] = "trava",
    ["zulu"] = "zulu",
    ["jb"] = "jetbrains",
}

local short_name = {}
local long_name = {}
local distribution_version = { distributions = {} }

-- Build mappings by combining static aliases and dynamic data from foojay
local function build_mappings()
    -- start with static aliases
    for k, v in pairs(static_aliases) do
        short_name[k] = v
        long_name[v] = long_name[v] or k
    end

    -- fetch distributions from foojay and merge synonyms
    local ok, dists = pcall(foojay.get_distributions)
    if ok and dists then
        for _, dist in ipairs(dists) do
            local api_param = dist.api_parameter
            if api_param then
                -- ensure long_name has at least api_param as short alias
                long_name[api_param] = long_name[api_param] or api_param
                -- map api_parameter itself as a valid short_name (normalized)
                short_name[string.lower(api_param)] = api_param
                -- map synonyms to api_parameter
                if dist.synonyms then
                    for _, s in ipairs(dist.synonyms) do
                        if s and type(s) == "string" then
                            short_name[string.lower(s)] = api_param
                        end
                    end
                end
                -- add to distributions list (used by Available)
                table.insert(distribution_version.distributions, {
                    name = api_param,
                    short_name = api_param,
                })
            end
        end
    else
        -- fallback: if call failed, populate distributions from static aliases
        for k, v in pairs(static_aliases) do
            table.insert(distribution_version.distributions, {
                name = v,
                short_name = k,
            })
        end
    end
end

build_mappings()

function distribution_version.parse_distribution (name)
    if not name or type(name) ~= "string" then
        return nil
    end
    -- normalize input to support varied user input (case-insensitive)
    local name_l = string.lower(name)

    -- first check if input matches a known long name (api_parameter)
    if long_name[name_l] then
        return {
            name = name_l,
            short_name = long_name[name_l]
        }
    end

    -- check short_name aliases (including synonyms)
    local mapped = short_name[name_l]
    if mapped then
        return {
            name = mapped,
            short_name = name_l
        }
    end

    -- as last resort, check if the input as-is matches a long name
    if long_name[name] then
        return {
            name = name,
            short_name = long_name[name]
        }
    end

    return nil
end


--- Converts user-input version format to Foojay API format
--- Examples: "26.ea.1" -> "26-ea+1", "26.ea" -> "26-ea", "25.0.3" -> "25.0.3"
--- @param version string User-input version
--- @return string Converted version for Foojay API
function distribution_version.convert_version_for_api(version)
    -- Handle EA version format: "X.ea.Y" -> "X-ea+Y"
    local ea_version, ea_build = version:match("^(%d+)%.ea%.(%d+)$")
    if ea_version and ea_build then
        return ea_version .. "-ea+" .. ea_build
    end
    
    -- Handle EA version format without build number: "X.ea" -> "X-ea"
    local ea_version_only = version:match("^(%d+)%.ea$")
    if ea_version_only then
        return ea_version_only .. "-ea"
    end
    
    -- Return as-is for normal versions
    return version
end

function distribution_version.parse_version (arg)
    local version_parts = strings.split(arg, "-")
    local version
    local distribution
    local javafx_bundled = false

    -- Check if the last part is "fx" and remove it, setting javafx_bundled flag
    if version_parts[#version_parts] == "fx" then
        javafx_bundled = true
        table.remove(version_parts)
    end

    if not version_parts[2] then
        -- no parts, check if we got a distribution name without version
        distribution = distribution_version.parse_distribution(version_parts[1])
        if not distribution then
            -- no valid distribution found, handle as version with distribution "openjdk"
            version=version_parts[1]
            distribution = distribution_version.parse_distribution("openjdk")
        end
    else
        -- check if the distribution is in the second part of the string (vfox/sdkman default)
        distribution = distribution_version.parse_distribution(version_parts[2])
        if distribution then
            -- valid distribution found, treat first part as version
            version=version_parts[1]
        else
            -- check if the distribution is in the first part of the string (asdf default)
            distribution = distribution_version.parse_distribution(version_parts[1])
            if distribution then
                -- valid distribution found, treat second part as version
                version=version_parts[2]
            else
                -- invalid distribution name
                return nil
            end
        end
    end

    -- Convert version format for Foojay API
    version = distribution_version.convert_version_for_api(version)

    return {
        version = version,
        distribution = distribution,
        javafx_bundled = javafx_bundled,
    }
end

return distribution_version
