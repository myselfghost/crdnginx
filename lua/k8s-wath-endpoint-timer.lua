local ngx_balancer = require("ngx.balancer")
local upstream_map = require("upstream_map")
local json = require("cjson")
local math_random =  math.random
local gmatch = ngx.re.gmatch
local getenv = os.getenv
local concat = table.concat
local _M = {}
local upstream_sh_data = ngx.shared.upstream_sh_data
local lrucache = require "resty.lrucache" 
local cache, err = lrucache.new(500)  -- allow up to 500 items in the cache
 

local function del_sh_data(proxy_upstream_name)
  local ok = upstream_sh_data:delete(proxy_upstream_name)
  if not ok then
     ngx.log(ngx.ERR,"can not delete sh  upstream:",proxy_upstream_name)
     return false
  end
  return true
end
local function set_sh_data(proxy_upstream_name,upstream_data_str)
  local ok = upstream_sh_data:set(proxy_upstream_name,upstream_data_str)
  if not ok then
     ngx.log(ngx.ERR,"can not set upstream_sh_data")
     return false
  end
  return true
end

local function hand_kube_endpoints(buffer)
  local endpoints_info = json.decode(buffer)
  if not endpoints_info then
    ngx.log(ngx.ERR,"json code buffer failed")
    return false
  end

  local r_type = endpoints_info["type"]
  local svc_name = endpoints_info["object"]["metadata"]["name"]
  local svc_namespace = endpoints_info["object"]["metadata"]["namespace"]
  local resourceVersion = endpoints_info["object"]["metadata"]["resourceVersion"]
  local addresses = endpoints_info["object"]["subsets"][1]["addresses"]
  local ports = endpoints_info["object"]["subsets"][1]["ports"]

  local proxy_upstream_name
  if r_type == "DELETED" then
    local port = ports[1]["port"]
    proxy_upstream_name = svc_name.."-"..svc_namespace.."-"..port
    local r = del_sh_data(proxy_upstream_name)
    if not r then
      return false
    else
      return true
    end
  else
    local upstream_data_tp = {}
    local ip_tb = {}
    for k,v in ipairs(addresses) do
      ip_tb[#ip_tb+1] = v["ip"]
    end


    for k,v in ipairs(ports) do
      proxy_upstream_name = svc_name.."-"..svc_namespace.."-"..v["port"]
      upstream_data_tp["port"] = v["port"]
      upstream_data_tp["addresses"] = ip_tb
      local upstream_data_str = json.encode(upstream_data_tp)
      if upstream_data_str then
        local r = set_sh_data(proxy_upstream_name,upstream_data_str)        
      else
        ngx.log(ngx.ERR,"json code upstream_sh_data failed")        
      end
    end
    return true


  end


end



function _M.begin_watch(premature)
  if premature then
    local ok_set = cache:delete("is_watch_endpoint_running")
    return
  end
  local is_watch_endpoint_running = cache:get("is_watch_endpoint_running")
  if is_watch_endpoint_running and is_watch_endpoint_running == 1 then
    ngx.log(ngx.ERR, "is_watch_endpoint_running == 1")
    return
  end

  local uri = '/api/v1/endpoints?watch=true&labelSelector=dy-up+in+(http,stream)'
  -- you must set in nginx.confenv
  --env kube_config_host;
  --env kube_config_port;
  --env kube_config_token;
  local token = getenv("kube_config_token")
  local kube_config_token = 'Bearer '..token
  local kube_config_host = getenv("kube_config_host")
  local kube_config_port = getenv("kube_config_port")

  local httpc = require("resty.http").new()

  ::connect_again::
  --ngx.log(ngx.ERR, "begin connect_again")
  -- must  (in seconds) > sum(set_timeouts)
  local ok_set = cache:set("is_watch_endpoint_running",1,247)

  -- (connect_timeout, send_timeout, read_timeout) in milliseconds
  httpc:set_timeouts(3000,3000,240000)
  -- First establish a connection
  local ok, err = httpc:connect({
      scheme = "https",
      host = kube_config_host,
      port = kube_config_port,
      ssl_verify=false,
  })
  if not ok then
      ngx.log(ngx.ERR, "connection failed: ", err)
      ngx.sleep(1)
      goto connect_again
      
  end
  
  -- Then send using `request`, supplying a path and `Host` header instead of a
  -- full URI.
  ::request_again::
  local res, err = httpc:request({
      path = uri,
      headers = {
          ["Authorization"] = kube_config_token,
          ["Content-Type"] = "application/json"
      },
  })
  if not res then
      ngx.log(ngx.ERR, "request failed: ", err)
      ngx.sleep(1)
      goto request_again
  end
 


  local is_break_first = false
  while true do
    local buffer_tmp = {}
    
    if is_break_first then
      break
    end
    ngx.sleep(0.1)
    while true do
      local ok_set = cache:set("is_watch_endpoint_running",1,247)
      ngx.sleep(0.1)
      --ngx.log(ngx.ERR, 'begin 2 repeat')
      local buffer, err, partial = httpc.sock:receive("*l")
      if not buffer then
        --ngx.log(ngx.ERR, 'not buffer,err:',err)
        is_break_first = true
        break
      end
      if buffer == "" then
        --ngx.log(ngx.ERR, 'buffer kong')
        break
      end
      if buffer == "0" then
        --ngx.log(ngx.ERR, 'buffer 0')
        is_break_first = true
        break
      end
      if not tonumber(buffer, 16) then
        --ngx.log(ngx.ERR, 'buffer not 16 size')
        buffer_tmp[#buffer_tmp+1] = buffer
      end
    end
    
    local buffer_str = concat(buffer_tmp)
    local it,err = gmatch(buffer_str,'{.+?]}}',"jo")
    if not it then
      ngx.log(ngx.ERR, "error: ", err)
    else
      while true do
        local m, err = it()
        if err then
            ngx.log(ngx.ERR, "error: ", err)
            return
        end  
        if not m then
            -- no match found (any more)
            break
        end
        
        local ok, re = pcall(hand_kube_endpoints, m[0])
        if not ok or not re then
          ngx.log(ngx.ERR, 'hand_kube_endpoints faild')
          
        end

      end
    end


  end

  local ok, err = httpc:close()
  goto connect_again

end

return _M
