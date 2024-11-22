Title: Error handlers and failure handlers in Vert.x
Date: 2024-11-22
Tags: Java, Vert.x
Image: assets/social/cofx-java.png
Image-Alt: An image indicating that this post is about Java
Issue: 9

[Vert.x](https://vertx.io/) is a toolkit for developing reactive applications on the JVM.
I wrote a [short introductory post](reactive-java-with-vertx.html) about it earlier,
when I used it for a commercial project.
I had to revisit a Vert.x-based hobby project a few weeks ago,
and I learned that there were some gaps in my knowledge about how Vert.x handles failures and errors.
To fill those gaps, I did some experiments, wrote a few tests, and then wrote this blog post.

<!-- end-of-preview -->

The heart of most Vert.x-based web applications is a router.
The router routes requests to zero or more requests handlers, based on the path of the requests.
If all goes well, the handler that is handling a given request will issue a response.
When something does go wrong, Vert.x offers failure handlers and error handlers to handle the situation.

## How to signal that something went wrong in a request handler?

Errors in request handlers come in two flavors: either an exception is thrown (intentionally or unintentionally) or an error is signalled explicitly by calling the `fail` method on the routing context.
If you want to signal something went wrong by calling this method, you have three options:

- you can supply a status code,
- you can supply a status code and an exception, or
- you can supply an exception.

Throwing an exception has the same effect as calling the `fail` method with an exception as argument.
If no status code is provided when calling `fail`, status code 500 is used.
If an exception is provided when calling `fail`, this exception will be available to all failure and error handlers.

Without any error or failure handler, Vert.x will respond to a failed request with status code 500 and a body containing "Internal Server Error".
If that response doesn't suit your needs, you'll need to register an error handler and/or one or more failure handlers.

## Error handlers

You can register one error handler per status code with a router.
If some failure happens while handling a request and there are no failure handlers (more about those below),
then the error handler registered for the status code corresponding to the failure will handle the request:

```java
@Test
void errorHandlerCanHandleException(VertxTestContext vertxTestContext) {
    var handlerExecuted = vertxTestContext.checkpoint();
    var errorHandlerExecuted = vertxTestContext.checkpoint();

    router.route("/")
            .handler(rc -> {
                handlerExecuted.flag();
                throw new RuntimeException(REQUEST_HANDLER_ERROR_MESSAGE);
            });
    router.errorHandler(500, rc -> {
        errorHandlerExecuted.flag();
        rc.response()
                .setStatusCode(500)
                .end(MESSAGE_FROM_ERROR_HANDLER + ": " + rc.failure().getMessage());
    });

    var response = performGetRequest("/");

    assertThat(response.statusCode()).isEqualTo(500);
    assertThat(response.body()).startsWith(MESSAGE_FROM_ERROR_HANDLER);
    assertThat(response.body()).endsWith(REQUEST_HANDLER_ERROR_MESSAGE);
    vertxTestContext.succeedingThenComplete();
}
```

As discussed above, the error handler has access to the exception that led to the invocation of the error handler.
In this example, the error handler for status code 500 handles the error because this is the default status code when no other status code is provided.

Vert.x supports splitting up a single (large) router into multiple smaller ones using sub routers.
Although error handlers can be registered for each sub router, they will simply be ignored:

```java
@Test
void errorHandlerForSubRouterIsIgnored(Vertx vertx, VertxTestContext vertxTestContext) {
    var handlerExecuted = vertxTestContext.checkpoint();
    var rootErrorHandlerExecuted = vertxTestContext.checkpoint();

    var subRouter = Router.router(vertx);
    subRouter.errorHandler(500, rc ->
            vertxTestContext.failNow("Error handler for sub router should not be reached"));
    subRouter.route("/route")
            .handler(rc -> {
                handlerExecuted.flag();
                throw new RuntimeException(REQUEST_HANDLER_ERROR_MESSAGE);
            });

    router.route("/sub/*")
            .subRouter(subRouter);

    router.errorHandler(500, rc -> {
        rootErrorHandlerExecuted.flag();
        rc.response()
                .setStatusCode(500)
                .end(MESSAGE_FROM_ERROR_HANDLER + ": " + rc.failure().getMessage());
    });

    var response = performGetRequest("/sub/route");

    assertThat(response.statusCode()).isEqualTo(500);
    assertThat(response.body()).startsWith(MESSAGE_FROM_ERROR_HANDLER);
    assertThat(response.body()).endsWith(REQUEST_HANDLER_ERROR_MESSAGE);
    vertxTestContext.succeedingThenComplete();
}
```

## Failure handlers

In some cases, you may want more fine-grained control over how errors are handled.
This is where failure handlers come in.
One or more failure handlers can be registered per route.
They will handle errors in the order in which they are registered, until a handler successfully handles the error or an exception is thrown.

Like error handlers, failure handlers have access to the exception that led to their invocation.
They also have access to the status code:

```java
@Test
void failureHandlerCanHandleFailWithStatusCodeAndException(VertxTestContext vertxTestContext) {
    var handlerExecuted = vertxTestContext.checkpoint();
    var failureHandlerExecuted = vertxTestContext.checkpoint();

    router.route("/")
            .handler(rc -> {
                handlerExecuted.flag();
                rc.fail(418, new RuntimeException(REQUEST_HANDLER_ERROR_MESSAGE));
            })
            .failureHandler(rc -> {
                failureHandlerExecuted.flag();
                rc.response()
                        .setStatusCode(rc.statusCode())
                        .end(MESSAGE_FROM_FAILURE_HANDLER + ": " + rc.failure().getMessage());
            });

    var response = performGetRequest("/");

    assertThat(response.statusCode()).isEqualTo(418);
    assertThat(response.body()).startsWith(MESSAGE_FROM_FAILURE_HANDLER);
    assertThat(response.body()).endsWith(REQUEST_HANDLER_ERROR_MESSAGE);
    vertxTestContext.succeedingThenComplete();
}
```

Once an failure handler has handled a failure successfully,
no error handler will be invoked:

```java
@Test
void errorHandlerIsIgnoredWhenFailureHandlerHandledFailure(VertxTestContext vertxTestContext) {
    var handlerExecuted = vertxTestContext.checkpoint();
    var failureHandlerExecuted = vertxTestContext.checkpoint();

    router.route("/")
            .handler(rc -> {
                handlerExecuted.flag();
                throw new RuntimeException(REQUEST_HANDLER_ERROR_MESSAGE);
            })
            .failureHandler(rc -> {
                failureHandlerExecuted.flag();
                rc.response()
                        .setStatusCode(rc.statusCode())
                        .end(MESSAGE_FROM_FAILURE_HANDLER + ": " + rc.failure().getMessage());
            });
    router.errorHandler(500, rc -> vertxTestContext.failNow("Error should not reach error handler"));

    var response = performGetRequest("/");

    assertThat(response.statusCode()).isEqualTo(500);
    assertThat(response.body()).startsWith(MESSAGE_FROM_FAILURE_HANDLER);
    assertThat(response.body()).endsWith(REQUEST_HANDLER_ERROR_MESSAGE);
    vertxTestContext.succeedingThenComplete();
}
```

If a failure handler is unable to handle a certain failure,
it can let it be handled by the next failure handler:

```java
@Test
void failureHandlerCanDeferToNextFailureHandler(VertxTestContext vertxTestContext) {
    var handlerExecuted = vertxTestContext.checkpoint();
    var firstFailureHandlerExecuted = vertxTestContext.checkpoint();
    var secondFailureHandlerExecuted = vertxTestContext.checkpoint();

    router.route("/")
            .handler(rc -> {
                handlerExecuted.flag();
                throw new RuntimeException(REQUEST_HANDLER_ERROR_MESSAGE);
            })
            .failureHandler(rc -> {
                firstFailureHandlerExecuted.flag();
                rc.next();
            })
            .failureHandler(rc -> {
                secondFailureHandlerExecuted.flag();
                rc.response()
                        .setStatusCode(rc.statusCode())
                        .end(MESSAGE_FROM_FAILURE_HANDLER + ": " + rc.failure().getMessage());
            });

    var response = performGetRequest("/");

    assertThat(response.statusCode()).isEqualTo(500);
    assertThat(response.body()).startsWith(MESSAGE_FROM_FAILURE_HANDLER);
    assertThat(response.body()).endsWith(REQUEST_HANDLER_ERROR_MESSAGE);
    vertxTestContext.succeedingThenComplete();
}
```

If handling a failure leads to an exception,
the handling of the original failure is taken over by the error handler:

```java
@Test
void exceptionInFailureHandlerIsIgnoredByErrorHandler(VertxTestContext vertxTestContext) {
    var handlerExecuted = vertxTestContext.checkpoint();
    var failureHandlerExecuted = vertxTestContext.checkpoint();
    var errorHandlerExecuted = vertxTestContext.checkpoint();

    router.route("/")
            .handler(rc -> {
                handlerExecuted.flag();
                throw new RuntimeException(REQUEST_HANDLER_ERROR_MESSAGE);
            })
            .failureHandler(rc -> {
                failureHandlerExecuted.flag();
                throw new RuntimeException(FAILURE_HANDLER_ERROR_MESSAGE);
            });

    router.errorHandler(500, rc -> {
        errorHandlerExecuted.flag();
        rc.response()
                .setStatusCode(500)
                .end(MESSAGE_FROM_ERROR_HANDLER + ": " + rc.failure().getMessage());
    });

    var response = performGetRequest("/");

    assertThat(response.statusCode()).isEqualTo(500);
    assertThat(response.body()).startsWith(MESSAGE_FROM_ERROR_HANDLER);
    assertThat(response.body()).endsWith(REQUEST_HANDLER_ERROR_MESSAGE);
    vertxTestContext.succeedingThenComplete();
}
```

If there is no error handler registered for status code 500,
an exception thrown in a failure handler will lead to an internal server error.

We saw above that error handlers registered on sub router are ignored.
Failure handlers registered for routes on a sub router function as expected, however.
The failure handler registered for one of the routes of a sub router can either return a response itself or
fall back to the failure handler of another matching route:

```java
@Test
void failureHandlerForSubRouterCanFallBackToFailureHandlerForRoot(Vertx vertx, VertxTestContext vertxTestContext) {
    var handlerExecuted = vertxTestContext.checkpoint();
    var rootFailureHandlerExecuted = vertxTestContext.checkpoint();
    var subFailureHandlerExecuted = vertxTestContext.checkpoint();

    var subRouter = Router.router(vertx);
    subRouter.route("/route")
            .handler(rc -> {
                handlerExecuted.flag();
                throw new RuntimeException(REQUEST_HANDLER_ERROR_MESSAGE);
            })
            .failureHandler(rc -> {
                subFailureHandlerExecuted.flag();
                rc.next();
            });

    router.route("/sub/*")
            .subRouter(subRouter);

    router.route()
            .failureHandler(rc -> {
                rootFailureHandlerExecuted.flag();
                rc.response()
                        .setStatusCode(500)
                        .end(MESSAGE_FROM_FAILURE_HANDLER + ": " + rc.failure().getMessage());
            });

    var response = performGetRequest("/sub/route");

    assertThat(response.statusCode()).isEqualTo(500);
    assertThat(response.body()).startsWith(MESSAGE_FROM_FAILURE_HANDLER);
    assertThat(response.body()).endsWith(REQUEST_HANDLER_ERROR_MESSAGE);
    vertxTestContext.succeedingThenComplete();
}
```

## Conclusion

I hope this post provides a useful addition to Vert.x's official documentation.
If you want to experiment a little yourself, clone and browse
[https://github.com/ljpengelen/vertx-error-and-failure-handlers](https://github.com/ljpengelen/vertx-error-and-failure-handlers)
for some inspiration.
