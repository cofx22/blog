Title: shadow-cljs and running tests
Date: 2023-01-27
Tags: Clojure, ClojureScript

When I used to work on front ends based on JavaScript or TypeScript, I usually had [Karma](https://karma-runner.github.io/latest/index.html) running in watch mode while developing.
Each time I saved a file, all (unit) tests would run.
This would give me a short feedback loop, letting me know quickly when I was unintentionally breaking things and constantly indicating whether what I was creating matched its specifications as defined by the tests.
In other words, tests were used to prevent regressions, but also as a tool to quickly see whether I was building the right things.

In the last few years, I've been using Clojure and ClojureScript to create prototypes and utilities at work as well as hobby projects and apps for personal use.
Because of the size and nature of these applications, I wasn't too worried about regressions.
Because Clojure and ClojureScript have excellent support for REPL-driven development, the need for tests as a means for quick feedback also disappeared.
As a result, I wrote a few tests for these applications, but not nearly as many as I used to.

Deep down inside, however, I knew I would have to invest some time into learning about testing Clojure and ClojureScript applications at some point.
I wouldn't want to work in a team that produced software without decent test coverage.
I should hold myself to that same standard.
This week, I decided to sit down and take some time to look into running tests for ClojureScript apps powered by [shadow-cljs](https://github.com/thheller/shadow-cljs).
As you may know, shadow-cljs is one of the two de facto standard tools for creating ClojureScript apps.
The other, equally well-known tool is [Figwheel](https://figwheel.org/).

<!-- end-of-preview -->

There are a number of different ways to execute tests for a shadow-cljs based ClojureScript application.
In my experience, documentation and advice about this topic is scattered around the internet and Slack channels.
For this reason, I decided to document three ways of running tests in this blog post.
There are more alternatives, but I'll probably stick with a combination of the following for now.

## Running tests on the command line

## Running tests in the browser

## Running tests from the REPL
