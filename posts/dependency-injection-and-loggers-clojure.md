Title: Dependency injection and loggers in Clojure
Date: 2023-02-03
Tags: Clojure

Logging functions have to be impure to be useful.
If they don't change the state of the world around them by writing something somewhere, why would you use them?
This makes any function that uses a logging function directly impure too.
If that is something you want to avoid, you could inject a logging service and use that instead of the logging function.
Let's do that and see why it's not the ideal solution.

```clojure
(ns logging
  (:require [clojure.tools.logging :as log]))

(defprotocol Logger
  (info [this message]))

(defn create-logger []
  (reify Logger
    (info [_ message] (log/info message))))
```

```clojure
(ns domain
  (:require [logging :refer [create-logger info]]))

(defn add-and-log [logger & args]
  (info logger (apply + args)))

(add-and-log (create-logger) 1 2 3 4)
(add-and-log (create-logger) 1 2 3 4 5)
```

```shell-session
13:47:30.130 [nREPL-session-fab93eaa-9ae3-40d4-a4f1-a0605747ba5c] INFO logging - 10
13:49:22.927 [nREPL-session-fab93eaa-9ae3-40d4-a4f1-a0605747ba5c] INFO logging - 15
```

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

(defmacro log [logger level message throwable]
  `(-log ~logger ~*ns* ~level ~message ~throwable))

(defmacro info [logger message]
  `(log ~logger :info ~message nil))
```

```clojure
(ns domain
  (:require [logging :refer [create-logger info]]))

(defn add-and-log [logger & args]
  (info logger (apply + args)))

(add-and-log (create-logger) 1 2 3 4)
(add-and-log (create-logger) 1 2 3 4 5)
```

```shell-session
13:58:17.378 [nREPL-session-fab93eaa-9ae3-40d4-a4f1-a0605747ba5c] INFO  domain - 10
13:58:18.589 [nREPL-session-fab93eaa-9ae3-40d4-a4f1-a0605747ba5c] INFO  domain - 15
```
