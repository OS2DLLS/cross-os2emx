# Makefile to build cross-os2emx

PACKAGE := cross-os2emx
VERSION := $(shell git describe --abbrev=0)

TARC := tar cvzf
TARX := tar xvzf
TARBALL := $(PACKAGE)-$(VERSION).tar.gz

# Prefer the system Linux host compilers over Nix wrapper compilers. The latter
# can place glibc headers before libstdc++ and break <cstdlib>'s include_next.
HOST_SYSTEM_PATH ?= /usr/bin:/bin
export PATH := $(HOST_SYSTEM_PATH):$(PATH)

# Binutils links host ar against flex's libfl; system GCC needs this Nix
# package library path explicitly when host tools come from /usr/bin.
HOST_FLEX_PATH := $(shell command -v flex 2>/dev/null)
ifneq ($(strip $(HOST_FLEX_PATH)),)
HOST_FLEX_LIBDIR ?= $(abspath $(dir $(HOST_FLEX_PATH))/../lib)
export LIBRARY_PATH := $(HOST_FLEX_LIBDIR)$(if $(strip $(LIBRARY_PATH)),:$(LIBRARY_PATH))
# The Nix flex library is linked against its own glibc. Keep host tools that
# load libfl from mixing that libm with the system libc.
HOST_FLEX_GLIBC_LIBDIR := $(shell ldd $(HOST_FLEX_LIBDIR)/libfl.so.2 2>/dev/null | awk '/libc.so.6 =>/ { print $$3; exit }' | xargs dirname)
ifneq ($(strip $(HOST_FLEX_GLIBC_LIBDIR)),)
export LD_LIBRARY_PATH := $(HOST_FLEX_GLIBC_LIBDIR)$(if $(strip $(LD_LIBRARY_PATH)),:$(LD_LIBRARY_PATH))
endif
endif

# Set the out-of-tree build root before deriving PREFIX/BINDIR.
OS2EMX_BUILD_ROOT ?= /data/build-nix
OS2EMX_CROSS_BUILD_ROOT ?= $(patsubst %/,%,$(OS2EMX_BUILD_ROOT))/cross-os2emx/bare-make

# The default toolchain is self-contained under the out-of-tree build root.
# Override PREFIX explicitly when an installation outside that tree is wanted.
PREFIXROOT ?= $(HOME)
PREFIX ?= $(OS2EMX_CROSS_BUILD_ROOT)/toolchain
BINDIR := $(PREFIX)/bin
LIBDIR := $(PREFIX)/lib
SHAREDIR := $(PREFIX)/share

TARGETSPEC := i686-pc-os2-emx
TARGETCPU := $(firstword $(subst -, ,$(TARGETSPEC)))
TARGETPREFIX := $(PREFIX)/$(TARGETSPEC)
TARGETBINDIR := $(TARGETPREFIX)/bin
TARGETINCDIR := $(TARGETPREFIX)/include
TARGETLIBDIR := $(TARGETPREFIX)/lib

SYSNAME := $(shell uname -s)

# Keep host AR untouched for the Linux-host build tools (Autotools/libtool).
# The target archiver is named explicitly in the generated cross-toolchain.
EMX_AR := $(BINDIR)/$(TARGETSPEC)-ar
EMX_ARFLAGS := cru

MKDIR_P := mkdir -p
RM := rm -f
INSTALL := install
INSTALLDATA := $(INSTALL) -m 644
UNZIP := unzip -u
WGET := wget
CP := cp
LN_S := ln -s
MV := mv
SED := sed
TOUCH := touch


AUTOTOOLSDIR ?= $(OS2EMX_CROSS_BUILD_ROOT)/autotools
AUTOCONFTGZ := autoconf-2.69.tar.gz
AUTOCONFTGZURL := https://ftp.gnu.org/gnu/autoconf/$(AUTOCONFTGZ)
AUTOMAKETGZ := automake-1.18.1.tar.gz
AUTOMAKETGZURL := https://ftp.gnu.org/gnu/automake/$(AUTOMAKETGZ)
LIBTOOLTGZ := 2.5.4-os2-r2.tar.gz
LIBTOOLTGZURL := https://github.com/komh/libtool-os2/archive/refs/tags/$(LIBTOOLTGZ)
LIBTOOLDIR := $(AUTOTOOLSDIR)/libtool-os2-$(LIBTOOLTGZ:.tar.gz=)
LIBTOOLBOOTSTRAPBUILDDIR := $(LIBTOOLDIR)/build
LIBTOOLBUILDDIR := $(LIBTOOLDIR)/build.all-libtool

OS2EMX_SOURCE_ROOT ?= $(abspath ..)
BINUTILSDIR ?= $(OS2EMX_SOURCE_ROOT)/binutils-os2
BINUTILSBUILDDIR ?= $(OS2EMX_CROSS_BUILD_ROOT)/binutils
LIBCDIR ?= $(OS2EMX_SOURCE_ROOT)/libc-os2
GCCDIR ?= $(OS2EMX_SOURCE_ROOT)/gcc-os2
GCCBUILDDIR ?= $(OS2EMX_CROSS_BUILD_ROOT)/gcc
GCCPREREQSDIR ?= $(OS2EMX_CROSS_BUILD_ROOT)/gcc-prerequisites
GCCPREREQSDRIVERDIR ?= $(OS2EMX_CROSS_BUILD_ROOT)/gcc-prerequisites-driver
CMAKEBUILDDIR ?= $(OS2EMX_CROSS_BUILD_ROOT)/cmake-build
EMXDIR := $(LIBCDIR)/src/emx
EMXOUTDIR ?= $(OS2EMX_CROSS_BUILD_ROOT)/emxtools/$(TARGETSPEC)
EXTRASDIR := extras
EXTRASBUILDDIR ?= $(OS2EMX_CROSS_BUILD_ROOT)/extras
SETEMXENV := $(EXTRASBUILDDIR)/setemxenv
SETEMXENV_IN := $(EXTRASDIR)/setemxenv.in
PKGCONFIG := $(EXTRASBUILDDIR)/pkg-config
PKGCONFIG_IN := $(EXTRASDIR)/pkg-config.in
LXLITESRC := $(EXTRASDIR)/$(SYSNAME)/lxLite
LXLITEDST := $(EXTRASBUILDDIR)/$(SYSNAME)/lxlite

MESONDIR ?= $(OS2EMX_CROSS_BUILD_ROOT)/meson
MESONVER := 1.11.1
MESONTGZ := meson-$(MESONVER).tar.gz
MESONTGZXDIR := $(MESONTGZ:.tar.gz=)
MESONTGZURL := https://github.com/mesonbuild/meson/releases/download/$(MESONVER)/$(MESONTGZ)
MESONCROSSFILE := $(MESONDIR)/$(TARGETSPEC)
MESONCROSSFILEIN := $(CURDIR)/meson/$(TARGETSPEC)

CMAKEDIR ?= $(OS2EMX_SOURCE_ROOT)/cmake-os2
CMAKECROSSFILE := $(OS2EMX_CROSS_BUILD_ROOT)/cmake-cross/$(TARGETSPEC).cmake
CMAKECROSSFILEIN := $(CURDIR)/cmake/$(TARGETSPEC).cmake.in

LIBCZIP := libc-0_1_14-1_oc00.zip
LIBCZIPURL := https://rpm.netlabs.org/release/00/zip/$(LIBCZIP)
LIBCZIPDIR := $(OS2EMX_CROSS_BUILD_ROOT)/libc-$(TARGETSPEC)
LIBCFENVH := $(LIBCDIR)/src/emx/include/fenv.h

.PHONY: all
all: install

.PHONY: all-autotools
all: all-autotools
all-autotools:

.PHONY: all-autotools-autoconf
all-autotools: all-autotools-autoconf
all-autotools-autoconf: $(AUTOTOOLSDIR)/autoconf.done
$(AUTOTOOLSDIR)/autoconf.done: $(AUTOTOOLSDIR)/$(AUTOCONFTGZ)
	cd $(AUTOTOOLSDIR); \
	$(TARX) $(AUTOCONFTGZ) || exit 1; \
	cd $(AUTOCONFTGZ:.tar.gz=); \
	./configure --prefix=$(AUTOTOOLSDIR) && $(MAKE) && $(MAKE) install
	$(TOUCH) $@

$(AUTOTOOLSDIR)/$(AUTOCONFTGZ):
	$(MKDIR_P) $(AUTOTOOLSDIR)
	cd $(AUTOTOOLSDIR); $(WGET) $(AUTOCONFTGZURL)

.PHONY: all-autotools-automake
all-autotools: all-autotools-automake
all-autotools-automake: $(AUTOTOOLSDIR)/automake.done
$(AUTOTOOLSDIR)/automake.done: $(AUTOTOOLSDIR)/$(AUTOMAKETGZ)
	cd $(AUTOTOOLSDIR); \
	$(TARX) $(AUTOMAKETGZ) || exit 1; \
	cd $(AUTOMAKETGZ:.tar.gz=); \
	./configure --prefix=$(AUTOTOOLSDIR) && $(MAKE) && $(MAKE) install
	$(TOUCH) $@

$(AUTOTOOLSDIR)/$(AUTOMAKETGZ):
	$(MKDIR_P) $(AUTOTOOLSDIR)
	cd $(AUTOTOOLSDIR); $(WGET) $(AUTOMAKETGZURL)

.PHONY: all-autotools-libtool
all-autotools: all-autotools-libtool
all-autotools-libtool: $(AUTOTOOLSDIR)/libtool.done
$(AUTOTOOLSDIR)/libtool.done: $(AUTOTOOLSDIR)/$(LIBTOOLTGZ)
	test -f $(LIBTOOLDIR)/configure \
	  || ( cd $(AUTOTOOLSDIR); $(TARX) $(LIBTOOLTGZ); ) \
	  || exit 1;
	$(MKDIR_P) $(LIBTOOLBOOTSTRAPBUILDDIR)
	cd $(LIBTOOLBOOTSTRAPBUILDDIR); \
	../configure --prefix=$(AUTOTOOLSDIR) \
	  && $(MAKE) && $(MAKE) install
	$(TOUCH) $@

$(AUTOTOOLSDIR)/$(LIBTOOLTGZ):
	$(MKDIR_P) $(AUTOTOOLSDIR)
	cd $(AUTOTOOLSDIR); $(WGET) $(LIBTOOLTGZURL)

.PHONY: all-binutils
all: all-binutils
all-binutils: all-autotools
	$(MKDIR_P) $(BINUTILSBUILDDIR)
	export PATH=$(AUTOTOOLSDIR)/bin:$$PATH; \
	cd $(BINUTILSBUILDDIR); \
	test "$(FORCE_CONFIGURE)" = "" -a -f config.status || \
	  OS2EMX_PREFIX=$(PREFIX) PREFIXROOT=$(PREFIXROOT) \
	    $(abspath $(BINUTILSDIR))/conf-cross-os2emx || exit 1; \
	$(MAKE)

.PHONY: all-libc
all: all-libc
all-libc: $(LIBCZIPDIR)/libc.done
$(LIBCZIPDIR)/libc.done: $(LIBCZIPDIR)/$(LIBCZIP) $(LIBCFENVH)
	$(UNZIP) $(LIBCZIPDIR)/$(LIBCZIP) -d $(LIBCZIPDIR)
	$(INSTALL) -d $(LIBCZIPDIR)/@unixroot/usr/include
	$(CP) $(LIBCFENVH) $(LIBCZIPDIR)/@unixroot/usr/include/fenv.h
	$(TOUCH) $@

$(LIBCZIPDIR)/$(LIBCZIP):
	$(MKDIR_P) $(LIBCZIPDIR)
	cd $(LIBCZIPDIR); $(WGET) $(LIBCZIPURL)

.PHONY: all-emxtools
all: all-emxtools
all-emxtools: all-binutils
	$(MAKE) -C $(EMXDIR) -f Makefile.cross \
	  EMXDIR=$(abspath $(EMXDIR)) BINUTILSDIR=$(abspath $(BINUTILSDIR)) \
	  BINUTILSBUILDDIR=$(abspath $(BINUTILSBUILDDIR)) OUTDIR=$(abspath $(EMXOUTDIR)) \
	  OS2EMX_BUILD_ROOT=$(OS2EMX_BUILD_ROOT) OS2EMX_PREFIX=$(PREFIX) \
	  PREFIXROOT=$(PREFIXROOT) PREFIX=$(PREFIX)

.PHONY: all-extras
all: all-extras
all-extras: $(SETEMXENV) $(PKGCONFIG)

$(SETEMXENV): $(SETEMXENV_IN)
	$(MKDIR_P) $(@D)
	$(SED) -e 's,@PREFIX@,$(PREFIX),g' -e 's,@TARGETSPEC@,$(TARGETSPEC),g' \
	       < $< > $@
	chmod +x $@

$(PKGCONFIG): $(PKGCONFIG_IN)
	$(MKDIR_P) $(@D)
	$(SED) -e 's,@PREFIX@,$(PREFIX),g' -e 's,@TARGETSPEC@,$(TARGETSPEC),g' \
	       < $< > $@
	chmod +x $@

ifeq ($(SYSNAME),Linux)
all-extras: $(LXLITEDST)

$(LXLITEDST): $(LXLITESRC)
	$(MKDIR_P) $(@D)
	$(CP) -a $< $@
endif

.PHONY: all-gcc
all: all-gcc
all-gcc: all-autotools install-binutils install-libc install-emxtools \
         install-extras
	$(MKDIR_P) $(GCCBUILDDIR) $(GCCPREREQSDIR) \
	  $(GCCPREREQSDRIVERDIR)/gcc $(GCCPREREQSDRIVERDIR)/contrib
	export PATH=$(AUTOTOOLSDIR)/bin:$$PATH; \
	$(RM) $(GCCPREREQSDRIVERDIR)/gcc/BASE-VER \
	  $(GCCPREREQSDRIVERDIR)/contrib/prerequisites.sha512; \
	$(LN_S) $(abspath $(GCCDIR))/gcc/BASE-VER \
	  $(GCCPREREQSDRIVERDIR)/gcc/BASE-VER || exit 1; \
	$(LN_S) $(abspath $(GCCDIR))/contrib/prerequisites.sha512 \
	  $(GCCPREREQSDRIVERDIR)/contrib/prerequisites.sha512 || exit 1; \
	cd $(GCCPREREQSDRIVERDIR); \
	$(abspath $(GCCDIR))/contrib/download_prerequisites \
	  --directory=$(abspath $(GCCPREREQSDIR)) || exit 1; \
	cd $(GCCBUILDDIR); \
	if test "$(FORCE_CONFIGURE)$(FORCE_GCC_CONFIGURE)" != ""; then $(RM) config.cache */config.cache */*/config.cache */*/*/config.cache; fi; \
	test "$(FORCE_CONFIGURE)$(FORCE_GCC_CONFIGURE)" = "" -a -f config.status || \
	  OS2EMX_PREFIX=$(PREFIX) PREFIXROOT=$(PREFIXROOT) \
	    GCC_PREREQS_DIR=$(abspath $(GCCPREREQSDIR)) \
	    ac_cv_have_decl_basename_const_charp_=yes \
	    ac_cv_have_decl_strstr_const_charp_const_charp_=yes \
	    gcc_cv_have_decl_sbrk=yes \
	    gcc_cv_have_decl_strsignal=yes \
	    $(abspath $(GCCDIR))/conf-cross-os2emx || exit 1; \
	export PATH=$(DESTDIR)$(BINDIR):$$PATH; \
	$(MAKE) all-gcc all-target-libgcc all-target-libstdc++-v3 all-target-libssp

.PHONY: all-meson
all: all-meson
all-meson: $(MESONCROSSFILE)-aout.txt $(MESONCROSSFILE)-omf.txt \
           $(MESONDIR)/meson.done

$(MESONCROSSFILE)-aout.txt: $(MESONCROSSFILEIN)-aout.txt.in
	$(MKDIR_P) $(@D)
	$(SED) -e 's,@PREFIX@,$(PREFIX),g' -e 's,@TARGETSPEC@,$(TARGETSPEC),g' \
	       -e 's,@TARGETCPU@,$(TARGETCPU),g' < $< > $@

$(MESONCROSSFILE)-omf.txt: $(MESONCROSSFILEIN)-omf.txt.in
	$(MKDIR_P) $(@D)
	$(SED) -e 's,@PREFIX@,$(PREFIX),g' -e 's,@TARGETSPEC@,$(TARGETSPEC),g' \
	       -e 's,@TARGETCPU@,$(TARGETCPU),g' < $< > $@

$(MESONDIR)/meson.done: $(MESONDIR)/$(MESONTGZ)
	$(TARX) $(MESONDIR)/$(MESONTGZ) -C $(MESONDIR)
	$(TOUCH) $@

$(MESONDIR)/$(MESONTGZ):
	$(MKDIR_P) $(MESONDIR)
	cd $(MESONDIR); $(WGET) $(MESONTGZURL)

.PHONY: all-cmake
all: all-cmake
all-cmake: $(CMAKECROSSFILE)
	$(MKDIR_P) $(CMAKEBUILDDIR)
	cd $(CMAKEBUILDDIR); \
	test -f Makefile || \
	  $(abspath $(CMAKEDIR))/configure --prefix=$(PREFIX) || exit 1;
	export PATH=$(DESTDIR)$(BINDIR):$(PATH); \
	$(MAKE) -C $(CMAKEBUILDDIR)

$(CMAKECROSSFILE): $(CMAKECROSSFILEIN)
	$(MKDIR_P) $(@D)
	$(SED) -e 's,@PREFIX@,$(PREFIX),g' -e 's,@TARGETSPEC@,$(TARGETSPEC),g' \
	       -e 's,@TARGETCPU@,$(TARGETCPU),g' < $< > $@

.PHONY: all-libtool
all: all-libtool
all-libtool: $(AUTOTOOLSDIR)/all-libtool.done
$(AUTOTOOLSDIR)/all-libtool.done: $(AUTOTOOLSDIR)/$(LIBTOOLTGZ)
	test -f $(LIBTOOLDIR)/configure \
	  || ( cd $(AUTOTOOLSDIR); $(TARX) $(LIBTOOLTGZ); ) \
	  || exit 1;
	$(MKDIR_P) $(LIBTOOLBUILDDIR)
	cd $(LIBTOOLBUILDDIR); \
	../configure --prefix=$(PREFIX) --disable-ltdl-install \
	  && $(MAKE)
	$(TOUCH) $@

.PHONY: install
install:

.PHONY: install-binutils
install: install-binutils
install-binutils: all-binutils
	$(MAKE) -C $(BINUTILSBUILDDIR) install DESTDIR=$(DESTDIR)

.PHONY: install-libc
install: install-libc
install-libc: all-libc
	$(INSTALL) -d $(DESTDIR)$(TARGETPREFIX)
	$(CP) -a "$(LIBCZIPDIR)/@unixroot/usr/include" \
	         "$(DESTDIR)$(TARGETPREFIX)"
	$(CP) -a "$(LIBCZIPDIR)/@unixroot/usr/lib" \
	         "$(DESTDIR)$(TARGETPREFIX)"
	$(INSTALL) -d $(DESTDIR)$(TARGETPREFIX)/usr
	$(RM) $(DESTDIR)$(TARGETPREFIX)/usr/include
	$(LN_S) ../include $(DESTDIR)$(TARGETPREFIX)/usr/include
	$(RM) $(DESTDIR)$(TARGETPREFIX)/usr/lib
	$(LN_S) ../lib $(DESTDIR)$(TARGETPREFIX)/usr/lib

.PHONY: install-emxtools
install: install-emxtools
install-emxtools: all-emxtools
	$(MAKE) -C $(EMXDIR) -f Makefile.cross install \
	  EMXDIR=$(abspath $(EMXDIR)) BINUTILSDIR=$(abspath $(BINUTILSDIR)) \
	  BINUTILSBUILDDIR=$(abspath $(BINUTILSBUILDDIR)) OUTDIR=$(abspath $(EMXOUTDIR)) \
	  OS2EMX_BUILD_ROOT=$(OS2EMX_BUILD_ROOT) OS2EMX_PREFIX=$(PREFIX) \
	  PREFIXROOT=$(PREFIXROOT) PREFIX=$(PREFIX) DESTDIR=$(DESTDIR)

.PHONY: install-extras
install: install-extras
install-extras: all-extras
	$(INSTALL) -d $(DESTDIR)$(TARGETBINDIR)
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	for f in "$(EXTRASDIR)/"* "$(EXTRASDIR)/$(SYSNAME)/"* ; do \
	  test -f $$f || continue; \
	  test "$${f%.in}" = "$$f" || continue; \
	  n=$$(basename $$f); \
	  if test -L $$f || test ! -x $$f ; then \
	    $(CP) -a $$f $(DESTDIR)$(TARGETBINDIR)/$$n; \
	  else \
	    $(INSTALL) $$f $(DESTDIR)$(TARGETBINDIR)/$$n; \
	  fi; \
	  if test -x $$f ; then \
	    $(LN_S) -f ../$(TARGETSPEC)/bin/$$n $(DESTDIR)$(BINDIR); \
	    $(LN_S) -f ../$(TARGETSPEC)/bin/$$n \
	               $(DESTDIR)$(BINDIR)/$(TARGETSPEC)-$$n; \
	  fi; \
	done; \
	for f in "$(SETEMXENV)" "$(PKGCONFIG)" "$(LXLITEDST)"; do \
	  test -f $$f || continue; \
	  n=$$(basename $$f); \
	  if test -L $$f || test ! -x $$f; then \
	    $(CP) -a $$f $(DESTDIR)$(TARGETBINDIR)/$$n; \
	  else \
	    $(INSTALL) $$f $(DESTDIR)$(TARGETBINDIR)/$$n; \
	  fi; \
	  if test -x $$f; then \
	    $(LN_S) -f ../$(TARGETSPEC)/bin/$$n $(DESTDIR)$(BINDIR); \
	    $(LN_S) -f ../$(TARGETSPEC)/bin/$$n \
	               $(DESTDIR)$(BINDIR)/$(TARGETSPEC)-$$n; \
	  fi; \
	done

.PHONY: install-gcc
install: install-gcc
install-gcc: all-gcc
	$(MAKE) -C $(GCCBUILDDIR) DESTDIR=$(DESTDIR) \
	           install-gcc install-target-libgcc install-target-libstdc++-v3 \
	           install-target-libssp

.PHONY: install-meson
install: install-meson
install-meson: all-meson
	$(INSTALLDATA) -D $(MESONCROSSFILE)-aout.txt \
	  $(DESTDIR)$(SHAREDIR)/meson/cross/$(notdir $(MESONCROSSFILE)-aout.txt)
	$(INSTALLDATA) -D $(MESONCROSSFILE)-omf.txt \
	  $(DESTDIR)$(SHAREDIR)/meson/cross/$(notdir $(MESONCROSSFILE)-omf.txt)
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(CP) -a $(MESONDIR)/$(MESONTGZXDIR) $(DESTDIR)$(BINDIR)
	$(LN_S) -f $(MESONTGZXDIR)/meson.py $(DESTDIR)$(BINDIR)/meson

.PHONY: install-cmake
install: install-cmake
install-cmake: all-cmake
	$(INSTALLDATA) -D $(CMAKECROSSFILE) \
	  $(DESTDIR)$(SHAREDIR)/cmake/cross/$(notdir $(CMAKECROSSFILE))
	$(MAKE) -C $(CMAKEBUILDDIR) install DESTDIR=$(DESTDIR)
	@if test -n "$(HOST_FLEX_GLIBC_LIBDIR)"; then \
	  set -eu; \
	  bindir="$(DESTDIR)$(BINDIR)"; \
	  mv -f "$$bindir/cmake" "$$bindir/cmake.real"; \
	  { printf '%s\n' \
	      '#!/bin/sh' \
	      'export LD_LIBRARY_PATH="$(HOST_FLEX_GLIBC_LIBDIR)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"' \
	      'case "$$0" in */*) _cmake_path="$$0" ;; *) _cmake_path=$$(command -v "$$0") ;; esac' \
	      '_cmake_dir=$$(CDPATH= cd "$$(dirname "$$_cmake_path")" && pwd)' \
	      'exec "$$_cmake_dir/cmake.real" "$$@"'; \
	  } > "$$bindir/cmake.tmp"; \
	  chmod +x "$$bindir/cmake.tmp"; \
	  mv -f "$$bindir/cmake.tmp" "$$bindir/cmake"; \
	fi

.PHONY: install-libtool
install: install-libtool
install-libtool: all-libtool
	$(MAKE) -C $(LIBTOOLBUILDDIR) install DESTDIR=$(DESTDIR)

.PHONY: test
test: install
	$(MAKE) -C tests PREFIXROOT=$(PREFIXROOT) PREFIX=$(PREFIX) TARGET=$(TARGETSPEC)

.PHONY: dist
dist:
	destdir=$(CURDIR)/$(PACKAGE)-$(VERSION); \
	prefixroot=$(patsubst %/,%,$(PREFIXROOT)); \
	test -z "$$prefixroot" || \
	  prefixrootfirst=/$$(echo $$prefixroot | cut -d '/' -f 2); \
	prefix=$(PREFIX); \
	test -z "$$prefixroot" || \
	  prefix=$$(echo $$prefix | $(SED) -e "s,$$prefixroot,,"); \
	prefixfirst=/$$(echo $$prefix | cut -d '/' -f 2); \
	$(MAKE) install DESTDIR=$$destdir PREFIXROOT=$(PREFIXROOT) && \
	{ \
	  test -z "$$prefixroot" || \
	    $(MV) $$destdir$$prefixroot$$prefixfirst $$destdir$$prefixfirst; \
	} && \
	$(SED) -e "s/@VER@/$(VERSION)/g" $(PACKAGE).txt \
	  > $$destdir/$(PACKAGE)-$(VERSION).txt && \
	$(CP) README.md $$destdir && \
	{ test -z "$$prefixrootfirst" || $(RM) -r $$destdir$$prefixrootfirst; }; \
	$(RM) $(TARBALL); \
	$(TARC) $(TARBALL) $(PACKAGE)-$(VERSION); \
	$(RM) -r $(PACKAGE)-$(VERSION)

.PHONY: clean
clean:
	$(RM) $(TARBALL)

.PHONY: clean-autotools
clean: clean-autotools
clean-autotools:
	$(RM) -r $(AUTOTOOLSDIR)

.PHONY: clean-binutils
clean: clean-binutils
clean-binutils:
	$(RM) -r $(BINUTILSBUILDDIR)

.PHONY: clean-libc
clean: clean-libc
clean-libc:
	$(RM) -r $(LIBCZIPDIR)

.PHONY: clean-emxtools
clean: clean-emxtools
clean-emxtools:
	$(MAKE) -C $(EMXDIR) -f Makefile.cross clean \
	  EMXDIR=$(abspath $(EMXDIR)) BINUTILSDIR=$(abspath $(BINUTILSDIR)) \
	  BINUTILSBUILDDIR=$(abspath $(BINUTILSBUILDDIR)) OUTDIR=$(abspath $(EMXOUTDIR)) \
	  OS2EMX_BUILD_ROOT=$(OS2EMX_BUILD_ROOT) OS2EMX_PREFIX=$(PREFIX) \
	  PREFIXROOT=$(PREFIXROOT) PREFIX=$(PREFIX)

.PHONY: clean-extras
clean: clean-extras
clean-extras:
	$(RM) $(SETEMXENV) $(PKGCONFIG) $(LXLITEDST)

.PHONY: clean-gcc
clean: clean-gcc
clean-gcc:
	$(RM) -r $(GCCBUILDDIR) $(GCCPREREQSDIR) $(GCCPREREQSDRIVERDIR)

.PHONY: clean-meson
clean: clean-meson
clean-meson:
	$(RM) $(MESONCROSSFILE)-aout.txt $(MESONCROSSFILE)-omf.txt
	$(RM) $(MESONDIR)/$(MESONTGZ)
	$(RM) -r $(MESONDIR)/$(MESONTGZXDIR)
	$(RM) $(MESONDIR)/meson.done

.PHONY: clean-cmake
clean: clean-cmake
clean-cmake:
	$(RM) $(CMAKECROSSFILE)
	$(RM) -r $(CMAKEBUILDDIR)

.PHONY: clean-libtool
clean: clean-libtool
clean-libtool:
	$(RM) -r $(LIBTOOLBUILDDIR)
	$(RM) $(AUTOTOOLSDIR)/all-libtool.done

.PHONY: clean-test
clean: clean-test
clean-test:
	$(MAKE) -C tests clean
