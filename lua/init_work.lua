local new_timer = ngx.timer.every
local process = require "ngx.process"   
local work_type = process.type()
if work_type ~= "privileged agent" then
  return
end


local watch_endpoint = require("k8s-wath-endpoint-timer")
local ok,err = ngx.timer.at(0.001,watch_endpoint["begin_watch"])
if not ok then
  ngx.log(ngx.ERR, "failed to create watch_endpoint timer",err)
end
local ok,err = new_timer(190,watch_endpoint["begin_watch"])
if not ok then
  ngx.log(ngx.ERR, "failed to create watch_endpoint timer",err)
end

local watch_crd = require("k8s-wath-crd-timer")
local ok,err = ngx.timer.at(0.001,watch_crd["begin_watch"])
if not ok then
  ngx.log(ngx.ERR, "failed to create watch_crd timer",err)
end
local ok,err = new_timer(190,watch_crd["begin_watch"])
if not ok then
  ngx.log(ngx.ERR, "failed to create watch_crd timer",err)
end

local reload_nginx = require("wait-for-reload-nginx")
local ok,err = new_timer(1,reload_nginx["begin_watch"])
if not ok then
  ngx.log(ngx.ERR, "failed to create reload_nginx timer",err)
end