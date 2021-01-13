KNOCONFIG         = knoconfig
KNOBUILD          = knobuild
LIBZIPINSTALL     = libzip-install

prefix		::= $(shell ${KNOCONFIG} prefix)
libsuffix	::= $(shell ${KNOCONFIG} libsuffix)
INIT_CFLAGS     ::= ${CFLAGS} -I. -fPIC 
INIT_LDFAGS     ::= ${LDFLAGS} -fPIC 
KNO_CFLAGS	::= -I. -fPIC $(shell ${KNOCONFIG} cflags)
KNO_LDFLAGS	::= -fPIC $(shell ${KNOCONFIG} ldflags)
KNO_LIBS	::= $(shell ${KNOCONFIG} libs)
LIBZIP_CFLAGS   ::= $(shell INSTALLROOT=${LIBZIPINSTALL} ./etc/pkc --static --cflags libzip)
LIBZIP_LDFLAGS  ::= $(shell INSTALLROOT=${LIBZIPINSTALL} ./etc/pkc --static --libs libzip)
CMODULES	::= $(DESTDIR)$(shell ${KNOCONFIG} cmodules)
LIBS		::= $(shell ${KNOCONFIG} libs)
LIB		::= $(shell ${KNOCONFIG} lib)
INCLUDE		::= $(shell ${KNOCONFIG} include)
KNO_VERSION	::= $(shell ${KNOCONFIG} version)
KNO_MAJOR	::= $(shell ${KNOCONFIG} major)
KNO_MINOR	::= $(shell ${KNOCONFIG} minor)
PKG_VERSION     ::= $(shell cat ./version)
PKG_MAJOR       ::= $(shell cat ./version | cut -d. -f1)
FULL_VERSION    ::= ${KNO_MAJOR}.${KNO_MINOR}.${PKG_VERSION}
PATCHLEVEL      ::= $(shell u8_gitpatchcount ./version)
PATCH_VERSION   ::= ${FULL_VERSION}-${PATCHLEVEL}

PKG_NAME	::= ziptools
DPKG_NAME	::= ${PKG_NAME}_${PATCH_VERSION}
SUDO            ::= $(shell which sudo)
CFLAGS		  = ${INIT_CFLAGS} ${KNO_CFLAGS} ${LIBZIP_CFLAGS}
LDFLAGS		  = ${INIT_LDFLAGS} ${KNO_LDFLAGS} ${LIBZIP_LDFLAGS}
MKSO		  = $(CC) -shared $(LDFLAGS) $(LIBS)
MSG		  = echo
SYSINSTALL        = /usr/bin/install -c
DIRINSTALL        = /usr/bin/install -d
MACLIBTOOL	  = $(CC) -dynamiclib -single_module -undefined dynamic_lookup \
			$(LDFLAGS)

GPGID             = FE1BC737F9F323D732AA26330620266BE5AFF294
CODENAME	::= $(shell ${KNOCONFIG} codename)
REL_BRANCH	::= $(shell ${KNOBUILD} getbuildopt REL_BRANCH current)
REL_STATUS	::= $(shell ${KNOBUILD} getbuildopt REL_STATUS stable)
REL_PRIORITY	::= $(shell ${KNOBUILD} getbuildopt REL_PRIORITY medium)
ARCH            ::= $(shell ${KNOBUILD} getbuildopt BUILD_ARCH || uname -m || echo x86_64)
APKREPO         ::= $(shell ${KNOBUILD} getbuildopt APKREPO /srv/repo/kno/apk)
APK_ARCH_DIR      = ${APKREPO}/staging/${ARCH}

STATICLIBS=${LIBZIPINSTALL}/lib/libzip.a

default build:
	make ${STATICLIBS}
	make ziptools.${libsuffix}

libzip-build libzip-install:
	${DIRINSTALL} $@

libzip/.git:
	git submodule init
	git submodule update
libzip-build/Makefile: libzip/.git libzip-build libzip-install
	cd libzip-build; cmake -DENABLE_AUTOMATIC_INIT_AND_CLEANUP=OFF \
	      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	      -DBUILD_SHARED_LIBS=off \
	      -DCMAKE_INSTALL_PREFIX=../libzip-install \
	      ../libzip

ziptools.o: ziptools.c makefile ${STATICLIBS}
	$(CC) $(CFLAGS) -D_FILEINFO="\"$(shell u8_fileinfo ./$< $(dirname $(pwd))/)\"" -o $@ -c $<
	@$(MSG) CC "(ZIPTOOLS)" $@
ziptools.so: ziptools.o makefile ${STATICLIBS}
	 $(MKSO) -o $@ ziptools.o -Wl,-soname=$(@F).${FULL_VERSION} \
	          -Wl,--allow-multiple-definition \
	          -Wl,--whole-archive ${STATICLIBS} -Wl,--no-whole-archive \
			${LDFLAGS}
	 @$(MSG) MKSO "(ZIPTOOLS)" $@

ziptools.dylib: ziptools.o
	@$(MACLIBTOOL) -install_name \
		`basename $(@F) .dylib`.${KNO_MAJOR}.dylib \
		$(DYLIB_FLAGS) $(LIBZIP_LDFLAGS) \
		-o $@ ziptools.o 
	@$(MSG) MACLIBTOOL "(ZIPTOOLS)" $@

libzip-install/lib/libzip.a: libzip-build/Makefile libzip-install
	make -C libzip-build install
	if test -d libzip-install/lib; then \
	  echo > /dev/null; \
	elif test -d libzip-install/lib64; then \
	  ln -sf lib64 libzip-install/lib; \
	else echo "No install libdir"; \
	fi

staticlibs: ${STATICLIBS}

ziptools.so ziptools.dylib: staticlibs

${CMODULES}:
	@install -d ${CMODULES}

install: build ${CMODULES}
	${SUDO} u8_install_shared ${PKG_NAME}.${libsuffix} ${CMODULES} ${FULL_VERSION} "${SYSINSTALL}"

clean:
	rm -f *.o *.${libsuffix} *.${libsuffix}*
deepclean deep-clean: clean
	rm -rf libzip-build libzip-install
fresh: clean
	make
deep-fresh: deep-clean
	make

gitup gitup-trunk:
	git checkout trunk && git pull

# Debian packaging

DEBFILES=changelog.base compat control copyright dirs docs install

debian: ziptools.c makefile \
	dist/debian/rules dist/debian/control \
	dist/debian/changelog.base
	rm -rf debian
	cp -r dist/debian debian
	cd debian; chmod a-x ${DEBFILES}

debian/changelog: debian ziptools.c makefile
	cat debian/changelog.base | \
		u8_debchangelog kno-${PKG_NAME} ${CODENAME} ${REL_BRANCH} ${PATCH_VERSION} \
			${REL_STATUS} ${REL_PRIORITY} \
	    > $@.tmp
	if test ! -f debian/changelog; then \
	  mv debian/changelog.tmp debian/changelog; \
	elif diff debian/changelog debian/changelog.tmp 2>&1 > /dev/null; then \
	  mv debian/changelog.tmp debian/changelog; \
	else rm debian/changelog.tmp; fi

dist/debian.built: ziptools.c makefile debian/changelog
	dpkg-buildpackage -sa -us -uc -b -rfakeroot && \
	touch $@

dist/debian.signed: dist/debian.built
	@if test "${GPGID}" = "none" || test -z "${GPGID}"; then  	\
	  echo "Skipping debian signing";				\
	  touch $@;							\
	else 								\
	  echo debsign --re-sign -k${GPGID} ../kno-ziptools_*.changes; 	\
	  debsign --re-sign -k${GPGID} ../kno-ziptools_*.changes && 	\
	  touch $@;							\
	fi;

deb debs dpkg dpkgs: dist/debian.signed

debinstall: dist/debian.signed
	${SUDO} dpkg -i ../kno-ziptools*.deb

debclean: clean
	rm -rf ../kno-ziptools_* ../kno-ziptools-* debian dist/debian.*

debfresh:
	make debclean
	make dist/debian.signed

# Alpine packaging

staging/alpine:
	@install -d $@

staging/alpine/APKBUILD: dist/alpine/APKBUILD staging/alpine
	cp dist/alpine/APKBUILD staging/alpine

staging/alpine/kno-${PKG_NAME}.tar: staging/alpine
	git archive --prefix=kno-${PKG_NAME}/ -o staging/alpine/kno-${PKG_NAME}.tar HEAD

dist/alpine.setup: staging/alpine/APKBUILD makefile ${STATICLIBS} \
	staging/alpine/kno-${PKG_NAME}.tar
	if [ ! -d ${APK_ARCH_DIR} ]; then mkdir -p ${APK_ARCH_DIR}; fi && \
	( cd staging/alpine; \
		abuild -P ${APKREPO} clean cleancache cleanpkg && \
		abuild checksum ) && \
	touch $@

dist/alpine.done: dist/alpine.setup
	( cd staging/alpine; abuild -P ${APKREPO} ) && touch $@
dist/alpine.installed: dist/alpine.setup
	( cd staging/alpine; abuild -i -P ${APKREPO} ) && touch dist/alpine.done && touch $@


alpine: dist/alpine.done
install-alpine: dist/alpine.done

.PHONY: alpine

