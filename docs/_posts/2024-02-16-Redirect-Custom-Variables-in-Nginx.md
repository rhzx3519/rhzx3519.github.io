---
layout: post
title:  "Redirect Custom Variables in Nginx"
date:   2024-02-16 13:00:27 +1100
categories: Network
tags: nginx auth
---


# Introduction
It is a common demand to leave some information after a proxy server handled the request. At present, we have 
an auth server and a chat server. The auth server stands between the user request and chat server used for check
the authentication. If the request is valid, we want to add user information into the request that can be sent to
the chat server. Here is how we set in the auth server and Nginx configuration.

# Set Response Header in Auth Server
```go
c.Header("X-Forwarded-User", string(userJson)) // It is a conventional way to declare custom variable with a prefix "X-"
```

# Configuration in Nginx
auth_request_set directive allows us set a $variable $value pair based on the response header returned by the proxy server.
$value must have a prefix with "upstream_http_", "x_forwarded_user" corresponds the header "X-Forwarded-User". Thus, the $value
is set to the $variable $user.

```shell
location /api/chat {
    auth_request /auth;
    error_page 401 = @error401;
    auth_request_set $user $upstream_http_x_forwarded_user;  // key config
    proxy_set_header X-Forwarded-User $user;            // key config

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
```

# Reference
1. [Module ngx_http_auth_request_module](https://nginx.org/en/docs/http/ngx_http_auth_request_module.html#auth_request_set)
