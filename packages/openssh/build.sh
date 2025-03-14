TERMUX_PKG_HOMEPAGE=https://www.openssh.com/
TERMUX_PKG_DESCRIPTION="Secure shell for logging into a remote machine"
TERMUX_PKG_LICENSE="BSD"
TERMUX_PKG_VERSION=8.1p1
TERMUX_PKG_SHA256=02f5dbef3835d0753556f973cd57b4c19b6b1f6cd24c03445e23ac77ca1b93ff
TERMUX_PKG_SRCURL=https://fastly.cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_DEPENDS="libandroid-support, ldns, openssl, libedit, termux-auth, krb5, zlib"
TERMUX_PKG_CONFLICTS="dropbear"
# --disable-strip to prevent host "install" command to use "-s", which won't work for target binaries:
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--disable-etc-default-login
--disable-lastlog
--disable-libutil
--disable-pututline
--disable-pututxline
--disable-strip
--disable-utmp
--disable-utmpx
--disable-wtmp
--disable-wtmpx
--sysconfdir=$TERMUX_PREFIX/etc/ssh
--with-cflags=-Dfd_mask=int
--with-ldns
--with-libedit
--with-mantype=man
--without-ssh1
--without-stackprotect
--with-pid-dir=$TERMUX_PREFIX/var/run
--with-privsep-path=$TERMUX_PREFIX/var/empty
--with-xauth=$TERMUX_PREFIX/bin/xauth
--with-kerberos5
ac_cv_func_endgrent=yes
ac_cv_func_fmt_scaled=no
ac_cv_func_getlastlogxbyname=no
ac_cv_func_readpassphrase=no
ac_cv_func_strnvis=no
ac_cv_header_sys_un_h=yes
ac_cv_search_getrrsetbyname=no
ac_cv_func_bzero=yes
"
TERMUX_PKG_MAKE_INSTALL_TARGET="install-nokeys"
TERMUX_PKG_RM_AFTER_INSTALL="bin/slogin share/man/man1/slogin.1"
TERMUX_PKG_CONFFILES="etc/ssh/ssh_config etc/ssh/sshd_config var/service/sshd/run var/service/sshd/log/run"

termux_step_pre_configure() {
	# Certain packages are not safe to build on device because their
	# build.sh script deletes specific files in $TERMUX_PREFIX.
	if $TERMUX_ON_DEVICE_BUILD; then
		termux_error_exit "Package '$TERMUX_PKG_NAME' is not safe for on-device builds."
	fi

	autoreconf

    ## Configure script require this variable to set
    ## prefixed path to program 'passwd'
    export PATH_PASSWD_PROG="${TERMUX_PREFIX}/bin/passwd"

	CPPFLAGS+=" -DHAVE_ATTRIBUTE__SENTINEL__=1 -DBROKEN_SETRESGID -DTERMUX_EXPOSE_FILE_OFFSET64"
	LD=$CC # Needed to link the binaries
	LDFLAGS+=" -llog" # liblog for android logging in syslog hack
}

termux_step_post_configure() {
	# We need to remove this file before installing, since otherwise the
	# install leaves it alone which means no updated timestamps.
	rm -Rf $TERMUX_PREFIX/etc/moduli
}

termux_step_post_make_install() {
	# OpenSSH 7.0 disabled ssh-dss by default, keep it for a while in Termux:
	echo -e "PrintMotd yes\nPasswordAuthentication yes\nPubkeyAcceptedKeyTypes +ssh-dss\nSubsystem sftp $TERMUX_PREFIX/libexec/sftp-server" > $TERMUX_PREFIX/etc/ssh/sshd_config
	printf "PubkeyAcceptedKeyTypes +ssh-dss\nSendEnv LANG\n" > $TERMUX_PREFIX/etc/ssh/ssh_config
	install -Dm700 $TERMUX_PKG_BUILDER_DIR/source-ssh-agent.sh $TERMUX_PREFIX/bin/source-ssh-agent
	install -Dm700 $TERMUX_PKG_BUILDER_DIR/ssh-with-agent.sh $TERMUX_PREFIX/bin/ssha
	install -Dm700 $TERMUX_PKG_BUILDER_DIR/sftp-with-agent.sh $TERMUX_PREFIX/bin/sftpa

	# Install ssh-copy-id:
	cp $TERMUX_PKG_SRCDIR/contrib/ssh-copy-id.1 $TERMUX_PREFIX/share/man/man1/
	cp $TERMUX_PKG_SRCDIR/contrib/ssh-copy-id $TERMUX_PREFIX/bin/
	chmod +x $TERMUX_PREFIX/bin/ssh-copy-id

	mkdir -p $TERMUX_PREFIX/var/run
	echo "OpenSSH needs this folder to put sshd.pid in" >> $TERMUX_PREFIX/var/run/README.openssh

	mkdir -p $TERMUX_PREFIX/etc/ssh/
	cp $TERMUX_PKG_SRCDIR/moduli $TERMUX_PREFIX/etc/ssh/moduli

	# Setup sshd services
	mkdir -p $TERMUX_PREFIX/var/service
	cd $TERMUX_PREFIX/var/service
	mkdir -p sshd/log
	echo '#!/bin/sh' > sshd/run
	echo 'exec sshd -D -e 2>&1' >> sshd/run
	chmod +x sshd/run
	touch sshd/down
	ln -sf $TERMUX_PREFIX/share/termux-services/svlogger sshd/log/run
}

termux_step_post_massage() {
	# Verify that we have man pages packaged (#1538).
	local manpage
	for manpage in ssh-keyscan.1 ssh-add.1 scp.1 ssh-agent.1 ssh.1; do
		if [ ! -f share/man/man1/$manpage.gz ]; then
			termux_error_exit "Missing man page $manpage"
		fi
	done
}

termux_step_create_debscripts() {
	echo "#!$TERMUX_PREFIX/bin/sh" > postinst
	echo "mkdir -p \$HOME/.ssh" >> postinst
	echo "touch \$HOME/.ssh/authorized_keys" >> postinst
	echo "chmod 700 \$HOME/.ssh" >> postinst
	echo "chmod 600 \$HOME/.ssh/authorized_keys" >> postinst
	echo "" >> postinst
	echo "for a in rsa dsa ecdsa ed25519; do" >> postinst
	echo "	  KEYFILE=$TERMUX_PREFIX/etc/ssh/ssh_host_\${a}_key" >> postinst
	echo "	  test ! -f \$KEYFILE && ssh-keygen -N '' -t \$a -f \$KEYFILE" >> postinst
	echo "done" >> postinst
	echo "exit 0" >> postinst
	chmod 0755 postinst
}
