---
layout: post
title:  "Support Websocket in Nginx"
date:   2024-02-15 21:00:27 +1100
categories: Network
tags: nginx websocket network
---


# Introduction
Websocket is an application layer protocol enabling bidirectional communication based on TCP transport protocol,
compared with http protocol which only allows client sends to server. So when we want to realize some functions like
pushing notification or chatting with different users, it is intuitive to utilize the websocket.
However, it takes few more steps to make the Nginx to support websocket through configuration.

# Key Configuration
Whenever we receive websocket requests in nginx, before redirect to other server, we need to set the
proxy http version and proxy header to support websocket.

```shell
    # enable websocket
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
```

# Whole Configuration

e.g. we have a chat server preparing to receive websocket requests, the whole nginx configuration will like below:

```shell

upstream chat {
    server chat-server;
}

server {
    listen       80;
    listen  [::]:80;
    server_name  localhost;

    #access_log  /var/log/nginx/host.access.log  main;

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
        try_files $uri $uri/ /index.html; # Any route that doesn't have a file extension (e.g. /devices)
    }

    location /api/chat {
        rewrite ^/api/chat/(.*) /$1 break;
        proxy_pass http://chat-server;
        # enable websocket
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }


    # redirect to frontend login page
    location @error401 {
        add_header Set-Cookie "NSREDIRECT=$scheme://$http_host$request_uri;Path=/";
        return 302 /signin;
    }

    # redirect server error pages to the static page /50x.html
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}

server {
    listen                  443 ssl;
    listen                  [::]:443 ssl;
    server_name             localhost;
    ssl_certificate         /root/ssl/cert.pem;
    ssl_certificate_key     /root/ssl/key.pem;

    location / {
        proxy_pass "http://localhost/";

        # enable websocket
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    error_page   500 502 503 504  /50x.html;
}

```

# Wrap Up
Don't forget set the protocol as "wss" instead of "ws" when using 443 port to send websocket messages.
