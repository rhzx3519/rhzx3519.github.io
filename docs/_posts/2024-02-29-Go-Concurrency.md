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

# Fan In & Fan Out
To reuse a single stage of our pipeline on multiple
goroutines in an attempt to parallelize pulls from an upstream stage?
**Fan-out** is a term to describe the process of starting multiple goroutines to
handle input from the pipeline, and **fan-in** is a term to describe the process of
combining multiple results into one channel.

```go
fanIn := func(done <-chan interface{}, channels ...<-chan interface{}) <- chan interface{} {
    var wg sync.WaitGroup
    multiplexedStream := make(chan interface{})
    multiplex := func(c <-chan interface{}) {
        defer wg.Done()
        for i := range c {
            select {
                case <-done:
                    return
                case multiplexedStream <- i:
            }
        }
    }
    // Select from all the channels
    wg.Add(len(channels))
    for _, c := range channels {
        go multiplex(c)
    }
    // Wait for all the reads to complete
    go func() {
        wg.Wait()
        close(multiplexedStream)
    }()
    return multiplexedStream
}

toInt := func(done <-chan interface{}, valueStream <-chan interface{}) <-chan string {
  stringStream := make(chan string)
  go func() {
    defer close(stringStream)
    for v := range valueStream {
      select {
          case <-done:
              return
          case stringStream <- v.(int):
      }
    }
  }()
  return stringStream
}

primeFinder := func(done <-chan interface{}, intStream <-chan int) <-chan int {
    count := func(n int) int {
      var tot int
      f := make([]bool, n+1)
      for i := 2; i <= n; i++ {
        if !f[i] {
            tot++
        }
        for j := i*i; j <= n; j += i {
            f[j] = true
        }   
      }
    }
    intStream := make(chan int)
    go func() {
        defer close(intStream)
        for v := range intStream {
            select {
                case <-done:
                    return
                case n <- v:
                    intStream <- count(n)
            }       
        }   
    }   
    return intStream
}

done := make(chan interface{})
defer close(done)
start := time.Now()
rand := func() interface{} { return rand.Intn(50000000) }
randIntStream := toInt(done, repeatFn(done, rand))
numFinders := runtime.NumCPU()
fmt.Printf("Spinning up %d prime finders.\n", numFinders)
finders := make([]<-chan interface{}, numFinders)
fmt.Println("Primes:")
for i := 0; i < numFinders; i++ {
    finders[i] = primeFinder(done, randIntStream)
}
for prime := range take(done, fanIn(done, finders...), 10) {
    fmt.Printf("\t%d\n", prime)
}
fmt.Printf("Search took: %v", time.Since(start))
```

# The or-done-channel
```go
orDone := func(done, c <-chan interface{}) <-chan interface{} {
  valStream := make(chan interface{})
  go func() {
    defer close(valStream)
    for {
      select {
        case <-done:
            return
        case v, ok := <-c:
        if ok == false {
            return
        }
        select {
            case valStream <- v:
            case <-done:
        }
      }
    }
  }()
  return valStream
}

//Doing this allows us to get back to simple for-loops, like so:
for val := range orDone(done, myChan) {
    // Do something with val
}
```

# The tee-channel
Taking its name from the **tee** command in Unix-like systems, the tee-channel
does just this. You can pass it a channel to read from, and it will return two
separate channels which will get the same value.
```go
tee := func(done <-chan interface{}, in <-chan interface{}) (chan any, chan any) {
  out1 := make(chan interface{})
  out2 := make(chan interface{})
  go func() {
    defer close(out1)
    defer close(out2)
    for val := range orDone(done, in) {
      //We’re going to use one select statement so that writes to out1 and out2
      //don’t block each other. To ensure both are written to, we’ll perform two
      //iterations of the select statement: one for each outbound channel.
      var out1, out2 = out1, out2
      for i := 0; i < 2; i++ {
        select {
          case <-done:
          case out1<-val:
              // Once we’ve written to a channel, we set its shadowed copy to nil so 
              // that further writes will block and the other channel may continue.
            out1 = nil
          case out2<-val:
            out2 = nil
        }
      }
    }
  }()
  return out1, out2
}

done := make(chan interface{})
defer close(done)
out1, out2 := tee(done, take(done, repeat(done, 1, 2), 4))
for val1 := range out1 {
    fmt.Printf("out1: %v, out2: %v\n", val1, <-out2)
}
```

# The bridge-channel
In some circumstances, you may find yourself wanting to consume values
from a sequence of channels:
```go
func bridge(done <-chan interface{}, chanStream <-chan <-chan interface{}) <-chan interface{} {
	valStream := make(chan interface{})
	go func() {
		defer close(valStream)
		for {
			var stream <-chan interface{}
			select {
			case maybeStream, ok := <-chanStream:
				if ok == false {
					return
				}
				stream = maybeStream
			case <-done:
				return
			}
			for val := range orDone(done, stream) {
				select {
				case valStream <- val:
				case <-done:
				}
			}
		}
	}()
	return valStream
}
```

# The Context Package

```go
var Canceled = errors.New("context canceled")
var DeadlineExceeded error = deadlineExceededError{}
type CancelFunc
type Context
func Background() Context
func TODO() Context
func WithCancel(parent Context) (ctx Context, cancel CancelFunc)
func WithDeadline(parent Context, deadline time.Time) (Context, CancelFunc
func WithTimeout(parent Context, timeout time.Duration) (Context,
func WithValue(parent Context, key, val interface{}) Context

type Context interface {
  // Deadline returns the time when work done on behalf of this
  // context should be canceled. Deadline returns ok==false when no
  // deadline is set. Successive calls to Deadline return the same
  // results.
  Deadline() (deadline time.Time, ok bool)
  // Done returns a channel that's closed when work done on behalf
  // of this context should be canceled. Done may return nil if this
  // context can never be canceled. Successive calls to Done return
  // the same value.
  Done() <-chan struct{}
  // Err returns a non-nil error value after Done is closed. Err
  // returns Canceled if the context was canceled or
  // DeadlineExceeded if the context's deadline passed. No other
  // values for Err are defined. After Done is closed, successive
  // calls to Err return the same value.
  Err() error
  // Value returns the value associated with this context for key,
  // or nil if no value is associated with key. Successive calls to
  // Value with the same key returns the same result.
  Value(key interface{}) interface{}
}
```

## Instead of Done
* _WithCancel_ returns a new Context which closes its done channel when the returned cancel function is called.
* _WithDeadline_ returns a new Context which closes its done channel when the machine’s clock advances past the given deadline.
* _WithTimeout_ returns a new Context which closes its done channel after the given timeout duration.

```go
func printGreeting(ctx context.Context) error {
	greeting, err := genGreeting(ctx)
	if err != nil {
		return err
	}
	fmt.Printf("%s world!\n", greeting)
	return nil
}

func printFarewell(ctx context.Context) error {
	farewell, err := genFarewell(ctx)
	if err != nil {
		return err
	}
	fmt.Printf("%s world!\n", farewell)
	return nil
}

func genGreeting(ctx context.Context) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 1*time.Second)
	defer cancel()
	switch locale, err := locale(ctx); {
	case err != nil:
		return "", err
	case locale == "EN/US":
		return "hello", nil
	}
	return "", fmt.Errorf("unsupported locale")
}

func genFarewell(ctx context.Context) (string, error) {
	switch locale, err := locale(ctx); {
	case err != nil:
		return "", err
	case locale == "EN/US":
		return "goodbye", nil
	}
	return "", fmt.Errorf("unsupported locale")
}

func locale(ctx context.Context) (string, error) {
	// Here we check to see whether our Context has provided a deadline. If it
	// did, and our system’s clock has advanced past the deadline, we simply
	// return with a special error defined in the context package,
	// DeadlineExceeded.
	if deadline, ok := ctx.Deadline(); ok {
		if deadline.Sub(time.Now().Add(1*time.Minute)) <= 0 {
			return "", context.DeadlineExceeded
		}
	}

	select {
	case <-ctx.Done():
		return "", ctx.Err()
	case <-time.After(5 * time.Second):
	}
	return "EN/US", nil
}

// Greeting&Farewell Context pattern
// Let’s say that genGreeting only wants to wait one second before abandoning
// the call to locale — a timeout of one second. We also want to build some
// smart logic into main. If printGreeting is unsuccessful, we also want to
// cancel our call to printFarewell. After all, it wouldn’t make sense to say
// goodbye if we don’t say hello!
func ExampleContextPattern() {
  var wg sync.WaitGroup
  ctx, cancel := context.WithCancel(context.Background())
  defer cancel()
  wg.Add(1)
  go func() {
    defer wg.Done()
    if err := printGreeting(ctx); err != nil {
      fmt.Printf("cannot print greeting: %v\n", err)
      cancel()
    }
  }()
  wg.Add(1)
  go func() {
    defer wg.Done()
    if err := printFarewell(ctx); err != nil {
      fmt.Printf("cannot print farewell: %v\n", err)
    }
  }()
  wg.Wait()
  // Output:
  // cannot print greeting: context deadline exceeded
  // cannot print farewell: context canceled
}
```

## Store Value in Context

**Context Value**
- The key you use must satisfy Go’s notion of comparability, that is the
  equality operators == and != need to return correct results when used.
- Values returned must be safe to access from multiple goroutines.

**Convention**
- First, they recommend you define a custom key-type in your package. As
  long as other packages do the same, this prevents collisions within the
  Context.
- Since the type you define for your package’s keys is unexported, other
  packages cannot conflict with keys you generate within your package.
  Since we don’t export the keys we use to store the data, we must therefore
  export functions that retrieve the data for us.

```go
type ctxKey int

const (
	ctxUserID ctxKey = iota
	ctxAuthToken
)

func UserID(c context.Context) string {
	return c.Value(ctxUserID).(string)
}
func AuthToken(c context.Context) string {
	return c.Value(ctxAuthToken).(string)
}

func ProcessRequest(userID, authToken string) {
	ctx := context.WithValue(context.Background(), ctxUserID, userID)
	ctx = context.WithValue(ctx, ctxAuthToken, authToken)
	HandleResponse(ctx)
}

func HandleResponse(ctx context.Context) {
	fmt.Printf("handling response for %v (auth: %v)", UserID(ctx), AuthToken(ctx))
}

func ExampleContextValue() {
  ProcessRequest("jane", "abc123")
  // Output:
  // handling response for jane (auth: abc123)
}

```


# Reference
1. [Concurrency in Go](https://www.oreilly.com/library/view/concurrency-in-go/9781491941294/)
