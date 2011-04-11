#!/usr/bin/perl -w

# Author: Maxim Janssens
# Email: maxim@linux.com

use strict;
use LWP::Simple;

# Global Variables
my $calendar = get "https://link.to/ical/calendar" or die "Cannot get calendar: $!\n";
my @lines = split "\n", $calendar;
chomp (my $today = `date '+%Y%m%d'`);
my @employees = ("employee1", "employee2", "employee3", "employee4");
my $directory = "/etc/nagios";
my $confdir = "$directory/conf.d";
my $watchdir = "$directory/nagioswatchers";
my $watchfile = "$confdir/nagioswatch.cfg";
my $nagioscfg = "$directory/nagios.cfg";
my $g = my $i = my $k = my $m = my $w = 0;
my ($date, $summary, $key, $value, $watcher, $lurker, $recipient, $nametmp);
my (@daywatch, @sendlist, @pagers, @previous);
my (%events, %previous, %current);

# main()
print "====GET_WATCHERS====\n";
&get_watchers;
print "====UPDATE_WATCHFILE====\n";
&update_watchfile($daywatch[0],$daywatch[1]);
print "====CHECK_EXISTING====\n";
&check_existing($daywatch[0],$daywatch[1]);
print "====NOTIFY_WATCHERS====\n";
&notify_watchers;
print "===NOTIFY_NAGIOS====\n";
&notify_nagios;

# Subroutines
sub get_watchers {
	foreach my $line (@lines){
		if($line =~ /^\s/){ $line =~ s/^\s//; }

		if($line =~  s/^SUMMARY://){ chomp($summary = $line); $i++; }
		elsif($line =~ s/^DTSTART;VALUE=DATE:// || $line =~ s/^DTSTART;TZID="\w+\/\w+"://){ $line =~ s/^(\d{8})\w+/$1/; chomp($date = $line); $events{$date} = (); $i++; }
		
		if($i == 2){ $events{$date} = $summary; $i = 0; }
		else { next; }
	}

	while(($key, $value) = each(%events)){
		if($key =~ /$today/){ $watcher = $value; } 
	}

	if($watcher eq ''){ 
		print "No watcher found, same watcher today...\n"; 
		exit 0;
	} else { 	
		@daywatch = split ' ', $watcher; 
		my $x = my $i = 0;
		foreach my $entry (@daywatch){
			my $tmp = $employees[$i];
			if($entry !~ /$tmp/i && $x >= 3) { die "Calendar entry does not match any employee: $!\n"; }
			else { print $entry . "\n"; next; }	
		}
	return 0;
	}
}

sub update_watchfile {
	$watcher = $_[0];
	$lurker = $_[1];
	$w = 0;
	open(NAGIOSWATCH, '<', $watchfile) or die "$watchfile can't be opened: $!\n";
		while (<NAGIOSWATCH>){ 
			if(/alias\s+(\w+)/){ $nametmp = lc($1); $previous{$nametmp} = (); }
			if(/pager\s+(\d+)/){ $previous{$nametmp} = $1; $previous[$w] = $1; $w++;  } 
		}
	close NAGIOSWATCH;
	open(NAGIOSWATCH, '>', $watchfile) or die "$watchfile can't be opened: $!\n";
		print NAGIOSWATCH "";
	close NAGIOSWATCH;

	open (NAGIOSWATCH, ">>", $watchfile) or die "$watchfile can't be opened: $!\n";
	open (WATCHER, "$watchdir/$watcher.cfg") or die "$watcher.cfg can't be opened: $!\n";
	open (LURKER, "$watchdir/$lurker.cfg") or die "$lurker.cfg can't be opened: $!\n";
		while (<WATCHER>){ 
			if(/contact_name\s+(\w+)/){ $nametmp = $1; $current{$nametmp} = (); print NAGIOSWATCH "\tcontact_name SynqWatch\n";next; }
			if(/pager\s+(\d+)/){ $current{$nametmp} = $1; print NAGIOSWATCH "$_"; }
			else { print NAGIOSWATCH "$_"; }
		}

	print NAGIOSWATCH "\n";
		while (<LURKER>){ 
			if(/contact_name\s+(\w+)/) { $nametmp = $1; $current{$nametmp} = ();  print NAGIOSWATCH "\tcontact_name SynqLurk\n";next; }
			if(/pager\s+(\d+)/){ $current{$nametmp} = $1; print NAGIOSWATCH "$_"; }
			else { print NAGIOSWATCH "$_"; }
		}

	close WATCHER;
	close LURKER;
	close NAGIOSWATCH;
	
	open(WATCH, '<', $watchfile) or die "$watchfile cannot be opened: $!\n";
		while(<WATCH>){ print; }
	close WATCH;
}

sub check_existing {
	$watcher = $_[0];
	$lurker = $_[1];
	my $z = $m = 0;
	open(NAGIOSWATCH, "<", $watchfile) or die "Can't open $watchfile: $!\n";
	while (<NAGIOSWATCH>){ 
		if(/pager\s+(\d+)/){ $pagers[$m] = $1; $m++; }
	}
	close NAGIOSWATCH;
	
	foreach my $key1 (keys %previous){
		$z = 0;
		foreach my $key2 (keys %current){
			if($key1 ne $key2){ $z++; }
			if($key1 ne $key2 && $z > 1){ &off_duty_watcher($key1, $previous{$key1}) }
		}
	}			

	for(my $i = 0; $i <= $#pagers; $i++){
		if($i == 0 && $pagers[$i] == $previous[$i]){ print "$watcher remains the watcher\n"; }
		elsif($i >= 1 && $pagers[$i] == $previous[$i]){ print "$lurker remains the lurker\n"; }
		else { $sendlist[$i] = $pagers[$i]; }
	}

	foreach(@sendlist){ print "New recipient: $_\n"; }
}

sub notify_watchers {
	my $z = 1;
	foreach(@sendlist){
		$recipient = $_;
		if($z == 1){
#			`/usr/nagios/libexec/send_sms.pl "$watcher, je hebt vanavond 1e NagiosWatch, $lurker heeft 2e Watch." $recipient`;
			print "$watcher is watcher met $recipient\n";
			$z++;
		} elsif($z != 1){
#			`/usr/nagios/libexec/send_sms.pl "$lurker, je hebt vanavond 2e NagiosWatch, $watcher heeft 1e Watch." $recipient`;
			print "$lurker is lurker met $recipient\n";
		}
	}
}	

sub off_duty_watcher {
	my $no_watcher = $_[0];
	my $no_recipient = $_[1];
	if($no_recipient == 0 || $no_watcher eq ''){ die "Too few arguments in subroutine: off_duty_watcher:$!\n"; }
	print "no_watcher is $no_watcher en no_recipient is $no_recipient\n";
#	`/usr/nagios/libexec/send_sms.pl "$no_watcher, je hebt vanaf vandaag geen NagiosWatch meer!" $no_recipient`;
}

sub notify_nagios {
	print "Reloading Nagios ...\n";
	system "/etc/init.d/nagios3 reload";
}
