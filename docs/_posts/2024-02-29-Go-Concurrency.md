---
layout: post
title:  "Go Concurrency Tips"
date:   2024-02-29 18:06:00 +1100
categories: Go
tags: go goroutine concurrency
---

# Introduction
Here is some tips of go concurrency regarding the book "Concurrency in Go".

# Chan
I’ll define ownership as being a goroutine which instantiates, writes, and closes a channel.
**Channel owners** have a write-access view into the channel (chan or chan<-), and 
**channel utilizers** only have a read-only view into the channel (<-chan).

```go
chanOwner := func() <-chan int {
    resultStream := make(chan int, 5)
    go func() {
        defer close(resultStream)
        for i := 0; i <= 5; i++ {
        resultStream <- i
    }}()
    return resultStream
}
resultStream := chanOwner()
for result := range resultStream {
    fmt.Printf("Received: %d\n", result)
} 
fmt.Println("Done receiving!")
```


# Reference
1. [Concurrency in Go](https://www.oreilly.com/library/view/concurrency-in-go/9781491941294/)
