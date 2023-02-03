Title: Dependency injection and loggers in Clojure
Date: 2023-02-03
Tags: Clojure
Image: assets/social/cofx-clojure.png
Image-Alt: An image indicating that this post is about Clojure

Logging functions have to be impure to be useful.
If they don't change the state of the world around them by writing something somewhere, why would you use them?
This makes any function that uses a logging function directly impure too.
If that is something you want to avoid, you could inject a logging service and use that instead of the logging function.
Let's do that and see where we end up.

<!-- end-of-preview -->

The protocol `Logger` below consists of a single method `info`.
The constructor function `create-logger` returns a concrete implementation of `Logger`, which delegates to `log/info`.
This may seem convoluted, but remember that we're doing this to keep as many functions as possible pure, also those that need to log.

```clojure
(ns logging
  (:require [clojure.tools.logging :as log]))

(defprotocol Logger
  (info [this message]))

(defn create-logger []
  (reify Logger
    (info [_ message] (log/info message))))
```

The function `add-and-log` below takes a logger as its first argument and uses it to log the result of some computation.
Pay close attention to the namespace.

```clojure
(ns domain
  (:require [logging :refer [create-logger info]]))

(defn add-and-log [logger & args]
  (info logger (apply + args)))

(add-and-log (create-logger) 1 2 3 4)
(add-and-log (create-logger) 1 2 3 4 5)
```

The result of evaluating the last two expressions is as follows:

```shell-session
13:47:30.130 [nREPL-session-fab93eaa-9ae3-40d4-a4f1-a0605747ba5c] INFO logging - 10
13:49:22.927 [nREPL-session-fab93eaa-9ae3-40d4-a4f1-a0605747ba5c] INFO logging - 15
```

These two log entries contain the log level ("INFO"), the namespace from which the logging function was called ("logging"), and the log messages ("10" and "15").

Usually, it's convenient to be able to trace an entry in the logs to its origin in the code.
In this example, however, we're logging messages in the namespace `domain`, but the log entries contain the namespace `logging`.
This unfortunate, but it makes perfect sense.
It may look like we're logging messages in the namespace `domain`, because that's where we call the `info` method of the logger,
but the actual logging happens in the namespace `logging`, where `log/info` is called.

## Macros to the rescue

After some head scratching and browsing through code bases and documentation, I learned that this is one of those occasions where macros come in handy.
As you may know, macros can be used to transform code at compile time.
The end result of this transformation is evaluated at runtime.

For example, the macro `twice` below takes a function and a value, and applies the function twice: once to the value and then to the result of the first application.

```clojure
(defmacro twice [f x]
  `(~f (~f ~x)))
```

Without going into details too much, you could view the expression <code>`(~f (~f ~x))</code> as a template, where <code>~</code> is used as an escape symbol.

At compile time, the expression `(twice inc 0)` expands to the following:

```clojure
(inc (inc 0))
```

At runtime, this evaluates to `2`.

For beginners, it can be difficult to determine whether a function or a macro should be used to solve a certain problem.
In fact, the macro `twice` could have been a function.
Most people would say that if something can be implemented as a function, then it should be implemented as function, not a macro.
The problem with our logger, however, is a perfect fit for macros.

Let's look at the new `Logger` protocol and the corresponding constructor function first.

```clojure
(ns logging
  (:require [clojure.tools.logging :as log]
            [clojure.tools.logging.impl :as impl]))

(defprotocol Logger
  (-log [this ns level message throwable]))

(defn create-logger []
  (reify Logger
    (-log [_ ns level message throwable]
      (let [logger (impl/get-logger log/*logger-factory* ns)]
        (log/log* logger level throwable message)))))
```

This version of the protocol consists of a single method named `-log`, where the minus-sign indicates that the method is not meant to be called directly.
(It can be called directly, but it's not meant to be.)
What's most noteworthy about this method is that it takes an argument `ns`.
The constructor function creates a logger by passing the value of `ns` to the logger factory of `clojure.tools.logging`.

How can we pass the namespace in which we're logging something to this method without doing so explicitly?
Part of the answer lies in `*ns*`, an object [representing the current namespace](https://clojuredocs.org/clojure.core/*ns*).
Using a function in the `logging` namespace to pass along `*ns*` wouldn't work however, because we would be passing along that namespace again.
The second part of the answer lies in using a macro.

```clojure
(defmacro log [logger level message throwable]
  `(-log ~logger ~*ns* ~level ~message ~throwable))
```

As mentioned above, macros will be expanded at compile time and the resulting expression will be evaluated at runtime.
Because the expansion happens where the macro is applied, the value of `*ns*` is the namespace in which the macro is applied, not the namespace in which the macro is defined.

To provide an API that is a little more pleasant to use, the macro above is combined with the following ones (and similar ones for other log levels).

```clojure
(defmacro info [logger message]
  `(log ~logger :info ~message nil))

(defmacro error [logger message throwable]
  `(log ~logger :error ~message throwable))
```

Let's put these new macros to use:

```clojure
(ns domain
  (:require [logging :refer [create-logger info]]))

(defn add-and-log [logger & args]
  (info logger (apply + args)))

(add-and-log (create-logger) 1 2 3 4)
(add-and-log (create-logger) 1 2 3 4 5)
```

The result of evaluating the last two expressions is now as follows:

```shell-session
13:58:17.378 [nREPL-session-fab93eaa-9ae3-40d4-a4f1-a0605747ba5c] INFO  domain - 10
13:58:18.589 [nREPL-session-fab93eaa-9ae3-40d4-a4f1-a0605747ba5c] INFO  domain - 15
```

Only one word changed, but this can make a world of difference when looking through logs to track down bugs.
