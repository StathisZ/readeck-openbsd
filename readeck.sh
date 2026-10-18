#!/bin/sh
# readeck.sh - add a private, Tailscale-only Readeck read-it-later server to a
# self-managed OpenBSD server. No OpenBSD package or binary exists, so build it
# on another machine with readeck-build and copy it to /root/readeck first.
# Re-run with a newer /root/readeck to upgrade; a failed upgrade rolls back.
# by Stathis, https://nevrast.xyz
# INSTALL: scp readeck readeck.sh root@server: ; ssh root@server sh readeck.sh
# Readeck listens on 127.0.0.1:8099 and is published on tailnet port 8445.
# If 8445 is taken ('tailscale serve status' lists used ports), run with
# TSPORT=<port>. If 8099 is taken, change port= below.
# Tailscale was chosen because it keeps Readeck off the public
# internet. To reach it another way (a reverse proxy with TLS, WireGuard, an
# SSH tunnel), delete the last section and point that at 127.0.0.1:8099.

if [[ $(id -u) -ne 0 || $(uname) != "OpenBSD" ]]; then
	echo "must be run as root on OpenBSD"
	exit 1
fi

port=8099
tsport=${TSPORT:-8445}

# SERVICE USER + DATA (config, database and saved articles all live in /var/readeck)
id _readeck >/dev/null 2>&1 || useradd -c Readeck -d /var/empty -s /sbin/nologin _readeck
install -d -o _readeck -m 700 /var/readeck

# minimal config; Readeck adds a secret key and the remaining defaults on first start
if [ ! -f /var/readeck/config.toml ]; then
	cat > /var/readeck/config.toml <<CONFEOF
[main]
data_directory = "/var/readeck/data"

[server]
host = "127.0.0.1"
port = $port
CONFEOF
	chown _readeck /var/readeck/config.toml
fi

# RC.D SERVICE
cat > /etc/rc.d/readeck <<RCEOF
#!/bin/ksh
daemon="/usr/local/bin/readeck"
daemon_flags="serve -config /var/readeck/config.toml"
daemon_user="_readeck"
daemon_logger="daemon.info"

. /etc/rc.d/rc.subr

rc_bg="YES"
rc_cmd \$1
RCEOF
chmod 555 /etc/rc.d/readeck
rcctl enable readeck

# INSTALL OR UPGRADE THE BINARY, keeping the old binary and data for rollback
upgraded=0
if [ -f /root/readeck ]; then
	if [ -x /usr/local/bin/readeck ]; then
		rcctl stop readeck
		rm -rf /var/readeck.bak
		cp -Rp /var/readeck /var/readeck.bak
		cp -p /usr/local/bin/readeck /usr/local/bin/readeck.bak
		upgraded=1
	fi
	install -m 755 -o root -g bin /root/readeck /usr/local/bin/readeck
	rm /root/readeck
fi

rcctl restart readeck
sleep 5
if ! ftp -VMo /dev/null "http://127.0.0.1:$port/login"; then
	if [ $upgraded -eq 1 ]; then
		echo "new Readeck did not answer -- rolling back binary and data"
		rcctl stop readeck
		mv /usr/local/bin/readeck.bak /usr/local/bin/readeck
		rm -rf /var/readeck
		mv /var/readeck.bak /var/readeck
		rcctl start readeck
		echo "Rolled back: the previous version is running again."
		exit 1
	fi
	echo "Readeck is not answering on port $port. Check 'tail -30 /var/log/daemon'."
	exit 1
fi
/usr/local/bin/readeck version

# PUBLISH PRIVATELY OVER TAILSCALE (optional, see the header; needs Tailscale installed and logged in:
# pkg_add tailscale ; rcctl enable tailscaled ; rcctl start tailscaled ; tailscale up)
tailscale serve --bg --https=$tsport "http://127.0.0.1:$port"
tailscale serve status
echo "Done. Open the tailnet address above and create your account on the first visit."
