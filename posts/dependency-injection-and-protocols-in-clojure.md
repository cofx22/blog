Title: Dependency injection and protocols in Clojure
Date: 2023-01-29
Tags: Clojure

Consider the following function, which
* takes a map of dependencies and a ring request,
* updates a gift using data from the request, and
* returns a ring response:

<!-- force end of list -->

```clojure
(defn update-gift [{:keys [datasource]} request]
  (let [{:keys [external-list-id external-gift-id]} (:path-params request)
        {:keys [name ok price description]} (:params request)]
    (when ok
      (domain/update-gift! datasource external-gift-id name price description))
    (response/redirect (str "/list/" external-list-id "/edit") :see-other)))
```

The function `domain/update-gift!` persists the changes to the database.
It has a side effect, which makes it an impure function.
Because `update-gift` uses `domain/update-gift!`, it's impure too.

You could argue that this fact alone is a reason to refactor this code.
Generally speaking, pure functions are easier to test and easier to reason about,
which are both good reasons to prefer pure functions over impure ones.

For simple apps, however, you could also argue that there's not much to reason about anyway, and refactoring may not be worth the effort.
What's more, replacing the impure function `domain/update-gift!` using [with-redefs](https://clojuredocs.org/clojure.core/with-redefs) would make testing quite straightforward.

Because this blog post is about dependency injection, we better find another reason to refactor `update-gift` and apply some more dependency injection.
Luckily, we can pretend that we want to replace the function `domain/update-gift!` with a function that uses a completely different method to persist gifts.
That's not something you would do with `with-redefs`.
