check_sip_call
==============

Testing a SIP call with Icinga or Nagios.

The plugin will initiate a SIP call over a registrar or proxy. It expects the
other end to pick up the call and either end the call after a timeout, or when
the other end hangs up.

## Requirements and Acknowledgment

The plugin is based on the Perl module [`Net::SIP`](http://search.cpan.org/search?query=Net%3A%3ASIP&mode=module)
and their examples.

You will also need [`Monitoring::Plugin`](http://search.cpan.org/search?query=Monitoring%3A%3APlugin&mode=module).

## Behavior

Considered OK:

* Call is established and hung up by peer
* Call is established and ends after timeout (30 seconds)
* Call is established and no audio is received for 10 seconds

Considered CRITICAL:

* Invite fails (incorrect number, rejection, auth, network error)
* Invite times out after 30 seconds

Currently the plugin does not register with the proxy or registrar, it just
invites a peer (with authentication if necessary).

## Arguments

```
Usage: check_sip_call.pl [-v] -F <SIP-URL> -T <SUP-URL>

 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][@file]
   Read options from an ini file. See https://www.monitoring-plugins.org/doc/extra-opts.html
   for usage and examples.
 -F, --from=SIP-URL
   SIP identify your are calling from
 -T, --to=SIP-URL
   SIP identify your are calling to
 -R, --registrar=hostname
   SIP registrar you call via
 -O, --proxy=hostname
   SIP proxy you call via
 -U, --username=username
   username for authenticating to SIP registrar or proxy
 -P, --password=password
   password for authenticating to SIP registrar or proxy
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 15)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)
```

## Examples

Simple call without full SIP URLs:

```
./check_sip_call.pl \
  --username johndoe --password test123 \
  --registrar sip.example.com \
  --to +49911928850
```

Using full URLs:

```
./check_sip_call.pl \
  --username 123456789 \
  --password test123 \
  --registrar 217.10.79.9:5060 \
  --from sip:123456789@sipgate.de \
  --to sip:0911928850@sipgate.de
```

Output for a timed out invite:

    SIP_CALL CRITICAL - Invite ran into timeout after 15 seconds | elapsed_invite=15.00;;;0;;15

Output for a rejected call:

    SIP_CALL CRITICAL - Inviting sip:012345678@sip.example.com failed: Failed with error 22 code=486 | elapsed_invite=9.50;;;0;;15

Output for a successful call:

    SIP_CALL OK - Call successful, finished audio. | elapsed_invite=6.96;;;0;;15 elapsed_talking=10.00;;;0;;15

Output for a successful, but hangup, call:

    SIP_CALL OK - Call successful, peer hung up. | elapsed_invite=4.73;;;0;;15 elapsed_talking=2.52;;;0;;15

## Installation

On Debian / Ubuntu:

    apt-get install libmonitoring-plugin-perl libnet-sip-perl
    cp check_sip_call.pl /usr/lib/nagios/plugin/check_sip_call
    chmod 755 /usr/lib/nagios/plugin/check_sip_call

	/usr/lib/nagios/plugin/check_sip_call --help

## Known Issues

Net::SIP wants to establish a IPv6 connection. Workaround: Use IPv4 address

## License

    Copyright (C) 2017 NETWAYS GmbH <info@netways.de>
                       Markus Frosch <markus.frosch@netways.de>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
