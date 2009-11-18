#!/usr/bin/perl
use feature ':5.10';
use strict;
use DateTime;
use Date::Calc qw(Add_Delta_Days);
use File::Path qw(mkpath);
use File::Spec::Functions qw(catdir catfile);

use Getopt::Long ();

# Get command line options
Getopt::Long::Parser->new(
    config => [ qw(bundling no_ignore_case no_require_order) ],
)->getoptions(
    'date=s' => \(my ($date) = qx[date --iso-8601] =~ m/(\S+)/),
) or die "Can't getoptions()";

my $osmdiff20 = '~/src/osm-applications-utils-planet.osm-perl/osmdiff20.pl';
my $osmosis   = '~/src/osm-applications-utils-osmosis-trunk/bin/osmosis';
my $date_osm_dir  = "/var/www/osm.nix.is/archive/$date";
my $date_diff_dir  = "/var/www/osm.nix.is/diff/archive/$date";
my $latest_diff_dir = "/var/www/osm.nix.is/diff/latest";

system "mkdir -p $date_diff_dir" and die "mkdir -p $date_diff_dir: $!";
chdir $date_diff_dir or die "can't chdir($date_diff_dir): $!";

my %area = (
    # All of Iceland
    '.' => { size => 1024*6 },

    # bbox = left,bottom,right,top

    # Towns
    Akureyri  => { bbox => '-18.1688,65.6443,-18.0487,65.7071' },
    'Akranes' => { bbox => '-22.103,64.3047,-22.025,64.3337' },
    'Ólafsfjörður' => { bbox => '-18.6709,66.0666,-18.6304,66.0797' },
    'Dalvík' => { bbox => '-18.5564,65.9651,-18.5174,65.9783' },
    'Egilsstaðir' => { bbox => '-14.4374,65.2537,-14.3698,65.2939'  },
    'Ísafjörður' => { bbox => '-23.2193,66.0459,-23.1026,66.0832' },
    'Ásbrú' => { bbox => '-22.6008,63.9569,-22.548,63.9827' },
    'Húsavík' => { bbox => '-17.3664,66.0284,-17.321,66.0542' },
    'Vopnafjörður' => { bbox => '-14.8424,65.7446,-14.8144,65.7622' },
    'Seyðisfjörður' => { bbox => '-14.0193,65.2575,-13.9857,65.2684' },
    'Neskaupstaður' => { bbox => '-13.7593,65.1245,-13.6429,65.1561' },
    'Eskifjörður' => { bbox => '-14.0481,65.0567,-13.9832,65.084' },
    'Höfn' => { bbox => '-15.2259,64.2298,-15.1703,64.2692' },
    'Vík' => { bbox => '-19.0329,63.4108,-18.9874,63.4285' },
    'Hvolsvöllur' => { bbox => '-20.2515,63.7417,-20.2054,63.7583' },
    'Hella' => { bbox => '-20.4107,63.829,-20.382,63.8381' },
    'Selfoss' => { bbox => '-21.0543,63.9177,-20.9603,63.9572' },
    'Hveragerði' => { bbox => '-21.2117,63.9904,-21.1668,64.0091' },
    'Reykjanesbær' => { bbox => '-22.668,63.945,-22.473,64.014' },
    'Sandgerði' => { bbox => '-22.7215,64.0303,-22.6892,64.0462' },
    'Grindavík' => { bbox => '-22.45,63.8318,-22.4128,63.8502' },
    'Vestmannaeyjar' => { bbox => '-20.3188,63.3965,-20.2251,63.4577' },
    'Borgarnes' => { bbox => '-21.9325,64.5321,-21.8826,64.5591' },
    #'' => { bbox => '' },

    'Greater_Reykjavík_Area' => { bbox => '-22.075,64.03,-21.64,64.201' },
    # Within the Reykjavík Area
    'Reykjavík' => { bbox => '-22.042,64.092,-21.732,64.181' },
    'Kópavogur' => { bbox => '-21.948,64.074,-21.797,64.123' },
    'Mosfellsbær' => { bbox => '-21.737,64.1483,-21.6494,64.1891' },
    'Hafnafjörður' => { bbox => '-22.0014,64.0348,-21.9118,64.0845' },
);

my ($year, $month, $day) = $date =~ /^(\d+)-(\d+)-(\d+)$/;
my $time = DateTime->new(year => $year, month => $month, day => $day)->epoch;
my $i = 1; for my $area (sort keys %area)
{
    warn "Generating $area ($i/" . (scalar keys %area) . ")"; $i++;
    my $bbox = $area{$area}->{bbox};
    my $size = $area{$area}->{size} // 1024*2;

    my $outdir = catdir($date_diff_dir, $area);

    # Day
    generate_area($time, -1, '01-day', $bbox, $size, $outdir);

    # Week
    generate_area($time, -7, '07-week', $bbox, $size, $outdir);

    # Month
    generate_area($time, -30, '30-month', $bbox, $size, $outdir);

    # Maybe year
    my $delta = -365;
    my ($sec, $min, $hour, $mday, $mon, $y, $wday, $yday, $isdst) = localtime $time;
    my ($year, $month_no_leading, $day_no_leading) = Add_Delta_Days(1900+$y, $mon+1, $mday, $delta);
    my $month = sprintf "%02i", $month_no_leading;
    my $day = sprintf "%02i", $day_no_leading;
    my $from_file_orig = "/var/www/osm.nix.is/archive/$year-$month-$day/Iceland.osm.bz2";
    if (-f $from_file_orig) {
        generate_area($time, $delta, '365-year', $bbox, $size, $outdir);
    }
}

#
# Delete temporary .osm files
#
system qq[find $date_diff_dir -type f -name '*.osm' -exec rm -v {} \\;];

#
# link latest to todays generated stuff
#
if (-l $latest_diff_dir) {
    unlink $latest_diff_dir or die "unlink($latest_diff_dir): $!";
}
symlink($date_diff_dir, $latest_diff_dir) or die "symlink($date_diff_dir, $latest_diff_dir): $!";

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
    my ($fv) = qx[bzcat $from_file_orig | head -n2 | grep "^<osm"] =~ /version="(.*?)"/;
    my $to_file_orig   = catfile($date_osm_dir, 'Iceland.osm.bz2');
    my ($tv) = qx[bzcat $to_file_orig | head -n2 | grep "^<osm"] =~ /version="(.*?)"/;
    my ($from_file, $to_file);

    unless ($bbox) {
        $from_file = $from_file_orig;
        $to_file   = $to_file_orig;
    } else {
        my $osmosis_bbox = bbox_to_osmosis_bbox($bbox);
        my $from = "$outdir/$year-$month-$day.osm";
        my $to   = "$outdir/$date.osm";

        my $from_osmosis_cmd = qq[$osmosis --read-xml-$fv $from_file_orig --bounding-box-$fv completeWays=no $osmosis_bbox --write-xml-$fv '$from'];
        my $to_osmosis_cmd   = qq[$osmosis --read-xml-$tv $to_file_orig --bounding-box-$tv completeWays=no $osmosis_bbox --write-xml-$tv '$to'];

        system $from_osmosis_cmd and die "Can't execute `$from_osmosis_cmd': $!";
        if (-f $to and not -z $to) {
            warn "`$to' already exists, no need to generate it";
        } else {
            system $to_osmosis_cmd and die "Can't execute `$to_osmosis_cmd': $!";
        }

        $from_file = $from;
        $to_file   = $to;
    }

    if (not -f $from_file or not -f $to_file) {
        die "Both input files need to exist:\n" . `du -sh $from_file $to_file`;
    }

    my $cmd = "$^X $osmdiff20 $from_file $to_file $label.html $label.png $size";
    system $cmd and die "Can't osmdiff ($!): $cmd";
}

sub bbox_to_osmosis_bbox
{
    my $bbox = shift;
    my %bbox;
    @bbox{qw(left bottom right top)} = split /,/, $bbox;
    return "left=$bbox{left} bottom=$bbox{bottom} right=$bbox{right} top=$bbox{top}";
}
