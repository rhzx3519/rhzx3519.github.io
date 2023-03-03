---
layout: post
title:  "Cue Overviews for Beginners"
date:   2023-03-02 14:16:27 +1100
categories: DevOps
tags: Configure Template
---

![Image](/assets/images/cue/The Logic of CUE _ CUE.jpeg)

# Overviews
Every resource in kubernetes can be declared through texts, and these texts are always duplicated.
therefore, many template techniques are developed to generate texts, e.g. Helm, Customize and so on.
Cue is a language specialized for generate texts, what is different in Cue is that it avoids layered designed, 
which is often the most difficult part when it comes to manage large configuration in kubernetes. 
Developers or Operators are always confused in which layer they should change the template values.
With many traits different to current template techniques, I think we should take a look at Cue.

## Foundations
Cue is a superset of JSON.

superset.cue
```cue
str: "hello world"
num: 42
flt: 3.14

// Special field name (and a comment)
"k8s.io/annotation": "secure-me"

// lists can have different element types
list: [
	"a", "b", "c",
	1,
	2,
	3,
]

obj: {
	foo: "bar"
	// reuse another field?!
	L: list
}
```

cue export superset.cue --out json
```cue
{
    "str": "hello world",
    "num": 42,
    "flt": 3.14,
    "k8s.io/annotation": "secure-me",
    "list": [
        "a",
        "b",
        "c",
        1,
        2,
        3
    ],
    "obj": {
        "foo": "bar",
        "L": [
            "a",
            "b",
            "c",
            1,
            2,
            3
        ]
    }
}
```

### The Lattice
Every instance lives somewhere is cue's lattice.
top(_) -> schema -> constraint -> data -> bottom(_|_)

### Types and Values
Cue merges types and values into one concept, the lattice.

schema.cue
```cue
album: {
  title: string
  year: int
  live: bool
}
```
constraints.cue
```cue
import "strings"

album: {
  title: strings.MinRunes(5)
  year: >1952
  live: false
}
```
data.cue
```cue
album: {
  title: "Houses of the Holy"
  year: 1973
  live: false
}
```

```shell
cue eval schema.cue constraints.cue data.cue
```

### Order Is Irrelevant
order.cue
```cue
// you can add constraints after
a: 3
a: int
a: >1

// define a struct in one place
s: {
	x: int
	y: int
}

// define a struct in parts
s: y: int
s: x: int

// the above is shorthand
// when setting a nested value
```

### Values Cannot Be Changed
### Defining Fields
Cue allows fields to be defined more than once, as long as they are consistent with each other.
- basic data types must be the same
- you can make a field more restrict, but not the other way.
- struct fields are merged, list elements must match exactly.
- the rules are applied recursively.

fields.cue
```cue
hello: "world"
hello: "world"

// set a type
s: {a: int}

// set some data
s: {a: 1, b: 2}

// set a nested field without curly braces
s: c: d: 3

// lists must have the same elements
// and cannot change length
l: ["abc", "123"]
l: [
	"abc",
	"123",
]
```

### Definitions (Schema)
Definitions are struct with a '#' prefix, and you can leave it open with '...' at last inside.

definition.cue
```cue
#Album: {
	artist: string
	title:  string
	year:   int

	// ...  // 2. uncomment to open and fix error, must be last
}

// This is a conjunction, it says "album" has to be "#Album"
album: #Album & {
	artist: "Led Zeppelin"
	title:  "Led Zeppelin I"
	year:   1969

	// studio: true  // 1. uncomment to trigger error
}
```

### Conjunction
Conjunctions 'meet' values together, combining their fields, rules and data together.
They are like 'and' and the operator is '&'

conjunction.cue
```cue
// conjunctions on a field
n: int & >0 & <100
n: 23
// conjunctions on a schema
val: #Def1 & #Def2
val: {
  foo: "bar"
  ans: 42
}

#Def1: {
  foo: string
  ans: int
}

#Def2: {
  foo: =~'[a-z]+'
  ans: >0
}
```

### Disjunctions
Disjunctions 'join' values to create options or alternatives, they are like 'or' and the operator is '|'

disjunction.cue
```cue
// disjunction of values (like an enum)
hello: "world" | "bob" | "mary"
hello: "world"

// disjunction of types
port: string | int
port: 5432

// disjunction of schemas
val: #Def1 | #Def2
val: {foo: "bar", ans: 42}

#Def1: {
	foo: string
	ans: int
}

#Def2: {
	name: string
	port: int
}
```

Disjunctions have several uses:
- enums(as values), "foo" | "bar" | "zkk"
- sum-type(any of these types), string | int
- null-coalescing, elments[3] | "d"

## Defaults and Options
Defaults's operator is '*' as a prefix in the value.
Options's operator is '?' as a suffix in the key.
```cue
s: {
	// field with a default
	hello: string | *"world" | "apple"
	// an optional integer
	count?: int
}
```

## Incomplete and Concrete
incomplete.cue
```cue
// incomplete values
a: _
b: int

s: {
  a: _
}

// concrete values
a: "a"
b: int

s: a: { foo: "bar" }
```

### Open and Closed
Open means a struct can be extended, and closed means they cannot.
By default, structs are open and definition are closed.

open-closed.cue
```cue
	// Closed struct
s: close({
	foo: "bar"
})

// Open definition
#d: {
	foo: "bar"
	... // must be last
}
```

## Building up Values
You can define small schemas first, then embed them into a bigger schema, this makes
schemas reusable.

building-up.cue
```cue
 
#Base: {
	name: string
	kind: string
}

#Meta: {
	// string and a semver regex
	version: string & =~"^v[0-9]+\\.[0-9]+\\.[0-9]+$"
	// list of strings
	labels: [...string]
}

#Permissions: {
	role:   string
	public: bool | *false
}

// Building up a schema using embeddings
#Schema: {
	// embed other schemas
	#Base
	#Meta

	#Permissions
	// with no '...' this is final
}

value: #Schema & {
	name:    "app"
	kind:    "deploy"
	version: "v1.0.42"
	labels: ["server", "prod"]
	role: "backend"
	// public: false  (by default)
}
```

## Types and Values
### Builtin Types
null  bool  string  bytes  number  list  struct
                             |
                            int

'_' means top.
'_|_' means bottom and represents an error.


## Expressions
### Interpolation
Cue supports interpolation in strings and bytes with \(<expr>)
interpolate.cue
```cue
 
container: {
	repo:    "docker.io/cuelang"
	image:   "cue"
	version: "v0.3.0"
	full:    "\(repo)/\(image):\(version)"
}

name: "Tony"
msg:  "Hello \(name)"
// conver string to bytes
b: '\(msg)'
// convert bytes to string
s: "\(b)"
```

### List Comprehensions
list-comp.cue
```cue
nums: [1, 2, 3, 4, 5, 6]
sqrd: [ for _, n in nums {n * n}]
even: [ for _, n in nums if mod(n, 2) == 0 {n}]

listOfStructs: [ for p, n in nums {
	pos: p
	val: n
}]

extractVals: [ for p, S in listOfStructs {S.val}]
```

### Field Comprehensions
field-comp.cue
```cue
 
apps: ["nginx", "express", "postgres"]
#labels: [string]: string
stack: {
	for i, app in apps {
		"\(app)": {
			name:   app
			labels: #labels & {
				app:  "foo"
				tier: "\(i)"
			}
		}
	}
}
```

### Conditional Fields
guards.cue
```cue
 
app: {
	name: string
	tech: string
	mem:  int

	if tech == "react" {
		tier: "frontend"
	}
	if tech != "react" {
		tier: "backend"
	}

	if mem < 1Gi {
		footprint: "small"
	}
	if mem >= 1Gi && mem < 4Gi {
		footprint: "medium"
	}
	if mem >= 4Gi {
		footprint: "large"
	}
}

// This will result in an error because CUE evaluates all conditions
// without short-circuiting, meaning it will still try to access app.field
// if app.field != _|_ && app.field == true {
//   foo: true
// }

// Use nested guards to check multiple conditions
if app.field != _|_ {
	if app.field == true {
		foo: true
	}
}
```

## Scopes and Visibility

### Reference Lookup
```cue
 
val: 42
A: {
	val: 23
	num: val // will be 23, matches locally

	// irregular names need to be quoted and require indexing to access
	"user-id": "abc"
	UserID:    A["user-id"]
}
A: {
	b: val   // 42, matches top-level
	c: A.num // 23, reference A.num

	// num itself is not in scope even though it is part of A
}
```

### Paths
```cue
 
A: {
	a:    "A"
	"2f": 3
	l: ["cow", "moo"]
}

a: {
	// either is valid
	f1: A.a
	f2: A["a"]
	// must index
	f3: A["2f"]
	// list index
	f4: A.l[1]
}
```

### Hidden Fields and Values

hidden.cue
```cue
A: {
	_hidden: "a hidden field"
	isshown: "I can be seen"
	hidrefd: _hidden + " sort of?"
}

_#NoshowDefn: {
	hello: string
	num:   int | *42
}

B: _#NoshowDefn & {hello: "world"}
```

### Reference Cycles
Cue can resolve many cycles, as long as they can resovle to a final, concrete value.

ref-cycle.cue
```cue
// a mathematically valid releationship
// but invalid in Cue until one or the other has a value
a: b - 10
b: a + 10

// we need to set a or b and Cue will do the rest
// if not, a cycle error will be reported
a: 100
```

### Structural Cycles

structural.cue

```cue
 
#List: {
	val:  _
	next: #List | *null
}

// Cannot do this, it is structural recursion
#Contains: {
	list:  #List
	val:   _
	found: bool | *false

	if list.val == val {
		found: true
	}
	if list.val != val && list.next != null {
		// No recursion!
		found: #Contains & {"list": list.next, "val": val}
	}
}

// We can define an infinite structure
list: #List & {val: "a", next: {val: "b"}}

// results in
list: {
	val: "a"
	next: {
		val:  "b"
		next: null
	}
}
```













