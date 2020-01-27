KNOCONFIG       ::= knoconfig
prefix		::= $(shell ${KNOCONFIG} prefix)
libsuffix	::= $(shell ${KNOCONFIG} libsuffix)
INIT_CFLAGS     ::= ${CFLAGS} -I. -fPIC 
INIT_LDFAGS     ::= ${LDFLAGS} -fPIC 
KNO_CFLAGS	::= -I. -fPIC $(shell ${KNOCONFIG} cflags)
KNO_LDFLAGS	::= -fPIC $(shell ${KNOCONFIG} ldflags) $(shell ${KNOCONFIG} libs)
LIBZIP_CFLAGS   ::= -Iinstalled/include
LIBZIP_LDFLAGS  ::= -lz -lbz2 -llzma
CFLAGS		::= ${CFLAGS} ${KNO_CFLAGS} ${LIBZIP_CFLAGS}
LDFLAGS		::= ${LDFLAGS} ${KNO_LDFLAGS} ${LIBZIP_LDFLAGS}
CMODULES	::= $(DESTDIR)$(shell ${KNOCONFIG} cmodules)
LIBS		::= $(shell ${KNOCONFIG} libs)
LIB		::= $(shell ${KNOCONFIG} lib)
INCLUDE		::= $(shell ${KNOCONFIG} include)
KNO_VERSION	::= $(shell ${KNOCONFIG} version)
KNO_MAJOR	::= $(shell ${KNOCONFIG} major)
KNO_MINOR	::= $(shell ${KNOCONFIG} minor)
PKG_RELEASE	::= $(cat ./etc/release)
DPKG_NAME	::= $(shell ./etc/dpkgname)
MKSO		::= $(CC) -shared $(LDFLAGS) $(LIBS)
MSG		::= echo
SYSINSTALL      ::= /usr/bin/install -c
MOD_NAME	::= ziptools
MOD_RELEASE     ::= $(shell cat etc/release)
MOD_VERSION	::= ${KNO_MAJOR}.${KNO_MINOR}.${MOD_RELEASE}

GPGID = FE1BC737F9F323D732AA26330620266BE5AFF294
SUDO  = $(shell which sudo)

default build: ziptools.${libsuffix}

STATICLIBS=installed/lib/libzip.a

libzip/.git:
	git submodule init
	git submodule update
libzip/cmake-build/Makefile: libzip/.git
	if test ! -d libzip/cmake-build; then mkdir libzip/cmake-build; fi && \
	cd libzip/cmake-build && \
	cmake -DENABLE_AUTOMATIC_INIT_AND_CLEANUP=OFF \
	      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	      -DBUILD_SHARED_LIBS=off \
	      -DCMAKE_INSTALL_PREFIX=../../installed \
	      ..

ziptools.o: ziptools.c makefile ${STATICLIBS}
	@$(CC) $(CFLAGS) -o $@ -c $<
	@$(MSG) CC "(ZIPTOOLS)" $@
ziptools.so: ziptools.o makefile ${STATICLIBS}
	 $(MKSO) -o $@ ziptools.o -Wl,-soname=$(@F).${MOD_VERSION} \
	          -Wl,--allow-multiple-definition \
	          -Wl,--whole-archive ${STATICLIBS} -Wl,--no-whole-archive \
			${LDFLAGS}
	@if test ! -z "${COPY_CMODS}"; then cp $@ ${COPY_CMODS}; fi;
	 @$(MSG) MKSO "(ZIPTOOLS)" $@

ziptools.dylib: ziptools.o
	@$(MACLIBTOOL) -install_name \
		`basename $(@F) .dylib`.${KNO_MAJOR}.dylib \
		$(DYLIB_FLAGS) $(LIBZIP_LDFLAGS) \
		-o $@ ziptools.o 
	@if test ! -z "${COPY_CMODS}"; then cp $@ ${COPY_CMODS}; fi;
	@$(MSG) MACLIBTOOL "(ZIPTOOLS)" $@

${STATICLIBS}: libzip/cmake-build/Makefile
	make -C libzip/cmake-build install
	if test -d installed/lib; then \
	  echo > /dev/null; \
	elif test -d installed/lib64; then \
	  ln -sf lib64 installed/lib; \
	else echo "No install libdir"; \
	fi

staticlibs: ${STATICLIBS}

ziptools.so ziptools.dylib: staticlibs

install: build
	@${SUDO} ${SYSINSTALL} ${MOD_NAME}.${libsuffix} ${CMODULES}/${MOD_NAME}.so.${MOD_VERSION}
	@echo === Installed ${CMODULES}/${MOD_NAME}.so.${MOD_VERSION}
	@${SUDO} ln -sf ${MOD_NAME}.so.${MOD_VERSION} ${CMODULES}/${MOD_NAME}.so.${KNO_MAJOR}.${KNO_MINOR}
	@echo === Linked ${CMODULES}/${MOD_NAME}.so.${KNO_MAJOR}.${KNO_MINOR} to ${MOD_NAME}.so.${MOD_VERSION}
	@${SUDO} ln -sf ${MOD_NAME}.so.${MOD_VERSION} ${CMODULES}/${MOD_NAME}.so.${KNO_MAJOR}
	@echo === Linked ${CMODULES}/${MOD_NAME}.so.${KNO_MAJOR} to ${MOD_NAME}.so.${MOD_VERSION}
	@${SUDO} ln -sf ${MOD_NAME}.so.${MOD_VERSION} ${CMODULES}/${MOD_NAME}.so
	@echo === Linked ${CMODULES}/${MOD_NAME}.so to ${MOD_NAME}.so.${MOD_VERSION}

clean:
	rm -f *.o *.${libsuffix} *.${libsuffix}*
deepclean deep-clean: clean
	if test -f libzip/Makefile; then cd ziptools; make clean; fi;
	rm -rf libzip/cmake-build installed
fresh: clean
	make

debian: ziptools.c makefile \
	dist/debian/rules dist/debian/control \
	dist/debian/changelog.base
	rm -rf debian
	cp -r dist/debian debian

debian/changelog: debian ziptools.c makefile
	@cat debian/changelog.base | etc/gitchangelog kno-ziptools > $@.tmp
	@if test ! -f debian/changelog; then \
	  mv debian/changelog.tmp debian/changelog; \
	 elif diff debian/changelog debian/changelog.tmp 2>&1 > /dev/null; then \
	  mv debian/changelog.tmp debian/changelog; \
	else rm debian/changelog.tmp; fi

dist/debian.built: ziptools.c makefile debian/changelog
	dpkg-buildpackage -sa -us -uc -b -rfakeroot && \
	touch $@

dist/debian.signed: dist/debian.built
	debsign --re-sign -k${GPGID} ../kno-ziptools_*.changes && \
	touch $@

dist/debian.updated: dist/debian.signed
	dupload -c ./dist/dupload.conf --nomail --to bionic ../kno-ziptools_*.changes && touch $@

deb debs dpkg dpkgs: dist/debian.signed

update-apt: dist/debian.updated

debinstall: dist/debian.signed
	${SUDO} dpkg -i ../kno-ziptools*.deb

debclean: clean
	rm -rf ../kno-ziptools_* ../kno-ziptools-* debian dist/debian.*

debfresh:
	make debclean
	make dist/debian.signed
