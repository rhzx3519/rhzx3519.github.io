---
layout: post
title:  "Nginx Configuration for Microservices"
date:   2024-02-01 13:54:27 +1100
categories: Architecture
tags: Web Architecture Nginx
---

![Architecture](/assets/images/nginx/nginx-configure.png)

# Introduction
This article introduces a nginx configuration used to deploy a multiple node service.
The aim is to serve the web service with only the 80 port exposed to external access.
There are three services in total, all these services are deployed in docker,
1. Frontend, together with Nginx as a static html server.
2. Auth-server, used to check requests' authorization.
3. Quote-server, business service.

# Reverse Proxy
In terms of the requests for common web pages, the route is host + /page, e.g. If you want to 
visit the main page, the route is host/main. For other requests for internal services, like auth or quote,
the route is start with /api/auth or /api/quote. We leverage the reverse proxy function on Nginx to redirect 
the requests to other services. Meanwhile, we will rewrite the uri when redirecting. e.g. /api/quote/ping will be 
rewritten as /ping, thus for quote server, it could avoid the influence from the deployment environment.

```nginx configuration
upstream quote {
	server quote-server;
}

server {
    listen       80;
    listen  [::]:80;
    server_name  localhost;

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
	      try_files $uri $uri/ /index.html; # Any route that doesn't have a file extension (e.g. /devices)
    }

    location /api/quote { # redirect any request starting with /api/quote
        rewrite ^/api/quote/(.*) /$1 break; # eliminate the /api/quote prefix
        proxy_set_header Host $http_host;
        proxy_pass http://quote-server;
    }
}
```

# Independent Authorization Check
We want to separate our authorization service from other business services as an independent service. Here we
leverage the auth_request module in Nginx. It enables us to intercept requests for specific routes, routes that need 
authorization to access. For valid requests, the auth server returns http ok status 200, then the requests will move on 
to the requested resources, while for invalid requests, these will be aborted with a http unauthorized code 401. 
```nginx configuration
upstream auth {
	server auth-server;
}

upstream quote {
	server quote-server;
}

server {
    listen       80;
    listen  [::]:80;
    server_name  localhost;

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
        try_files $uri $uri/ /index.html; # Any route that doesn't have a file extension (e.g. /devices)
    }

    location /api/quote {
        auth_request /auth;
        error_page 401 = @error401;
        auth_request_set $user $upstream_http_x_forwarded_user; 
        proxy_set_header X-Forwarded-User $user;

        rewrite ^/api/quote/(.*) /$1 break;
        proxy_set_header Host $http_host;
        proxy_pass http://quote-server;
    }

    # internal auth route
    location /auth {
        internal;
        proxy_set_header X-Original-URI $request_uri;
        proxy_set_header X-Original-METHOD $request_method;

        proxy_set_header Host $host;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_pass http://auth-server/v1/verify;
    }

    # redirect to frontend login page
    location @error401 {
        add_header Set-Cookie "NSREDIRECT=$scheme://$http_host$request_uri;Path=/";
        return 302 /signin;
    }
}
```

# Wrap Up
Nginx is a powerful tool to make us implement a distributed system in a elegant and convenient way.
