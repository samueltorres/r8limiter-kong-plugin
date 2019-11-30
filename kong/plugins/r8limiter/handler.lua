local resty_http = require "resty.http"
local cjson = require "cjson.safe"
local jwtParser = require "kong.plugins.jwt.jwt_parser"
local r8limiter = require("kong.plugins.base_plugin"):extend()

local time_units_map = {
    [0] = "unkown",
    [1] = "second",
    [2] = "minute",
    [3] = "hour",
    [4] = "day"
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

function r8limiter:new() r8limiter.super.new(self, "r8limiter") end

function r8limiter:access(config)
    r8limiter.super.access(self)

    local rate_limit_request = {
        domain = config.domain,
        descriptors = {{entries = {}}}
    }

    -- handle descriptor from ip address 
    if config.descriptor.ip_address then
        local ip_address = kong.client.get_forwarded_ip()
        table.insert(rate_limit_request.descriptors[1].entries, {key = "ip_address", value = ip_address})
    end

    -- handle descriptors from jwt claims
    local jwt = retrieve_auth_token()
    if jwt then
        local claims, err = get_claims_from_jwt(jwt)
        if not err then
            for i, c in ipairs(config.descriptor.jwt_claims) do
                local key = c.key or c.claim
                local value = claims[c.claim]

                if value then
                    table.insert(rate_limit_request.descriptors[1].entries, {key = key, value = value})
                end
            end
        end
    end
    
    -- handle http headers
    local headers = kong.request.get_headers()
    for i, c in ipairs(config.descriptor.headers) do
        local key = c.key or c.header
        local value = headers[c.header]

        if value then
            table.insert(rate_limit_request.descriptors[1].entries, {key = key, value = value})
        end
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
        
        local unit = time_units_map[rate_limit_response.statuses[1].current_limit.unit] or "unknown"
        local limit_remaining = rate_limit_response.statuses[1].limit_remaining or 0
        
        headers["X-RateLimit-Limit-Unit"] = unit
        headers["X-RateLimit-Remaining"] = limit_remaining
        headers["X-RateLimit-Limit"] = rate_limit_response.statuses[1].current_limit.requests_per_unit
        
        kong.ctx.plugin.headers = headers
    end
    
    if rate_limit_response['overall_code'] == 2 then
        return kong.response.exit(429, {message = "too many requests"})
    end

end

function r8limiter:header_filter(_)
    local headers = kong.ctx.plugin.headers
    if headers then kong.response.set_headers(headers) end
end

r8limiter.PRIORITY = 1000

return r8limiter
