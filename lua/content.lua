local upstream_sh_data = ngx.shared.upstream_sh_data

local args, err = ngx.req.get_uri_args()
local re =  upstream_sh_data:get(args["up"])
ngx.say(re)
