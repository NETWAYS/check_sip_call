#!/usr/bin/perl
#########################################################################
# check_sip_call
#########################################################################
# Copyright (C) 2017 NETWAYS GmbH <info@netways.de>
#                    Markus Frosch <markus.frosch@netways.de>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#########################################################################

use strict;
use warnings;

eval {
  require Monitoring::Plugin;
  require Net::SIP;
  require Time::HiRes;
  1;
} or do {
  print "Missing a dependency: $@\n";
  exit(3);
};

use Time::HiRes qw(time);

my $exited_normally = 0;
my $P;
my $ua;
my $call;
my $invited = 0;
my $in_call = 0;

# Fall back to unknown when program exits unexpected
sub handle_exit {
  if ($call) {
    # TODO: this causes weird errors, but it ends the call...
    $call->cancel() if ($invited);
    $call->bye() if ($in_call);
    $call->cleanup;
  }
  if ($ua) {
    $ua->cleanup;
  }
  return if $exited_normally;
  exit(3);
}
END { handle_exit; }
$SIG{INT} = \&handle_exit;
$SIG{TERM} = \&handle_exit;
$SIG{ALRM} = sub { print "Plugin timed out!\n"; handle_exit; };

# Handling a normal plugin exit
sub plugin_exit {
  $exited_normally = 1;
  if ($P) {
    return $P->plugin_exit(@_);
  } else {
    return Monitoring::Plugin::Functions::plugin_exit(@_);
  }
}

# Correcting a SIP address with prefix and domain, if provided
sub fix_sip_address {
  my $address = shift;
  my $registrar = shift;
  $address = 'sip:' . $address unless $address =~ /^sip:/;
  $address = $address . '@' . $registrar unless !$registrar or $address =~ /\@/;
  return $address;
}

my $license = "Copyright (C) 2017 NETWAYS GmbH <info\@netways.de>

This Icinga plugin is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

Full license at https://www.gnu.org/licenses/gpl2.txt

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.";

$P = Monitoring::Plugin->new(
  usage => "Usage: %s [-v] -F <SIP-URL> -T <SUP-URL> ",
  license => $license,
  version => "0.1.1",
);
$P->add_arg(
  spec => 'from|F=s',
  help => "-F, --from=SIP-URL\n   SIP identify your are calling from",
);
$P->add_arg(
  spec => 'to|T=s',
  help => "-T, --to=SIP-URL\n   SIP identify your are calling to",
  required => 1,
);
$P->add_arg(
  spec => 'registrar|R=s',
  help => "-R, --registrar=hostname\n   SIP registrar you call via",
);
$P->add_arg(
  spec => 'proxy|O=s',
  help => "-O, --proxy=hostname\n   SIP proxy you call via",
);
$P->add_arg(
  spec => 'username|P=s',
  help => "-U, --username=username\n   username for authenticating to SIP registrar or proxy",
);
$P->add_arg(
  spec => 'password|P=s',
  help => "-P, --password=password\n   password for authenticating to SIP registrar or proxy",
);
$P->add_arg(
  spec    => 'expires=s',
  help    => "--expires=seconds\n   Seconds for the register to expire (Default: 300) (Set -1 to disable)",
  default => 300,
);

$P->getopts;

# Ensure global timeout, twice the timeout plus buffer
alarm $P->opts->timeout * 2 + 2;

# handle input values
unless ($P->opts->registrar) {
  if ($P->opts->proxy) {
    $P->opts->set('registrar', $P->opts->proxy);
  } elsif ($P->opts->from and $P->opts->from =~ /\@(.+(:\d+)?)$/) {
    $P->opts->set('registrar', $1);
  } else {
    plugin_exit(3, 'You need to specify --registrar or set user@domain --from!');
  }
}
$P->opts->set('registrar', $P->opts->registrar . ':5060') unless $P->opts->registrar =~ /:\d+$/;
unless ($P->opts->from) {
  plugin_exit(3, 'You need to specify --from or --username!') unless $P->opts->username;
  $P->opts->set('from', $P->opts->username);
}
$P->opts->set('from', fix_sip_address($P->opts->from, $P->opts->registrar));
$P->opts->set('to', fix_sip_address($P->opts->to, $P->opts->registrar));

# create the user agent
$ua = Net::SIP::Simple->new(
  from => $P->opts->from,
  $P->opts->registrar ? ( registrar => $P->opts->registrar ) : (),
  $P->opts->proxy ? ( outgoing_proxy => $P->opts->proxy ) : (),
  $P->opts->password ? ( auth => [$P->opts->username, $P->opts->password] ) : (),
);

# Register to the server
if ($P->opts->expires > 0) {
  $ua->register(expires => 300);

  plugin_exit(2, sprintf(
    'Register failed %s: %s',
    $P->opts->to,
    $ua->error
  )) if $ua->error;
}

# setup call
my ($invite_final, $peer_hangup, $stopvar, $timeout_invite, $timeout_call);
my $time_start = time();
$call = $ua->invite($P->opts->to,
  # TODO: echo has been disabled with -1, while testing
  # loop hangs when RTP connects and the media is echoed
  init_media    => $ua->rtp('media_recv_echo', undef, -1),
  asymetric_rtp => 1,
  recv_bye      => \$peer_hangup,
  send_bye      => \$stopvar,
  cb_final      => \$invite_final,
);

plugin_exit(2, sprintf(
  'Creating call failed %s: %s',
  $P->opts->to,
  $ua->error
)) unless $call;
$invited = 1;

# wait for invite to complete
$ua->add_timer($P->opts->timeout, \$timeout_invite);
$ua->loop($P->opts->timeout, \$invite_final, \$timeout_invite);
my $time_invite = time();

if ($call->error) {
  plugin_exit(2, sprintf(
    'Inviting %s failed: %s | elapsed_invite=%0.2f;;;0;;%d',
    $P->opts->to,
    $call->error,
    $time_invite-$time_start,
    $P->opts->timeout
  ));
}

# handle timeout during invite
if ($timeout_invite) {
  $stopvar = undef;
  $call->cancel(cb_final => \$stopvar);
  $ua->loop(5, \$stopvar);
  $invited = 0;
  plugin_exit(2, sprintf(
    'Invite ran into timeout after %d seconds | elapsed_invite=%0.2f;;;0;;%d',
    $P->opts->timeout,
    $time_invite-$time_start,
    $P->opts->timeout
  ));
}

# call is connected
$invited = 0;
$in_call = 1;

# run mainloop
$ua->add_timer($P->opts->timeout, \$timeout_call);
while (!$stopvar and !$timeout_call and !$peer_hangup) {
  $ua->loop(1, \$timeout_call, \$stopvar, \$peer_hangup);
}
my $time_finished = time();

# handling the end of call
my $hangup_reason;
if ($peer_hangup) {
  $hangup_reason = 'peer hung up';
} elsif ($stopvar) {
  $hangup_reason = 'finished audio';
} else {
  $hangup_reason = sprintf('stopped call after %d seconds', $P->opts->timeout);
  $stopvar = undef;
  $call->bye(cb_final => \$stopvar);
  $ua->loop(5, \$stopvar);
}
$in_call = 0;

plugin_exit(0, sprintf(
  "Call successful, %s. |"
  ." elapsed_invite=%0.2f;;;0;;%d"
  ." elapsed_talking=%0.2f;;;0;;%d",
  $hangup_reason,
  $time_invite-$time_start,
  $P->opts->timeout,
  $time_finished-$time_invite,
  $P->opts->timeout
));

# vi: ts=2 sw=2 expandtab :
