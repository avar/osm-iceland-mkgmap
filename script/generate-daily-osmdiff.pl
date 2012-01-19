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

# The time we're generating from
my ($year, $month, $day) = $date =~ /^(\d+)-(\d+)-(\d+)$/;
my $time = DateTime->new(year => $year, month => $month, day => $day)->epoch;

my $date = "$year-$month-$day";
my $real_date = `date --iso-8601`; chomp $real_date;

my $useractivity = '~/src/osm.nix.is/osm-applications-utils-planet.osm-perl/useractivity.pl';
my $osmosis   = '~/src/osm.nix.is/osm-applications-utils-osmosis-trunk/bin/osmosis';
my $date_osm_dir  = "/var/www/osm.nix.is/archive/$date";
my $diff_root = "/var/www/osm.nix.is/diff";
#my $diff_root = "/tmp/diff";
my $date_diff_dir  = "$diff_root/archive/$date";
my $latest_diff_dir = "$diff_root/latest";

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

my @periods = (
    { label => '00-now', delta => 0      , generate => 0, err => 0},
    { label => '01-day', delta => -1     , generate => 1, err => 0},
    { label => '07-week', delta => -7    , generate => 1, err => 0},
    { label => '30-month', delta => -30  , generate => 1, err => 0},
    { label => '365-year', delta => -365 , generate => 1, err => 0},
);

# Generate .osm files with osmosis
for my $period (@periods) {
    my $delta = $period->{delta};
    my ($date, $base_file)= osm_file_delta_ago($time, $delta);

    if (not -f $base_file and $delta < -30) {
        #warn "Not generating delta $delta";
        $period->{generate} = 0;
        next;
    } elsif (not -f $base_file) {
        # It's an error if we can't generate the day/week/month files
        $period->{generate} = 0;
        $period->{err} = 1;
    }

    my $v = osm_version($base_file);
    die "Unable to determine version from $base_file" unless $v;

    my @dirs;
    my $cmd;
    $cmd .= "nice -n 19 $osmosis -quiet \\\n";
    $cmd .= "  --read-xml-$v $base_file \\\n";
    $cmd .= "  --tee-$v " . ((scalar keys %area)) . " \\\n";
    for my $area (sort keys %area) {
        my $bbox = $area{$area}->{bbox};
        my $bbox_cmd = '';
        if ($bbox) {
            my $osmosis_bbox = bbox_to_osmosis_bbox($bbox);
            $bbox_cmd = "--bounding-box-$v completeWays=no $osmosis_bbox ";
        }
        my $out_dir = catdir($date_diff_dir, $area);
        push @dirs => $out_dir;
        $cmd .= "  ${bbox_cmd}--write-xml-$v '$out_dir/$date.osm' \\\n";
    }
    $cmd =~ s[ \\$][];

    # mkdirs
    for my $outdir (@dirs) {
        system "mkdir -p '$outdir'" and die "mkdir -p '$outdir': $!";
        chdir $outdir or die "can't chdir($outdir): $!";
    }

    # osmosis
    #say $cmd;
    system $cmd and die "Can't execute `$cmd': $!";
}

# Generate diffs
for my $period (@periods) {
    my $delta = $period->{delta};
    my $label = $period->{label};
    my $generate = $period->{generate};

    # Skipping this one
    next unless $generate;

    my $i = 1; for my $area (reverse sort keys %area) {
        #warn "Generating $delta $area ($i/" . (scalar keys %area) . ")"; $i++;
        my $size = $area{$area}->{size} // 1024*2;

        my $outdir = catdir($date_diff_dir, $area);

        generate_area($time, $delta, $label, $size, $outdir);
    }
}

# Delete temporary .osm files
#
system qq[find $date_diff_dir -type f -name '*.osm' -exec rm {} \\;];

#
# link latest to todays generated stuff
#
if ($date eq $real_date) {
    if (-l $latest_diff_dir) {
        unlink $latest_diff_dir or die "unlink($latest_diff_dir): $!";
    }
    symlink($date_diff_dir, $latest_diff_dir) or die "symlink($date_diff_dir, $latest_diff_dir): $!";
}


if (my @err = grep { $_->{err} } @periods) {
    say STDERR "Error came up when when generating osmosis delta $_->{delta}" for @err;
    exit 1;
}

exit 0;

sub generate_area
{
    my ($time, $delta, $label, $size, $outdir) = @_;
    my ($sec, $min, $hour, $mday, $mon, $y, $wday, $yday, $isdst) = localtime $time;

    unless (-d $outdir) {
        system "mkdir -p '$outdir'" and die "mkdir -p '$outdir': $!";
    }
    chdir $outdir or die "can't chdir($outdir): $!";

    my ($from, $from_orig) = osm_file_delta_ago($time, $delta);
    my ($to, $to_orig) = osm_file_delta_ago($time, 0);

    $_ .= '.osm' for $from, $to;

    if (not -f $from or not -f $to) {
        die "Both input files need to exist:\n" . `du -sh $from $to`;
    }

    my $cmd = "nice -n 19 $^X $useractivity $from $to $label.html P $size > /dev/null";
    system $cmd and die "Can't osmdiff ($!): $cmd";
}

sub osm_file_delta_ago
{
    my ($time, $delta) = @_;

    my ($sec, $min, $hour, $mday, $mon, $y, $wday, $yday, $isdst) = localtime $time;
    my ($year, $month_no_leading, $day_no_leading) = Add_Delta_Days(1900+$y, $mon+1, $mday, $delta);
    my $month = sprintf "%02i", $month_no_leading;
    my $day = sprintf "%02i", $day_no_leading;
    my $date = "$year-$month-$day";
    my $osm = "/var/www/osm.nix.is/archive/$date/Iceland.osm.bz2";
    if (wantarray) {
        return ($date, $osm);
    } else {
        return $osm;
    }
}

sub osm_version
{
    my $file = shift;
    my ($fv) = qx[bzcat $file | head -n2 | grep "^<osm"] =~ /version=['"](.*?)['"]/;
    return $fv;
}

sub bbox_to_osmosis_bbox
{
    my $bbox = shift;
    my %bbox;
    @bbox{qw(left bottom right top)} = split /,/, $bbox;
    return "left=$bbox{left} bottom=$bbox{bottom} right=$bbox{right} top=$bbox{top}";
}
