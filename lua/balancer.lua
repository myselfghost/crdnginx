local ngx_balancer = require("ngx.balancer")
local json = require("cjson.safe")
local math_random =  math.random
local _M = {}
local upstream_sh_data = ngx.shared.upstream_sh_data
local lrucache = require "resty.lrucache"
local ngx_var = ngx.var
local cache, err = lrucache.new(50000)  -- allow up to 500 items in the cache

local function get_balancer()
  local backend_name = ngx_var.proxy_upstream_name
  -- use lrucache to cache table
  local upstream_data = cache:get(backend_name)
  if not upstream_data then
      --ngx.log(ngx.ERR,"lua get_balance begin get sh ")
      local upstream_data_str = upstream_sh_data:get(backend_name)
      if not upstream_data_str then
        ngx.log(ngx.ERR,"lua get_balance get sh failed")
        return false
      end
  
      local upstream_data = json.decode(upstream_data_str)
      if not upstream_data then
        ngx.log(ngx.ERR,"lua get_balancer json.decode failed")
        return false
      else
        local ok,err = cache:set(backend_name,upstream_data,1)
        return upstream_data
      end
   
      
  end
  return upstream_data
end

local function get_host_port(upstream_data_t)
  local upstream_data_t = upstream_data_t
  local addresses = upstream_data_t["addresses"]
  local port = upstream_data_t["port"]
  if not addresses or not port then
    ngx.log(ngx.ERR,"lua get_host_port not host and port")
    return false,false
  end
  if #addresses == 1 then
    return addresses[1],port
  end
  local num = math_random(1,#addresses)
  return addresses[num],port 
end

function _M.balance()
  local balancer = get_balancer()
  if not balancer then
    ngx.log(ngx.ERR,"lua get_balancer failed")
    return
  end

  local host, port = get_host_port(balancer)
  if not (host and port) then
    ngx.log(ngx.ERR,
      string.format("balancer-by-lua: host or port is missing, balancer: %s, host: %s, port: %s", host, port))
    return
  end
  -- you must set proxy_next_upstream_tries 3; in nginx.conf
  ngx_balancer.set_more_tries(1)

  local ok, err = ngx_balancer.set_current_peer(host, port)
  if not ok then
    ngx.log(ngx.ERR, "balancer-by-lua: error while setting current upstream peer to " .. tostring(err))
  end
end

return _M

