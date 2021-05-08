FROM openresty/openresty:1.19.3.1-8-centos7
COPY lua /usr/local/openresty/nginx/lua
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
RUN mkdir -p /usr/local/openresty/nginx/conf/conf.d/
RUN mkdir -p /usr/local/openresty/nginx/logs 
COPY check-up.conf /usr/local/openresty/nginx/conf/conf.d/check-up.conf 
