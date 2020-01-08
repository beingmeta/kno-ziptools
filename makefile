prefix		::= $(shell knoconfig prefix)
libsuffix	::= $(shell knoconfig libsuffix)
KNO_CFLAGS	::= -I. -fPIC $(shell knoconfig cflags)
KNO_LDFLAGS	::= -fPIC $(shell knoconfig ldflags)
LIBZIP_CFLAGS   ::=
LIBZIP_LDFLAGS  ::=
CFLAGS		::= ${CFLAGS} ${KNO_CFLAGS} ${BSON_CFLAGS} ${LIBZIP_CFLAGS}
LDFLAGS		::= ${LDFLAGS} ${KNO_LDFLAGS} ${BSON_LDFLAGS} ${LIBZIP_LDFLAGS}
CMODULES	::= $(DESTDIR)$(shell knoconfig cmodules)
LIBS		::= $(shell knoconfig libs)
LIB		::= $(shell knoconfig lib)
INCLUDE		::= $(shell knoconfig include)
KNO_VERSION	::= $(shell knoconfig version)
KNO_MAJOR	::= $(shell knoconfig major)
KNO_MINOR	::= $(shell knoconfig minor)
PKG_RELEASE	::= $(cat ./etc/release)
DPKG_NAME	::= $(shell ./etc/dpkgname)
MKSO		::= $(CC) -shared $(LDFLAGS) $(LIBS)
MSG		::= echo
SYSINSTALL      ::= /usr/bin/install -c
MOD_NAME	::= ziptools
MOD_RELEASE     ::= $(shell cat etc/release)
MOD_VERSION	::= ${KNO_MAJOR}.${KNO_MINOR}.${MOD_RELEASE}
GPGID           ::= FE1BC737F9F323D732AA26330620266BE5AFF294
SUDO            ::= $(shell which sudo)

default: staticlibs
	make ziptools.${libsuffix}

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
ziptools.so: ziptools.o makefile
	 $(MKSO) -o $@ ziptools.o -Wl,-soname=$(@F).${MOD_VERSION} \
	          -Wl,--allow-multiple-definition \
	          -Wl,--whole-archive ${STATICLIBS} -Wl,--no-whole-archive \
		 $(LDFLAGS) ${STATICLIBS}
	 @$(MSG) MKSO "(ZIPTOOLS)" $@

ziptools.dylib: ziptools.o
	@$(MACLIBTOOL) -install_name \
		`basename $(@F) .dylib`.${KNO_MAJOR}.dylib \
		$(DYLIB_FLAGS) $(LIBZIP_LDFLAGS) \
		-o $@ ziptools.o 
	@$(MSG) MACLIBTOOL "(ZIPTOOLS)" $@

${STATICLIBS}: libzip/cmake-build/Makefile
	make -C libzip/cmake-build install
staticlibs: ${STATICLIBS}

install:
	@${SUDO} ${SYSINSTALL} ${MOD_NAME}.${libsuffix} ${CMODULES}/${MOD_NAME}.so.${MOD_VERSION}
	@echo === Installed ${CMODULES}/${MOD_NAME}.so.${MOD_VERSION}
	@${SUDO} ln -sf ${MOD_NAME}.so.${MOD_VERSION} ${CMODULES}/${MOD_NAME}.so.${KNO_MAJOR}.${KNO_MINOR}
	@echo === Linked ${CMODULES}/${MOD_NAME}.so.${KNO_MAJOR}.${KNO_MINOR} to ${MOD_NAME}.so.${MOD_VERSION}
	@${SUDO} ln -sf ${MOD_NAME}.so.${MOD_VERSION} ${CMODULES}/${MOD_NAME}.so.${KNO_MAJOR}
	@echo === Linked ${CMODULES}/${MOD_NAME}.so.${KNO_MAJOR} to ${MOD_NAME}.so.${MOD_VERSION}
	@${SUDO} ln -sf ${MOD_NAME}.so.${MOD_VERSION} ${CMODULES}/${MOD_NAME}.so
	@echo === Linked ${CMODULES}/${MOD_NAME}.so to ${MOD_NAME}.so.${MOD_VERSION}

clean:
	rm -f *.o *.${libsuffix}
deepclean deep-clean: clean
	if test -f libzip/Makefile; then cd ziptools; make clean; fi;
	rm -rf libzip/cmake-build installed

debian: ziptools.c makefile \
	dist/debian/rules dist/debian/control \
	dist/debian/changelog.base
	rm -rf debian
	cp -r dist/debian debian
	cat debian/changelog.base | etc/gitchangelog kno-ziptools > debian/changelog

debian/changelog: debian ziptools.c makefile
	cat debian/changelog.base | etc/gitchangelog kno-ziptools > $@

debian.built: ziptools.c makefile debian debian/changelog
	dpkg-buildpackage -sa -us -uc -b -rfakeroot && \
	touch $@

debian.signed: debian.built
	debsign --re-sign -k${GPGID} ../kno-ziptools_*.changes && \
	touch $@

debian.updated: debian.signed
	dupload -c ./debian/dupload.conf --nomail --to bionic ../kno-ziptools_*.changes && touch $@

update-apt: debian.updated

debinstall: debian.signed
	${SUDO} dpkg -i ../kno-ziptools*.deb

debclean:
	rm -f ../kno-ziptools_* ../kno-ziptools-* debian/changelog

debfresh:
	make debclean
	make debian.signed
