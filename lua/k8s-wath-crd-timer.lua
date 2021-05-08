local ngx_balancer = require("ngx.balancer")
local upstream_map = require("upstream_map")
local json = require("cjson")
local resty_signal = require "resty.signal"
local shell = require "resty.shell"
local math_random =  math.random
local gmatch = ngx.re.gmatch
local getenv = os.getenv
local concat = table.concat
local prefix = ngx.config.prefix()
local _M = {}
local upstream_sh_data = ngx.shared.upstream_sh_data
local lrucache = require "resty.lrucache" 
local cache, err = lrucache.new(500)  -- allow up to 500 items in the cache
local the_last_resourceVersion_key = "the_last_resourceVersion_key"

local function del_sh_data(crdnginx_name)
  local ok = upstream_sh_data:delete(crdnginx_name)
  if not ok then
     ngx.log(ngx.ERR,"can not delete nginx_sh_data:",crdnginx_name)
     return false
  end
  return true
end
local function set_sh_data(crdnginx_name,upstream_data_str)
  local ok = upstream_sh_data:set(crdnginx_name,upstream_data_str)
  if not ok then
     ngx.log(ngx.ERR,"can not set sh data:",crdnginx_name)
     return false
  end
  return true
end

local function hand_data(buffer)

  local crdnginx_info = json.decode(buffer)
  if not crdnginx_info then
    ngx.log(ngx.ERR,"json code buffer failed")
    return false
  end

  local r_type = crdnginx_info["type"]
  local svc_name = crdnginx_info["object"]["metadata"]["name"]
  local svc_namespace = crdnginx_info["object"]["metadata"]["namespace"]
  local resourceVersion = crdnginx_info["object"]["metadata"]["resourceVersion"]
  local data = crdnginx_info["object"]["spec"]["data"]
  local config_type = crdnginx_info["object"]["spec"]["config-type"] 


  local crdnginx_name = svc_name.."-"..svc_namespace..".conf"
  local rv_name = svc_name.."-"..svc_namespace..".resourceVersion"
  if r_type == "DELETED" and config_type ~= "main" then

    local r = del_sh_data(crdnginx_name)
    r= os.remove(prefix.."/conf/conf.d/"..crdnginx_name)
    if not r then
      ngx.log(ngx.ERR, "remove file failed:",crdnginx_name)
      return false
    else
      local r_sh = del_sh_data(rv_name)
      local r_sh = set_sh_data(the_last_resourceVersion_key,resourceVersion)
      return true
    end
  else
    local old_resourceVersion = upstream_sh_data:get(rv_name)
    --ngx.log(ngx.ERR, rv_name)
    --ngx.log(ngx.ERR, "old_resourceVersion:",old_resourceVersion," resourceVersion:",resourceVersion)
    if old_resourceVersion == resourceVersion then
      
      return true
    else
      --ngx.log(ngx.ERR, "miss match resourceVersion")
      local file_path 
      if config_type == "main" then
        file_path = prefix.."/conf/"
      else
        file_path = prefix.."/conf/conf.d/"
      end

      local file = io.open(file_path..crdnginx_name,"w+")
      if file then
        local r_w_f = file:write(data)
        if r_w_f  then
          file:close()
          --local r_sh = set_sh_data(crdnginx_name,data)
          local r_sh = set_sh_data(rv_name,resourceVersion)
          local r_sh = set_sh_data(the_last_resourceVersion_key,resourceVersion)
          return true
        else
          ngx.log(ngx.ERR, "write nginx file failed")
          return false
        end
      else
        ngx.log(ngx.ERR, "open nginx file failed")
        return false
      end
    end
  end

end

function _M.begin_watch(premature)
  --ngx.log(ngx.ERR, "pid:",ngx.worker.pid()) 
  if premature then
    local ok_set = cache:delete("is_watch_crd_running")
    return
  end
  local is_watch_crd_running = cache:get("is_watch_crd_running")
  if is_watch_crd_running and is_watch_crd_running == 1 then
    ngx.log(ngx.ERR, "is_watch_crd_running == 1")
    return
  end

  local uri = '/apis/mycrd.com/v1/namespaces/crdnginx/nginxs?watch=true'
  -- you must set in nginx.confenv

  local token = getenv("kube_config_token")
  local kube_config_token = 'Bearer '..token
  local kube_config_host = getenv("kube_config_host")
  local kube_config_port = getenv("kube_config_port")

  local httpc = require("resty.http").new()

  ::connect_again::
  --ngx.log(ngx.ERR, "begin connect_again")
  -- must  (in seconds) > sum(set_timeouts)
  local ok_set = cache:set("is_watch_crd_running",1,247)

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
      local ok_set = cache:set("is_watch_crd_running",1,247)
      
      ngx.sleep(0.1)
      
      local buffer, err, partial = httpc.sock:receive("*l")
      local ok_set = set_sh_data("sock_receive_some_data",ngx.time())
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

    --ngx.log(ngx.ERR, 'begin hand')
    local buffer_str = concat(buffer_tmp)
    local regex = '{.+?"}}}'
    local it,err = gmatch(buffer_str,regex,"jo")
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
        
        local ok, re = pcall(hand_data, m[0])
        if not ok or not re then
          ngx.log(ngx.ERR, 'hand_kube_crdnginx faild')
          
        end
      end
    end

    --ngx.log(ngx.ERR, 'end 1')

  end
  

  local ok, err = httpc:close()
  goto connect_again

end

return _M

