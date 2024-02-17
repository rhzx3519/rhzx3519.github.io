---
layout: post
title:  "When does a Goroutine terminate?"
date:   2024-02-16 13:46:00 +1100
categories: Go
tags: go goroutine thread process
---


# Question
If we have a main goroutine(M), a setup goroutine(S), and a work goroutine(W). First, we boot the program with the M never 
terminated. Then we boot the S within which we start the W. The question is S is alike a parent of W, if S is terminated,
will W be terminated?

```go

type Bar struct {}

func (b *Bar) doing() {
    for {
        fmt.Println("I'm working...")
        time.Sleep(time.Second * 5)
    }
}

type Foo struct {
    Bars     map[*Bar]bool
    Register chan *Bar
}

func (f *Foo) run() {
    timer := time.NewTimer(time.Second * 30)
    for {
        select {
        case bar := <-f.Register:
            f.Bars[bar] = true
        case <-timer.C:
            return
        }
    }
}

func main() {
    f := Foo{
        Bars:     make(map[*Bar]bool),
        Register: make(chan *Bar),
    }

    go func() { // Goroutine: S
        defer fmt.Println("I'm done")
        time.Sleep(time.Second) // ensure f is running
        b := &Bar{}
        f.Register <- b
        go b.doing() // Goroutine: W
    }()

    f.run() // GoRoutine: main
}

```

# Wrap Up
Actually, W will keep running until it returns or the whole program is finished. Every goroutine is equivalent, it is not a
tree model like Linux process/thread or Java thread in other languages. If the parent is terminated, the child will not necessarily
be terminated. We need to carefully manage the goroutines we created, cause somtimes they will keep running at the back.

# Reference
1. [The Linux Process Model](https://www.linuxjournal.com/article/3814)
2. [The Go Memory Model](https://go.dev/ref/mem)
