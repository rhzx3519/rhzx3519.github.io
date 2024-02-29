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

# Preventing goroutine leaks
How to ensure a single child goroutine is guaranteed to be cleaned up?
```go
// goroutine is stuck in write chan (<-strings)
doWork := func(done <-chan interface{}, strings <-chan string) <-chan interface{} {
    terminated := make(chan interface{})
    go func() {
        defer fmt.Println("doWork exited.")
        defer close(terminated)
        for {
            select {
            case s := <-strings: 
                // Do something interesting
                fmt.Println(s)
            case <-done:
                return
            }
        }
    }()
    return terminated
}
done := make(chan interface{})
terminated := doWork(done, nil)
go func() {
    // Cancel the operation after 1 second.
    time.Sleep(1 * time.Second)
    fmt.Println("Canceling doWork goroutine...")
    close(done)
}()
<-terminated
fmt.Println("Done.")
```
```go
// goroutine is stuck in write chan(randStream <-)
newRandStream := func(done <-chan interface{}) <-chan int {
    randStream := make(chan int)
    go func() {
      defer fmt.Println("newRandStream closure exited.")
      defer close(randStream)
      for {
        select {
          case randStream <- rand.Int():
          case <-done:
            return
        }
      }
    }()
    return randStream
}
done := make(chan interface{})
randStream := newRandStream(done)
fmt.Println("3 random ints:")
for i := 1; i <= 3; i++ {
  fmt.Printf("%d: %d\n", i, <-randStream)
} 
close(done)
// Simulate ongoing work
time.Sleep(1 * time.Second)
```
How we ensure goroutines are able to be stopped can differ
depending on the type and purpose of goroutine, but they all build on the
foundation of passing in a done channel.    

**convention**: _If a goroutine is responsible for creating a goroutine, it is also
responsible for ensuring it can stop the goroutine._

# The or-channel
At times you may find yourself wanting to _combine one or more done
channels into a single done channel which closes if any of its component
channels close._

```go
var or func(channels ...<-chan interface{}) <-chan interface{}
or = func(channels ...<-chan interface{}) <-chan interface{} {
    switch len(channels) {
        case 0:
            return nil
        case 1:
            return channels[0]
    }
    orDone := make(chan interface{})
    go func() {
        defer close(orDone)
        switch len(channels) {
            case 2:
                select {
                    case <-channels[0]:
                    case <-channels[1]:
                }
            default:
                select {
                    case <-channels[0]:
                    case <-channels[1]:
                    case <-channels[2]:
                    case <-or(append(channels[3:], orDone)...):
                }
        }
    }()
    return orDone
}
```
**examples**
```go
sig := func(after time.Duration) <-chan interface{}{
    c := make(chan interface{})
    go func() {
        defer close(c)
        time.Sleep(after)
    }()
    return c
}
start := time.Now()
<-or(
    sig(2*time.Hour),
    sig(5*time.Minute),
    sig(1*time.Second),
    sig(1*time.Hour),
    sig(1*time.Minute),
) 
fmt.Printf("done after %v", time.Since(start))
// done after 1.000216772s
```

# Error Handling
```go
type Result struct {
    Error error
    Response *http.Response
} 
checkStatus := func(done <-chan interface{}, urls ...string) <-chan Result {
    results := make(chan Result)
    go func() {
        defer close(results)
        for _, url := range urls {
            var result Result
            resp, err := http.Get(url)
            result = Result{Error: err, Response: resp}
            select {
                case <-done:
                    return
                case results <- result:
            }
        }
    }()
    return results
}

done := make(chan interface{})
defer close(done)

errCount := 0
for result := range checkStatus(done, "a", "https://www.google.com", "b", "c") {
    if result.Error != nil {
        fmt.Printf("error: %v\n", result.Error)
        errCount++
        if errCount >= 3 {
            fmt.Println("Too many errors, breaking!")
            break
        }
        continue
    }
    fmt.Printf("Response: %v\n", result.Response.Status)
}
//error: Get a: unsupported protocol scheme ""
//Response: 200 OK
//error: Get b: unsupported protocol scheme ""
//error: Get c: unsupported protocol scheme ""
//Too many errors, breaking!
```

# Best Practices for Constructing Pipelines
```go
generator := func(done <-chan interface{}, integers ...int) <-chan int {
    intStream := make(chan int)
    go func() {
        defer close(intStream)
        for _, i := range integers {
            select {
            case <-done:
                return
            case intStream <- i:
            }
        }
    }()
    return intStream
}
multiply := func(done <-chan interface{}, intStream <-chan int, multiplier int) <-chan int {
    multipliedStream := make(chan int)
    go func() {
        defer close(multipliedStream)
        for i := range intStream {
            select {
              case <-done:
                return
              case multipliedStream <- i*multiplier:
            }
        }
    }()
    return multipliedStream
}
add := func(done <-chan interface{}, intStream <-chan int, additive int) <-chan int {
    addedStream := make(chan int)
    go func() {
        defer close(addedStream)
        for i := range intStream {
            select {
                case <-done:
                    return
                case addedStream <- i+additive:
            }
        }
    }()
    return addedStream
}
done := make(chan interface{})
defer close(done)

intStream := generator(done, 1, 2, 3, 4)
pipeline := multiply(done, add(done, multiply(done, intStream, 2),
for v := range pipeline {
    fmt.Println(v)
}
//This code produces:
//6 10
//14
//18
```

# Some Handy Generators

## Repeat & Take
This function will repeat the values you pass to it infinitely until you tell it to
stop.
```go
repeat := func(done <-chan interface{}, values ...interface{}) <-chan interface{} {
  valueStream := make(chan interface{})
  go func() {
    defer close(valueStream)
    for {
      for _, v := range values {
        select {
          case <-done:
            return
          case valueStream <- v:
        }
      }
    }
  }()
  return valueStream
}
```

This pipeline stage will only take the first num items off of its incoming
valueStream and then exit.
```go
take := func(done <-chan interface{}, valueStream <-chan interface{}, num int) <-chan interface{} {
  takeStream := make(chan interface{})
  go func() {
    defer close(takeStream)
    for i := 0; i < num; i++ {
      select {
        case <-done:
          return
        case takeStream <- <- valueStream:
      }
    }
  }()
  return takeStream
}
```

```go
done := make(chan interface{})
defer close(done)
for num := range take(done, repeat(done, 1), 10) {
    fmt.Printf("%v ", num)
}
//Running this code produces:
//1 1 1 1 1 1 1 1 1 1
```

## RepeatFn
Let’s create another repeating generator, but this
time, let’s create one that repeatedly calls a function.
```go
repeatFn := func(done <-chan interface{}, fn func() interface{}) <-chan interface{} {
  valueStream := make(chan interface{})
  go func() {
    defer close(valueStream)
    for {
      select {
        case <-done:
            return
        case valueStream <- fn():
      }
    }
  }()
  return valueStream
}
```

Let’s use it to generate 10 random numbers:
```go
done := make(chan interface{})
defer close(done)
rand := func() interface{} { return rand.Int()}
for num := range take(done, repeatFn(done, rand), 10) {
    fmt.Println(num)
}
//This produces:
//5577006791947779410
//8674665223082153551
//6129484611666145821
//4037200794235010051
//3916589616287113937
//6334824724549167320
//605394647632969758
//1443635317331776148
//894385949183117216
//2775422040480279449
```

# Reference
1. [Concurrency in Go](https://www.oreilly.com/library/view/concurrency-in-go/9781491941294/)
