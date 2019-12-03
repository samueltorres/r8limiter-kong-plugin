local resty_http = require "resty.http"
local cjson = require "cjson.safe"
local jwtParser = require "kong.plugins.jwt.jwt_parser"
local r8limiter = require("kong.plugins.base_plugin"):extend()

local time_units_description = {
    [0] = "unkown",
    [1] = "second",
    [2] = "minute",
    [3] = "hour",
    [4] = "day"
}

local time_unit_in_seconds = {
    [0] = 0,
    [1] = 1,
    [2] = 60,
    [3] = 3600,
    [4] = 86400,
}

local function retrieve_auth_token()
    kong.log.debug("FF-retrieve_token:")

    local access_token = kong.request.get_header("authorization")
    if access_token then
        local parts = {}
        for v in access_token:gmatch("%S+") do
            table.insert(parts, v)
        end

        if #parts == 2 and (parts[1]:lower() == "bearer") then
            return parts[2]
        end
    end

    return access_token
end

local function get_claims_from_jwt(jwt)
    local jwt_table, err = jwtParser:new(jwt)
    if err ~= nil then
        kong.log.err("error parsing jwt: ", err, " jwt: ", jwt)
        return nil, err
    end

    return jwt_table["claims"], err
end

local function get_ratelimit_reset(unit)
    local now = os.time()
    local reset_time = now - (now % time_unit_in_seconds[unit]) + time_unit_in_seconds[unit]
    local reset_after_seconds = time_unit_in_seconds[unit] - (now % time_unit_in_seconds[unit])

    return reset_time , reset_after_seconds
end

function r8limiter:new() r8limiter.super.new(self, "r8limiter") end

function r8limiter:access(config)
    r8limiter.super.access(self)

    local rate_limit_request = {
        domain = config.domain,
        descriptors = {}
    }

    for i, desc in ipairs(config.descriptors) do
        local d = {entries={}}

        -- handle descriptor from ip address 
        if desc.ip_address then
            local ip_address = kong.client.get_forwarded_ip()
            table.insert(d.entries, {key = "ip_address", value = ip_address})
        end

        -- handle descriptors from jwt claims
        local jwt = retrieve_auth_token()
        if jwt then
            local claims, err = get_claims_from_jwt(jwt)
            if not err and desc.jwt_claims then
                for i, c in ipairs(desc.jwt_claims) do
                    local key = c.key or c.claim
                    local value = claims[c.claim]

                    if value then
                        table.insert(d.entries, {key = key, value = value})
                    end
                end
            end
        end
        
        -- handle http headers
        local headers = kong.request.get_headers()
        if desc.headers then
            for i, c in ipairs(desc.headers) do
                local key = c.key or c.header
                local value = headers[c.header]
    
                if value then
                    table.insert(d.entries, {key = key, value = value})
                end
            end
        end

        table.insert(rate_limit_request.descriptors, d)

    end

    -- rate limiter service request setup
    local req_body, err = cjson.encode(rate_limit_request)
    if not req_body then
        kong.log.err("could not JSON encode ratelimit request body", err)
        return
    end

    local httpc = resty_http.new()
    httpc:set_timeout(config.server.timeout)
    httpc:connect(config.server.host, config.server.port)
    local res, err = httpc:request{
        method = "POST",
        path = "/ratelimit",
        body = req_body
    }

    if not res then
        kong.log.err("could not make request to the ratelimiter server", err)
        return
    end

    local content = res:read_body()
    local rate_limit_response, err = cjson.decode(content)
    if not rate_limit_response then
        kong.log.err("could not parse ratelimiter server response", err)
        return
    end

    -- add rate limiting headers
    local headers = {}
    if rate_limit_response.statuses[1] then
        
        local selected_status = rate_limit_response.statuses[1]
        for i, status in ipairs(rate_limit_response.statuses) do
            -- if the unit is lower - e.g - minutes vs seconds, seconds should be used
            if status.current_limit.unit < selected_status.current_limit.unit then
                selected_status = status
            elseif status.current_limit.unit == selected_status.current_limit.unit then
                -- check if theres a status with less requests remaining
                if (status.limit_remaining or 0) < (selected_status.limit_remaining or 0) then
                    selected_status = status
                end
            end
        end

        local reset, retry_after = get_ratelimit_reset(selected_status.current_limit.unit)
        headers["X-RateLimit-Limit"] = selected_status.current_limit.requests_per_unit
        headers["X-RateLimit-Remaining"] = selected_status.limit_remaining or 0
        headers["X-RateLimit-Reset"] = reset

        if rate_limit_response.overall_code == 2 then
            kong.log.err("retry-after", retry_after)
            headers["Retry-After"] = retry_after
        end

        kong.ctx.plugin.headers = headers
    end
    
    if rate_limit_response.overall_code == 2 then
        return kong.response.exit(429, {message = "too many requests"})
    end

end

function r8limiter:header_filter(_)
    local headers = kong.ctx.plugin.headers
    if headers then kong.response.set_headers(headers) end
end

r8limiter.PRIORITY = 1000

return r8limiter
