---
layout: post
title:  "Back-of-Envelope Estimation"
date:   2024-03-08 19:00:00 +1100
categories: system design
tags: system design backend architecture
---

## Metrics
After clarify the scope and limit of a problem in the system design interview, it is always a good idea to make 
a preliminary estimation of some metrics for our system. This will help us later when we will be focusing on scaling, 
partitioning, load balancing and caching. 

There are several metrics we need to determine at the first place, we could split the metrics into two categories:
**writing** and **reading**. Following metrics are to be estimated:
- Writing QPS/TPS
- Reading QPS/TPS
- Writing Band Width
- Reading Band Width
- Data Storage(for writing request)
- Cache Memory(for reading request)

And there are some common rules we can apply into our estimation.
- The ratio between writing and reading requests is **100:1**.
- Hot data abides by the **20/80** rule.
- Persistence data expiration is **5-10 years**.

## Examples
With all the prerequisite knowledge we have, Let practice it with a simple example. 
A system only has two API, a reading and a writing API, and it has **500M** writing requests per month.  
Please make an estimation for this system.

**Writing QPS** = `500M / (3600s * 24h * 30day) ~= 500M / (100K * 30day) ~= 200`, Here we use a rough estimation for a common
computation: `3600*24 ~= 100k`.    
**Reading QPS** = `200*100 ~= 20K`.   

Let's assume each request data is 500 bytes.
**Writing Band Width** = `200*500 ~= 100KB/s`.   
**Reading Band Width** = `20K * 500 ~= 10MB/s`.

Let's assume the data expires in 5 years.
**Data Storage** = `500M * 12month * 5 year * 500bytes ~= 30G * 500bytes ~= 15TB`     

Let's assume the cache expires in 1 day, and only the hot data is cached.
**Cache Memory** = `20K * 3600s * 24h * 500bytes * 0.2 ~= 20K * 100K * 100bytes ~= 200GB`

Here we have all the critical metric estimation for our system:
- Writing QPS/TPS: 200
- Reading QPS/TPS: 20K
- Writing Band Width: 100KB/s
- Reading Band Width: 10MB/s
- Data Storage(for writing request): 15TB
- Cache Memory(for reading request): 200GB

## Wrap up
This is a common law for us to apply in every back-of-envelope estimate of system design.


# Reference
1. [Grokking-System-Design](https://github.com/Jeevan-kumar-Raj/Grokking-System-Design)
