Title: Immutable objects in Python
Date: 2019-08-01
Tags: Python
Canonical-URL: https://www.kabisa.nl/tech/immutable-objects-in-python

*This post first appeared on [Kabisa's Tech Blog](https://www.kabisa.nl/tech/).*

To keep programs easy to reason about,
I try to avoid side effects and aim for a functional style of programming using immutable objects.
I’m happy to trade a few CPU cycles for a reduced demand of brain power.

Because we’re talking about Python here, and [we’re all responsible users](https://docs.python-guide.org/writing/style/#we-are-all-responsible-users), it’s impossible to create actual *objects* that are *impossible* to mutate.
You can, however, create things that behave like objects that are impossible to mutate or actual objects that cannot be mutated by mistake.

Let’s look at three ways to do this and how they differ.

## Named Tuples

The Python project I’m currently working on started before [data classes](https://docs.python.org/3/library/dataclasses.html) were available.
Additionally, this project is created for a client that prefers the use of as few dependencies as possible.
In that context, the following class for points emerged:

```
from collections import namedtuple


class Point(namedtuple("_Point", ["x", "y"])):
    def scale(self, scale):
        return Point(self.x * scale, self.y * scale)

    def translate(self, dx, dy):
        return Point(self.x + dx, self.y + dy)
```

It’s a class for points in two-dimensional space.
When you call the `scale` or `translate` method, a new point is returned.
This variant of the class extends a named tuple `_Point` consisting of two fields named `x` and `y`.

When you try to mutate an instance of this class, you’ll be greeted with an `AttributeError`:

```
>>> from collections import namedtuple
>>> Point = namedtuple("_Point", ["x", "y"])
>>> p = Point(1, 2)
>>> p.x
1
>>> p.x = 2
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
AttributeError: can't set attribute
```

That looks pretty much like immutability to me.
One of the downsides of this approach is that `p` isn’t an actual object.
It’s a tuple.

```
>>> SomethingCompletelyDifferent = namedtuple("SomethingCompletelyDifferent", "a b")
>>> a = SomethingCompletelyDifferent(1, 2)
>>> p == a
True
>>> p == (1, 2)
True
```

Depending on how you’re using instances of this class, this could be a big deal.
The documentation for the [attrs](https://www.attrs.org/en/stable/index.html) package list [a few more downsides](https://www.attrs.org/en/stable/why.html#namedtuples).

## Attrs

If you don’t mind dependencies, you could use the aforementioned [attrs](https://www.attrs.org/en/stable/index.html) package and do this:

```
import attr


@attr.s(frozen=True)
class Point:
    x = attr.ib()
    y = attr.ib()

    def scale(self, scale):
        return Point(self.x * scale, self.y * scale)

    def translate(self, dx, dy):
        return Point(self.x + dx, self.y + dy)
```

In this case, the decorator `@attr.s(frozen=True)` dictates that values of `x` and `y` cannot be changed by simple assignments.
This behaves like you expect it to:

```
>>> import attr
>>> @attr.s(frozen=True)
... class Point:
...     x = attr.ib()
...     y = attr.ib()
...
>>> p = Point(1, 2)
>>> p.x
1
>>> p.x = 2
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/lucengelen/.local/share/virtualenvs/python-immutable-1HIt_5XS/lib/python3.7/site-packages/attr/_make.py", line 428, in _frozen_setattrs
    raise FrozenInstanceError()
attr.exceptions.FrozenInstanceError
>>> p == (1, 2)
False
>>> p == Point(1, 2)
True
>>> p == Point(2, 1)
False
```

You can still mutate instances of this class, but not by accident:

```
>>> p = Point(1, 2)
>>> p.__dict__["x"] = 100
>>> p
Point(x=100, y=2)
```

## Data Classes

Since Python 3.7, you can use [data classes](https://docs.python.org/3/library/dataclasses.html) to achieve something similar to the variant using [attrs](https://www.attrs.org/en/stable/index.html):

```
from dataclasses import dataclass


@dataclass(frozen=True)
class Point:
    x: int
    y: int

    def scale(self, scale):
        return Point(self.x * scale, self.y * scale)

    def translate(self, dx, dy):
        return Point(self.x + dx, self.y + dy)
```

Here, the decorator `@dataclass(frozen=True)` dictates that the values of `x` and `y` cannot be changed by simple assignments.
This also behaves like you would expect:

```
>>> from dataclasses import dataclass
>>> @dataclass(frozen=True)
... class Point:
...     x: int
...     y: int
...
>>> p = Point(1, 2)
>>> p.x = 100
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "<string>", line 3, in __setattr__
dataclasses.FrozenInstanceError: cannot assign to field 'x'
>>> p = Point(1, 2)
>>> p == Point(1, 2)
True
>>> p == Point(2, 1)
False
>>> p == (1, 2)
False
```

You can mutate instances in the same way as above, but I won’t believe you if say you did this by mistake.

## Conclusion

If you want to play around with these variants, you could use the Python shell. You could also take a look at the following repo: [https://github.com/ljpengelen/immutable-python-objects](https://github.com/ljpengelen/immutable-python-objects).

My personal conclusion after reviewing these variants is that I won’t replace all the named tuples in existing projects just yet.
I don’t expect to get burned by the unfortunate behavior concerning equality.
For future projects, however, I’ll probably go with data classes.
