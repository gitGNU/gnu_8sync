## Copyright © 2015, 2016, 2017 Christopher Allan Webber <cwebber@dustycloud.org>

## parts of this automake recipe borrowed from:

## GNU Guix --- Functional package management for GNU
## Copyright © 2012, 2013, 2014, 2015 Ludovic Courtès <ludo@gnu.org>
## Copyright © 2013 Andreas Enge <andreas@enge.fr>
## Copyright © 2015 Alex Kost <alezost@gmail.com>

## Sly
## Copyright (C) 2013, 2014 David Thompson <dthompson2@worcester.edu>

## This program is free software: you can redistribute it and/or
## modify it under the terms of the GNU General Public License as
## published by the Free Software Foundation, either version 3 of the
## License, or (at your option) any later version.
##
## This program is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
## General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see
## <http://www.gnu.org/licenses/>.

GOBJECTS = $(SOURCES:%.scm=%.go)
nobase_mod_DATA = $(SOURCES)
nobase_go_DATA = $(GOBJECTS)

# Make sure source files are installed first, so that the mtime of
# installed compiled files is greater than that of installed source
# files.  See
# <http://lists.gnu.org/archive/html/guile-devel/2010-07/msg00125.html>
# for details.
guile_install_go_files = install-nobase_goDATA
$(guile_install_go_files): install-nobase_modDATA

GUILE_WARNINGS = -Wunbound-variable -Warity-mismatch -Wformat
SUFFIXES = .scm .go
.scm.go:
	$(AM_V_GEN)$(top_builddir)/pre-inst-env $(GUILE_TOOLS) compile $(GUILE_WARNINGS) -o "$@" "$<"

moddir=$(prefix)/share/guile/site/2.2
godir=$(libdir)/guile/2.2/ccache

SOURCES =  \
	8sync.scm					\
	8sync/agenda.scm				\
	8sync/repl.scm					\
	8sync/actors.scm				\
	8sync/debug.scm					\
	8sync/ports.scm					\
	8sync/contrib/base64.scm			\
	8sync/contrib/sha-1.scm				\
	8sync/systems/irc.scm				\
	8sync/systems/web.scm				\
	8sync/systems/websocket.scm			\
	8sync/systems/websocket/client.scm		\
	8sync/systems/websocket/frame.scm		\
	8sync/systems/websocket/server.scm		\
	8sync/systems/websocket/utils.scm

TESTS =							\
	tests/test-agenda.scm				\
	tests/test-actors.scm

TEST_EXTENSIONS = .scm

SCM_LOG_COMPILER = $(GUILE)
AM_SCM_LOG_FLAGS = --no-auto-compile -L $(top_srcdir)

CLEANFILES = 						\
	$(GOBJECTS)					\
	$(TESTS:tests/%.scm=%.log)			\
	*.log *.tar.gz


EXTRA_DIST = 						\
	$(SOURCES)					\
	$(TESTS)					\
	$(NOCOMP_SOURCES)				\
	COPYING-gplv3.txt				\
	pre-inst-env.in					\
	bootstrap.sh					\
	guix.scm					\
	tests/utils.scm					\
	demos/run-demo.sh				\
	demos/ircbot.scm				\
	demos/actors/botherbotherbother.scm		\
	demos/actors/simplest-possible.scm		\
	demos/actors/robotscanner.scm


## Make changelog on demand

dist-hook: gen-ChangeLog
# gen-AUTHORS might be useful to borrow from Guix

gen-ChangeLog:
	if test -d .git; then				\
	  $(top_srcdir)/build-aux/gitlog-to-changelog --since 2015-11-28	\
	    > $(distdir)/cl-t;				\
	  rm -f $(distdir)/ChangeLog;			\
	  mv $(distdir)/cl-t $(distdir)/ChangeLog;	\
	fi

## Texinfo stuff

info_TEXINFOS = doc/8sync.texi

8sync_TEXINFOS =				\
  doc/fdl.texi

dvi-local: # Skip dvi docs
