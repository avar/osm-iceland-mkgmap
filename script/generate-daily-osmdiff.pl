#!/usr/bin/perl
# Originally written by Björgvin Ragnarsson, modified by Ævar Arnfjörð Bjarmason
use feature ':5.10';
use strict;
use Date::Calc qw(Add_Delta_Days);
use File::Path qw(mkpath);
use File::Spec::Functions qw(catdir catfile);

my $osmdiff20 = '~/src/osm-applications-utils-planet.osm-perl/osmdiff20.pl';
my $osmosis   = '~/src/osm/applications/utils/osmosis/trunk/bin/osmosis';
my ($today) = qx[date --iso-8601] =~ m/(\S+)/;
my $today_osm_dir  = "/var/www/osm.nix.is/archive/$today";
my $today_diff_dir  = "/var/www/osm.nix.is/diff/archive/$today";
my $latest_diff_dir = "/var/www/osm.nix.is/diff/latest";

system "mkdir -p $today_diff_dir" and die "mkdir -p $today_diff_dir: $!";
chdir $today_diff_dir or die "can't chdir($today_diff_dir): $!";

my %area = (
    # All of Iceland
    '.' => { size => 1024*6 },

    # Towns
    Akureyri  => { bbox => '-18.1688,65.6443,-18.0487,65.7071' },
    'Akranes' => { bbox => '-22.103,64.3047,-22.025,64.3337' },
    'Ólafsfjörður' => { bbox => '-18.6709,66.0666,-18.6304,66.0797' },
    'Egilsstaðir' => { bbox => '-14.4374,65.2537,-14.3698,65.2939'  },
    'Ísafjörður' => { bbox => '-23.2193,66.0459,-23.1026,66.0832' },

    'Greater_Reykjavík_Area' => { bbox => '-22.075,64.03,-21.64,64.201' },
    # Within the Reykjavík Area
    'Reykjavík' => { bbox => '-22.042,64.092,-21.732,64.181' },
    'Kópavogur' => { bbox => '-21.948,64.074,-21.797,64.123' },
    'Mosfellsbær' => { bbox => '-21.737,64.1483,-21.6494,64.1891' },
);

my $i = 1;
my $time = time;
for my $area (sort keys %area)
{
    warn "Generating $area ($i/" . (scalar keys %area) . ")"; $i++;
    my $bbox = $area{$area}->{bbox};
    my $size = $area{$area}->{size} // 1024*2;

    my $outdir = catdir($today_diff_dir, $area);

    # Day
    generate_area($time, -1, '01-day', $bbox, $size, $outdir);

    # Week
    generate_area($time, -7, '07-week', $bbox, $size, $outdir);

    # Month
    generate_area($time, -30, '30-month', $bbox, $size, $outdir);
}

#
# Delete temporary .osm files
#
system qq[find $today_diff_dir -type f -name '*.osm' -exec rm -v {} \;];

#
# link latest to todays generated stuff
#
if (-l $latest_diff_dir) {
    unlink $latest_diff_dir or die "unlink($latest_diff_dir): $!";
}
symlink($today_diff_dir, $latest_diff_dir) or die "symlink($today_diff_dir, $latest_diff_dir): $!";

exit 0;

sub generate_area
{
    my ($time, $delta, $label, $bbox, $size, $outdir) = @_;
    my ($sec, $min, $hour, $mday, $mon, $y, $wday, $yday, $isdst) = localtime $time;

    system "mkdir -p '$outdir'" and die "mkdir -p '$outdir': $!";
    chdir $outdir or die "can't chdir($outdir): $!";

    my ($year, $month_no_leading, $day_no_leading) = Add_Delta_Days(1900+$y, $mon+1, $mday, $delta);
    my $month = sprintf "%02i", $month_no_leading;
    my $day = sprintf "%02i", $day_no_leading;

    my $from_file_orig = "/var/www/osm.nix.is/archive/$year-$month-$day/Iceland.osm.bz2";
    my $to_file_orig   = catfile($today_osm_dir, 'Iceland.osm.bz2');
    my ($from_file, $to_file);

    unless ($bbox) {
        $from_file = $from_file_orig;
        $to_file   = $to_file_orig;
    } else {
        my $osmosis_bbox = bbox_to_osmosis_bbox($bbox);
        my $from = "$outdir/$year-$month-$day.osm";
        my $to   = "$outdir/$today.osm";

        my $from_osmosis_cmd = qq[$osmosis -q --read-xml $from_file_orig --bounding-box completeWays=yes $osmosis_bbox --write-xml '$from'];
        my $to_osmosis_cmd   = qq[$osmosis -q --read-xml $to_file_orig --bounding-box completeWays=yes $osmosis_bbox --write-xml '$to'];

        system $from_osmosis_cmd and die "Can't execute `$from_osmosis_cmd': $!";
        system $to_osmosis_cmd and die "Can't execute `$to_osmosis_cmd': $!";

        $from_file = $from;
        $to_file   = $to;
    }

    system "$^X $osmdiff20 $from_file $to_file $label.html $label.png $size" and die "Can't osmdiff: $!";
}

sub bbox_to_osmosis_bbox
{
    my $bbox = shift;
    my %bbox;
    @bbox{qw(left bottom right top)} = split /,/, $bbox;
    return "left=$bbox{left} bottom=$bbox{bottom} right=$bbox{right} top=$bbox{top}";
}
