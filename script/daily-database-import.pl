#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;
use autodie;
use Getopt::Long;
use Capture::Tiny qw[capture];

Getopt::Long::Parser->new(
        config => [ qw< bundling no_ignore_case no_require_order > ],
)->getoptions(
    'v|verbose' => \my $verbose,
    'd|dry-run' => \my $dry_run,
    'b|base-name=s' => \(my $base_name = 'osmis'),
    'o|osm-file=s' => \(my $osm_file = '/var/www/osm.nix.is/latest/Iceland.osm.bz2'),
);

my $ok = 1;

sub docmd {
    my $cmd = shift;
    my $ret;
    say $cmd if $verbose;

    unless ($dry_run) {
        my ($stdout, $stderr) = capture {
            $ret = system $cmd;
        };

        if ($ret) {
            $ok = 0;
            print STDERR "Command '$cmd' failed with code '$ret'";
            print STDOUT $stdout;
            print STDERR $stderr;
        }
    }

    return;
}

## Create temporary DB:

# drop tmp users
for my $drop ("${base_name}tmp", "${base_name}del") {
    if (my ($db, $user) = db_and_owner($drop)) {
        docmd "dropdb $db";
        docmd "dropuser $user";
    }
}

# Create db
docmd qq[createuser ${base_name}tmp -w -s];
docmd qq[createdb -E UTF8 -O ${base_name}tmp ${base_name}tmp];
docmd qq[echo "alter user ${base_name}tmp encrypted password '${base_name}tmp';" | psql -q ${base_name}tmp];

# Create schema
docmd qq[psql -q -d ${base_name}tmp < /usr/share/postgresql/9.0/contrib/btree_gist.sql];

chdir "/home/avar/src/osm.nix.is/osm-sites-rails_port";

docmd qq[echo "development:"           > config/database.yml];
docmd qq[echo "  adapter: postgresql" >> config/database.yml];
docmd qq[echo "  database: ${base_name}tmp"  >> config/database.yml];
docmd qq[echo "  username: ${base_name}tmp"  >> config/database.yml];
docmd qq[echo "  password: ${base_name}tmp"  >> config/database.yml];
docmd qq[echo "  host: localhost"     >> config/database.yml];
docmd qq[echo "  encoding: utf8"      >> config/database.yml];

docmd q[cp config/example.application.yml config/application.yml];

# migrate!
docmd q[rake db:migrate];

# Import Iceland.osm
#echo Importing data
docmd qq[/home/avar/src/osm.nix.is/osmosis/bin/osmosis --read-xml-0.6 $osm_file --write-apidb-0.6 populateCurrentTables=yes host="localhost" database="${base_name}tmp" user="${base_name}tmp" password="${base_name}tmp" validateSchemaVersion=no];

## Rename it & delete
# old -> del
if (my ($db, $user) = db_and_owner("${base_name}")) {
    docmd qq[echo 'alter database ${base_name} rename to ${base_name}del;' | psql avar];
    docmd qq[echo 'alter user ${base_name} rename to ${base_name}del;' | psql avar];
}

# tmp -> new
docmd qq[echo 'alter database ${base_name}tmp rename to ${base_name};' | psql avar];
docmd qq[echo 'alter user ${base_name}tmp rename to ${base_name};' | psql avar];
docmd qq[echo "alter user ${base_name} encrypted password '${base_name}';" | psql avar];

# Drop the temporary user
docmd qq[dropuser ${base_name}tmp];

# del old
if (my ($db, $user) = db_and_owner("${base_name}del")) {
    docmd qq[dropdb ${base_name}del];
    docmd qq[dropuser ${base_name}del];
}

# Regenerate munin stats
if ($base_name eq 'osmis') {
    my $nuke = '/var/lib/munin/plugin-state/osm_apidb_*storable';
    if (glob $nuke) {
        docmd qq[sudo rm -v $nuke];
    }
}

# Grant permissions. THIS SUCKS
{
    chomp(my @lines = qx[psql -c "\\\\dt" ${base_name}]);
    my @tables = map { / ^ \s+ \S+ \s+ \| \s+ (\S+) /x; $1 } grep { /table/ } @lines;
    docmd qq[echo "GRANT ALL PRIVILEGES on $_ TO PUBLIC;" | psql -q ${base_name}] for @tables;
}

exit($ok ? 0 : 1);

sub db_and_owner {
    my ($db) = @_;

    chomp(my @out = qx[psql -l]);

    for (@out) {
        if (/^ \s+ ($db) \s+ \| \s+ (\S+) \b/x) {
            return ($1, $2);
        }
    }

    return;
}
