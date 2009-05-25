#!/usr/bin/perl
# Originally written by Björgvin Ragnarsson, modified by Ævar Arnfjörð Bjarmason
use strict;
use Date::Calc qw(Add_Delta_Days);

my $osmdiff20 = '~/src/osm-applications-utils-planet.osm-perl/osmdiff20.pl';
my $latest_osm = '/var/www/osm.nix.is/latest/Iceland.osm.bz2';
my ($today) = qx[date --iso-8601] =~ m/(\S+)/;

my $today_dir  = "/var/www/osm.nix.is/diff/archive/$today";
my $latest_dir = "/var/www/osm.nix.is/diff/latest";
system "mkdir -p $today_dir" and die "mkdir -p $today_dir: $!";
chdir $today_dir or die "can't chdir($today_dir): $!";

#
# Generate all the stuff
#

my ($sec, $min, $hour, $mday, $mon, $y, $wday, $yday, $isdst) = localtime (time);

# Day
my ($year, $month_no_leading, $day_no_leading) = Add_Delta_Days(1900+$y, $mon+1, $mday, -1);
my $month = sprintf "%02i", $month_no_leading;
my $day = sprintf "%02i", $day_no_leading;
my $file = "/var/www/osm.nix.is/archive/$year-$month-$day/Iceland.osm.bz2";
system "perl $osmdiff20 $file $latest_osm day.html day.png 8192";

# Week
($year, $month_no_leading, $day_no_leading) = Add_Delta_Days(1900+$y, $mon+1, $mday, -7);
$month = sprintf "%02i", $month_no_leading;
$day = sprintf "%02i", $day_no_leading;
$file = "/var/www/osm.nix.is/archive/$year-$month-$day/Iceland.osm.bz2";
system "perl $osmdiff20 $file $latest_osm week.html week.png 8192";

# Month
($year, $month_no_leading, $day_no_leading) = Add_Delta_Days(1900+$y, $mon+1, $mday, -30);
$month = sprintf "%02i", $month_no_leading;
$day = sprintf "%02i", $day_no_leading;
$file = "/var/www/osm.nix.is/archive/$year-$month-$day/Iceland.osm.bz2";
system "perl $osmdiff20 $file $latest_osm month.html month.png 8192";

#
# link latest to today's generated stuff
#
if (-l $latest_dir) {
    unlink $latest_dir or die "unlink($latest_dir): $!";
}
symlink($today_dir, $latest_dir) or die "symlink($today_dir, $latest_dir): $!";
