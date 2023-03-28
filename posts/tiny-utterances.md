Title: Tiny Utterances: a minimalistic comment system
Date: 2023-03-28
Tags: Blogging
Issue: 6

Are you looking for a free, serverless™ comment system for a technical blog?
Maybe [Tiny Utterances](https://cofx22.github.io/tiny-utterances/) is the tool you need.
All you need to get started is a GitHub issue and a few lines of CSS and JavaScript.

<!-- end-of-preview -->

## Conception

Tiny Utterances started out as Tiny Giscus, a clone of [Giscus](https://giscus.app/).
Giscus is a comment system based on [GitHub Discussions](https://docs.github.com/en/discussions).
Utterances, on the other hand, is based on [GitHub Issues](https://docs.github.com/en/issues/tracking-your-work-with-issues).

I started working on a minimalistic clone of Giscus that was based on GitHub Discussions too,
simply because comments feel more closely related to discussions than issues.
However, there's only a GraphQL API to interact with Github Discussions and this API requires a personal access token for all operations.
As a result, you can't really use this API client side.
Although it's technically possible, it requires you to expose one of your personal access tokens.
That's also technically possible, because you could create a personal access token that can only be used to read public repositories and discussion, but GitHub immediately revokes any personal access token it finds in a repository.

Long story short, I had to switch to GitHub Issues as a basis for my minimalistic comment system.
Although it's not a perfect fit conceptually, it works pretty well.

For additional details, such as installation instructions, visit the [documentation](https://cofx22.github.io/tiny-utterances/).
An example comment section is included at the bottom of this page and other pages of this blog.
Feel free to leave a comment, that's why it's there.
