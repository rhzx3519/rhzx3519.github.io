---
layout: post
title:  "A Backbone Architecture of A typical Web Application"
date:   2024-02-01 13:54:27 +1100
categories: Architecture
tags: Web Architecture
---

![Architecture](/assets/images/web-archi/archi.png)

# Introduction
This article introduce a typical architecture of a web application, as well
as the continuous integration process related. We leverage React to develop frontend 
business and use Nginx to deploy the frontend package. For backend, we adopt the Gin framework, 
which is very popular within Go, to implement our server business. In terms of the persistance level, 
we leverage MySql to save our data. All these process are deployed in containers in the purpose of quick
deployment.
...
