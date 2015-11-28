8sync: an asynchronous programming library for Guile
====================================================

8sync (pronounced "eight-sync") is an asynchronous programming library
for [GNU Guile](https://www.gnu.org/software/guile/).

Some features:
 - An asynchronous event loop!  Non-blocking on ports and file access.
 - Easy to use!  The =%8sync= operator lets you write
   asynchronous code that looks simple while avoiding callback hell.
   This happens through the magic of
   [delimited continuations](https://www.gnu.org/software/guile/manual/html_node/Prompts.html).
   ([Hence the %](https://www.gnu.org/software/guile/manual/html_node/Shift-and-Reset.html#Shift-and-Reset)!)
 - Provides building blocks on which you can build other asynchronous
   frameworks or paradigms on top of it (some of which will be
   included in the future), like:
   - an actor model implementation
   - the propagator model
   - web frameworks
   - your very heart's desire!

How do I use it?
----------------

For now, read the source ;)

Hey, I ought to get some docs up, right?  Soon, I promise!


License
-------

Everything in here is LGPL v3 or later, as published by the Free
Software Foundation, with exceptions below:

 - Some autotools related files are under the GPL v3 or later in the
   toplevel directory (their headers will say).  I guess if you
   compile things using them, maybe this project becomes GPL v3 or
   later?  I don't think so because the build tools themselves aren't
   linked, but I can't be sure.  If you really care, consider this
   whole project GPL v3 or later optionally... anyway a
   COPYING-gplv3.txt is included for these reasons.
 - Likewise, there's a single utility in tests/utils.scm from David
   Thompson that's under GPLv3 or later.  See above.
