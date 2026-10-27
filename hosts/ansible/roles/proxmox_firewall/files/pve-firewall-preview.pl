#!/usr/bin/perl
# Print the rules pve-firewall would load from the current cluster.fw and host.fw, even while
# their enable switch is 0. `pve-firewall compile` prints nothing then, because PVE::Firewall::compile
# returns empty rule sets when the datacenter switch is off (pve-firewall 6.0.6, src/PVE/Firewall.pm).
# The switch is turned on in memory only; no file and no live rule is changed. Read-only.
use strict;
use warnings;

use PVE::Firewall;

PVE::Firewall::set_verbose(1);

my $cluster_conf = PVE::Firewall::load_clusterfw_conf();
$cluster_conf->{options}->{enable} = 1;
my $hostfw_conf = PVE::Firewall::load_hostfw_conf($cluster_conf);
$hostfw_conf->{options}->{enable} = 1;

my ($ruleset, $ipset_ruleset, $rulesetv6) = PVE::Firewall::compile($cluster_conf, $hostfw_conf);

print "ipset cmdlist:\n";
PVE::Firewall::get_ipset_cmdlist($ipset_ruleset);
print "\niptables cmdlist:\n";
PVE::Firewall::get_ruleset_cmdlist($ruleset->{filter});
print "\nip6tables cmdlist:\n";
PVE::Firewall::get_ruleset_cmdlist($rulesetv6->{filter}, "ip6tables");
