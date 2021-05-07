# crdnginx
Another ingress, you can use the original nginx way to write nginx configuration files

## how to install 

please note: 

1. edit install-crdnginx.yml ,change env, kube_config_host,kube_config_port,kube_config_token
2. edit install-crdnginx.yml ,change nodeAffinity

```
kubectl apply -f install-crdnginx.yml
```


## how to add a http server
edit a server.yml, then kubectl apply -f server.yml

please note: 
  1. name must end whith ".conf"
  2. namespace  must be "crdnginx"
  3. config-type: http-server
  4. data are your config
  5. must have```set $proxy_upstream_name "yourservicename-namespace-port"```

```
apiVersion: "mycrd.com/v1"
kind: CrdNginx
metadata:
  name: test.conf
  namespace: crdnginx
spec:
  config-type: http-server
  data: |
        server {
            listen 80;
            server_name test.com;
            set $proxy_upstream_name "yourservicename-namespace-port";
            location / {
                proxy_pass http://upstream_balancer;
            }

        }
```

## how to create a upstream 
edit your service in your K8S,add a lable. crdnginx will auto create a upstram named 'yourservicename-namespace-port'
```
kubectl edit svc official-website

```

```
apiVersion: v1
kind: Service
metadata:
  labels:
    dy-up: http
  name: official-website
  namespace: default
```

## how to check upstream in crdnginx
```
curl http://crdnginx_ip:12345/?up=yourservicename-namespace-port
```

## hot use different upstream in different location
```
apiVersion: "mycrd.com/v1"
kind: CrdNginx
metadata:
  name: test2.conf
  namespace: crdnginx
spec:
  config-type: http-server
  data: |
        server {
            listen 80;
            server_name test2.com;
            set $proxy_upstream_name "yourservicename-namespace-port";
            location / {
                proxy_pass http://upstream_balancer;
            }
            location /2 {
                set $proxy_upstream_name "yourservicename-namespace-port2";
                proxy_pass http://upstream_balancer;
            }

        }
```

## how to A/B testing
```
apiVersion: "mycrd.com/v1"
kind: CrdNginx
metadata:
  name: test3.conf
  namespace: crdnginx
spec:
  config-type: http-server
  data: |
        server {
            listen 80;
            server_name test3.com;
            set $proxy_upstream_name "yourservicename-namespace-port";
            location / {
                proxy_pass http://upstream_balancer;
            }
            location /3 {
                set_by_lua_block $proxy_upstream_name {
                    local math_random =  math.random
                    local num = math_random(1,100)
                    if num > 80 then
                       return "yourservicename-namespace-port1"
                    else
                       return "yourservicename-namespace-port2"
                    end
                }
            }

        }
``` 

## how to add grpc server

```
apiVersion: "mycrd.com/v1"
kind: CrdNginx
metadata:
  name: test4.conf
  namespace: crdnginx
spec:
  config-type: http-server
  data: |
        server {
            listen 8888;
            server_name test4.com;
            set $proxy_upstream_name "yourservicename-namespace-port";
            location / {
                grpc_pass grpc://upstream_balancer;
            }

        }
```