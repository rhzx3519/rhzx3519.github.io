---
layout: post
title:  "Access Mysql in a Serializable Way"
date:   2024-03-11 21:30:00 +1100
categories: go
tags: mysql goroutine serializable
---

Goroutine is a magic which allows us to run our logic in a single routine. When it comes to the
database, the single routine allow us make access serializable. There is no more lock on the database, which
would significantly ramp up the performance, although it may require us write some extra codes.

# Examples
The whole logic is that we run the mysql client in a sub goroutine and use channel to pass in and out parameters.
Here is an example we need to plus 1 in a field in mysql. Table _counter_ only has three fields: (_id, name, count_).
For a plus 1 operation, we need to read the count from mysql, then update its new value into mysql. This code is simple,
```go
func (c *MysqlClient) doSomeSql(name string) (int, error) {
    row := c.db.QueryRow("SELECT count FROM counters WHERE name = ?", name)
    var count int
    if err := row.Scan(&count); err != nil {
        return 0, err
    }
    if _, err := c.db.Exec("UPDATE counters SET count = ? WHERE name = ?",
        count+1, name); err != nil {
        return 0, err
    }
    return count + 1, nil
}
```

Then we focus on the Mysql client, it needs a handler of connection to the database and a parameter channel 
as an entry to accept the request.

```go
type Add1Param struct {
  Name  string
  Count chan int
}

type MysqlClient struct {
  db                 *sql.DB
  add1Stream         chan Add1Param
}
```

Then, we kick off the mysql goroutine,

```go

func (c *MysqlClient) Run(ctx context.Context) (err error) {
    cfg := mysql.Config{
        User:                 getenv("DBUSER", ""),
        Passwd:               getenv("DBPASS", ""),
        Net:                  "tcp",
        Addr:                 fmt.Sprintf("%s:%s", getenv("DBHOST", "127.0.0.1"), getenv("DBPORT", "3306")),
        DBName:               "demo-brokers",
        AllowNativePasswords: true,
        ParseTime:            true,
    }

    c.db, err = sql.Open("mysql", cfg.FormatDSN())
    if err != nil {
        return err
    }
    pingErr := c.db.Ping()
    if pingErr != nil {
        return pingErr
    }
    fmt.Println("Mysql Connected...")

    go func() {
        defer c.exit()
        for {
            select {
            case param := <-c.add1Stream:
                count, err := c.doSomeSql(param.Name)
                if err != nil {
                    log.Fatalln(err)
                }
                param.Count <- count
            case <-ctx.Done():
                return
            }
        }
    }()

    return
}
```

It also needs some tricks to call mysql from another goroutine.
```go
func (c *MysqlClient) Add1(name string) int {
  param := Add1Param{
    Name:  name,
    Count: make(chan int),
  }
  defer close(param.Count)

  c.add1Stream <- param
  return <-param.Count
}
```

Finally, we need to validate whether it will remain data integrity under a concurrent environment.

```go
func TestMysqlClient_Run(t *testing.T) {
    client := NewMysqlClient()
    ctx, cancel := context.WithTimeout(context.TODO(), time.Minute)
    defer cancel()
    client.Run(ctx)
    const COUNTER_NAME = "reading"
    client.DeleteByName(COUNTER_NAME)
    client.AddCounter(COUNTER_NAME)

    var wg sync.WaitGroup
    const N = 10000
    for i := 0; i < N; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            client.Add1(COUNTER_NAME)
        }()
    }

    wg.Wait()

    count := client.QueryByName(COUNTER_NAME).Count
    assert.Equal(t, count, N)
}
```

# Reference
[GitHub](https://github.com/rhzx3519/go-concurrency/tree/master/examples/mysqlpattern)
