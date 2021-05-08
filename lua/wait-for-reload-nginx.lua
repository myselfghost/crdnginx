local upstream_sh_data = ngx.shared.upstream_sh_data
local _M = {}
local lrucache = require "resty.lrucache" 
local shell = require "resty.shell"


local function set_sh_data(crdnginx_name,upstream_data_str)
    local ok = upstream_sh_data:set(crdnginx_name,upstream_data_str)
    if not ok then
       ngx.log(ngx.ERR,"can not set sh data:",crdnginx_name)
       return false
    end
    return true
end

local function reload_nginx()
    local ok, stdout, stderr, reason, status = shell.run("openresty -t")
    if ok then
      local okk, stdout, stderr, reason, status = shell.run("openresty -s reload")
      if okk then
        return true
      else
        ngx.log(ngx.ERR,"nginx -s reload failed:",stderr)
        return false
      end
    else
      ngx.log(ngx.ERR,"nginx -t failed:",stderr)
      return false
    end
  
end
function _M.begin_watch(premature)
    --ngx.log(ngx.ERR, "pid:",ngx.worker.pid()) 
    if premature then
      return
    end
    --local begin_time = tobumber(upstream_sh_data:get("begin_sock_receive"))
    local receive_time = tonumber(upstream_sh_data:get("sock_receive_some_data"))
    if not receive_time then 
        return
    end
    local time_now = ngx.time()
    if (time_now - receive_time) > 3 then
        --ngx.log(ngx.ERR,"(time_now - receive_time) > 3")
        local the_last_rv = upstream_sh_data:get("the_last_resourceVersion_key")
        local the_nginx_reload_rv = upstream_sh_data:get("the_nginx_reload_resourceVersion_key")
        if the_last_rv ~= the_nginx_reload_rv then
            --ngx.log(ngx.ERR, "the_last_rv ~= the_nginx_reload_rv:",the_last_rv," reload_rv:",the_nginx_reload_rv) 
            local r = reload_nginx()
            if r then
                set_sh_data("the_nginx_reload_resourceVersion_key",the_last_rv)
            end
        end
    end
end

return _M