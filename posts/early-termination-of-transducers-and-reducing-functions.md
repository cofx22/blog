Title: Early termination of transducers and reducing functions
Date: 2024-11-23
Tags: Clojure
Image: assets/social/cofx-clojure.png
Image-Alt: An image indicating that this post is about Clojure
Issue: 10

In the [previous post about transducers](https://blog.cofx.nl/to-transduce-or-not-to-transduce.html),
I did not discuss early termination of reducing functions and transducers.
For the examples given in that post, early termination was irrelevant.
It is, however, an important and tricky aspect of reducing functions and transducers.

<!-- end-of-preview -->

## Early termination of reducing functions

The following reducing function is a variant on the function `first` and the transducer `(take 1)`,
created specially for people with [nostalgia for the 80s](https://en.wikipedia.org/wiki/Highlander_\(film\)).

```clojure
(defn highlander-rf
  "There can be only one"
  [_ input] (reduced input))
```

Although this function is largely useless in practice,
it provides the most minimalist example of early termination.
It takes an intermediate result and an input value, and returns this input value wrapped with a special object.
Functions that use this reducing function will recognize this special object and know that they shouldn't provide any more input to this function.

The function `reduce` is one of those functions that recognize the wrapper object:

```clojure
(reduce highlander-rf nil [1 2 3 4]) ;; Evaluates to 1
```

The function `reduce` will call `highlander-rf` with `nil` and 1 as arguments, and then won't call it any more.

This mechanism makes it possible to efficiently reduce large or even infinite collections.
Once all relevant input has been processed, all irrelevant input that follows can be ignored.

## Using ensure-reduced inside transducers

The following transducer has the same behavior as the reducing function above:

```clojure
(defn highlander-tr
  "There can be only one"
  [rf]
  (fn
    ([] (rf))
    ([result] (rf result))
    ([result input] (ensure-reduced (rf result input)))))
```

The two-arity variant of this transducer takes a value as input and returns this value wrapped in the same special object again.
It uses `ensure-reduced` to do this, instead of `reduced`.
When implementing `highlander-tr`, it's not known what reducing function `rf` it will be used with.
It could be that some of these functions will return a result that is already wrapped.
The function `ensure-reduced` will ensure that an already wrapped result is not wrapped again.
If the return value of `(rf result input)` is already wrapped using `reduced`, the result will be returned as-is.
If it is not wrapped, `ensure-reduced` will wrap it.

The following example demonstrates the behavior of `highlander-tr`:
```clojure
(into []
      highlander-tr
      [1 2 3 4]) ;; Evaluates to [1]
```

## Using reduced? inside transducers

The following reducer does a little more than the one we just saw:

```clojure
(defn broken-stutter [rf]
  (fn
    ([] (rf))
    ([result] (rf result))
    ([result input]
     (rf (rf result input) input))))
```

This transducer will output each value it receives as input twice.
As its name suggests, it is broken.
Unfortunately, that is not that easy to notice.

Evaluating the following example leads to the result you'd expect:

```clojure
(transduce
 broken-stutter
 conj
 []
 [1 2 3 4 5 6]) ;; Evaluates to [1 1 2 2 3 3 4 4 5 5 6 6]
```

When used together with the following reducing function that terminates early,
however,
the transducer will not always behave as expected:

```clojure
(defn limited-conj [n]
  (fn 
    ([result] result)
    ([result input]
     (if (>= (count result) n)
       (reduced result)
       (conj result input)))))
```

The reducing function above behaves the same as `conj`,
until the collection passed as intermediate result contains at least `n` values.
Once that threshold has been reached, the intermediate result is returned as final result.

Combining the reducing function `limited-conj` with the transducer `broken-stutter` can bring the issue with `broken-stutter` to the surface.
The following expression cannot be evaluated, for example:

```clojure
(transduce
 broken-stutter
 (limited-conj 6)
 []
 [1 2 3 4 5 6])
```

 The following expression *can* be evaluated, however, which highlights why dealing with early termination can be tricky:

 ```clojure
(transduce
 broken-stutter
 (limited-conj 5)
 []
 [1 2 3 4 5 6]) ;; Evaluates to [1 1 2 2 3]
```

The problem with `broken-stutter` is that it may apply the reducing function `rf` to a result that is already wrapped using `reduced`.
The following variant fixes that issue:

```clojure
(defn stutter [rf]
  (fn
    ([] (rf))
    ([result] (rf result))
    ([result input]
     (let [intermediate (rf result input)]
       (if (reduced? intermediate)
         intermediate
         (rf intermediate input))))))
```

This variant checks whether the intermediate result is already reduced and does not apply `rf` if that is the case.

```clojure
(transduce
 stutter
 (limited-conj 6)
 []
 [1 2 3 4 5 6]) ;; Evaluates to [1 1 2 2 3 3]
```

## Using unreduced inside transducers

There's one more scenario regarding early termination that I'd like to describe.
Because this scenario is also tricky, we need another reducing function that terminates early to demonstrate it.
The following function is taken from [ClojureDocs](https://clojuredocs.org/clojure.core/unreduced#example-64458dd4e4b08cf8563f4b96):

```clojure
(defn conj-till-odd
  ([coll] coll)
  ([coll x] (cond-> (conj coll x)
              (odd? x) reduced)))
```

It behaves as `conj` until an odd value is received as input.

The following stateful transducer outputs each input value it receives and stores the last one.
Once all input has been processed, the last input value is added to the output again.

```clojure
(defn repeat-last [rf]
  (let [pv (volatile! nil)]
    (fn
      ([] (rf))
      ([result]
       (if-let [p @pv]
         (unreduced (rf result p))
         (rf result)))
      ([result input]
       (let [result (rf result input)]
         (vreset! pv input)
         result)))))
```

This transducer uses `unreduced` to ensure that the final result returned by the single-arity variant of this function is not wrapped with `reduced`.
It could be that the result of `(rf result p)` is wrapped with `reduced`.
If that is the case, this wrapper should be removed because it has no place in the output of the transducer.

If a reducing function or the two-arity variant of a transducer returns a value wrapped with `reduced`,
this wrapper is only intended to signal that the reducing function or transducer will not process any more input values.
Whoever is using the reducing function or transducer should stop feeding it more input values and remove the wrapper from the final result.
The transducer `stutter` demonstrates the first action, and the transducer `repeat-last` demonstrates the second action.

The following example illustrates the use of `repeat-last` in combination with `conj-till-odd`:

```clojure
(transduce
 repeat-last
 conj-till-odd
 []
 [2 4 3 2]) ;; Evaluates to [2 4 3 3]
```

## Conclusion

See [https://github.com/ljpengelen/transduce-shakespeare/tree/main/transduce-clj](https://github.com/ljpengelen/transduce-shakespeare/tree/main/transduce-clj)
for a Clojure project containing some expressions that illustrate the concepts described in this post.
