#!/usr/bin/env perl
use strict;
my $workdir = '/home/avar/src/OSM-Iceland-mkgmap';
chdir $workdir or die "Can't chdir($workdir): $!";

my $sleeptime = 60 * 5;
# 8 digit UID for maps, this is pseudol33t for "Iceland", wrarr!
my $mapname = 13314530;
my $tried_times = 0;

chomp(my $date = `date --iso-8601`);
my $Iceland_Map = "Iceland.osm";
# Sanity check, should be more than around 20 MB
my $min_size = 20 * 10 ** 6;

# mkdir/chdir

# debugging when we run more than once a day
if (-d $date) {
    system "rm $date/*.img" and die $!;
} else {
    mkdir $date or die "Can't mkdir($date): $!";
}
chdir $date or die "Can't chdir($date): $!";

get_osm_map:

# Get the new map
my $ret = system qq[wget -q 'http://www.informationfreeway.org/api/0.5/map?bbox=-24.6333,63.1833,-13.1333,67.2358' -O $Iceland_Map];

if ($ret != 0) {
    warn "Couldn't get $Iceland_Map, sleeping $sleeptime seconds and trying again";
    $tried_times += 1;

    die "Tried $tried_times already, dying" if ($tried_times > 5);
    sleep $sleeptime;

    goto get_osm_map;
}

# Sanity check
my $size = ((stat($Iceland_Map))[7]);
if ($size < $min_size) {
    die "$Iceland_Map should be more than around 20 MB, it's $size bytes";
}

# Generate!
system qq[java -jar /home/avar/src/mkgmap/mkgmap-r630/mkgmap.jar --mapname=$mapname --description="Iceland OSM" --latin1 --gmapsupp $Iceland_Map];

# Symlink latest to the new stuff
chdir $workdir or die "Can't chdir($workdir): $!";
unless (-d 'latest') {
    mkdir 'latest' or die "Can't mkdir(latest): $!";
}

for ($Iceland_Map, "gmapsupp.img", "13314530.img") {
    unlink "latest/$_" if -l "latest/$_";
    symlink "$date/$_", "latest/$_" or die "symlink($date/$_, latest/$_): $!";
}
