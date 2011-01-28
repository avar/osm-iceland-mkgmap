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
for my $drop (qw(osmistmp osmisdel)) {
    if (my ($db, $user) = db_and_owner($drop)) {
        docmd "dropdb $db";
        docmd "dropuser $user";
    }
}

# Create db
docmd q[createuser osmistmp -w -S -D -R];
docmd q[createdb -E UTF8 -O osmistmp osmistmp];
docmd q[echo "alter user osmistmp encrypted password 'osmistmp';" | psql -q osmistmp];

# Create schema
docmd q[psql -q -d osmistmp < /usr/share/postgresql/9.0/contrib/btree_gist.sql];

chdir "/home/avar/src/osm.nix.is/osm-sites-rails_port";

docmd q[echo "development:"           > config/database.yml];
docmd q[echo "  adapter: postgresql" >> config/database.yml];
docmd q[echo "  database: osmistmp"  >> config/database.yml];
docmd q[echo "  username: osmistmp"  >> config/database.yml];
docmd q[echo "  password: osmistmp"  >> config/database.yml];
docmd q[echo "  host: localhost"     >> config/database.yml];
docmd q[echo "  encoding: utf8"      >> config/database.yml];

docmd q[cp config/example.application.yml config/application.yml];

# migrate!
docmd q[rake db:migrate];

# Import Iceland.osm
#echo Importing data
docmd q[/home/avar/src/osm.nix.is/osmosis/bin/osmosis --read-xml-0.6 /var/www/osm.nix.is/latest/Iceland.osm.bz2 --write-apidb-0.6 populateCurrentTables=yes host="localhost" database="osmistmp" user="osmistmp" password="osmistmp" validateSchemaVersion=no];

## Rename it & delete
# old -> del
if (my ($db, $user) = db_and_owner("osmis")) {
    docmd q[echo 'alter database osmis rename to osmisdel;' | psql avar];
    docmd q[echo 'alter user osmis rename to osmisdel;' | psql avar];
}

# tmp -> new
docmd q[echo 'alter database osmistmp rename to osmis;' | psql avar];
docmd q[echo 'alter user osmistmp rename to osmis;' | psql avar];
docmd q[echo "alter user osmis encrypted password 'osmis';" | psql avar];

# del old
if (my ($db, $user) = db_and_owner("osmisdel")) {
    docmd q[dropdb osmisdel];
    docmd q[dropuser osmisdel];
}

# Regenerate munin stats
my $nuke = '/var/lib/munin/plugin-state/osm_apidb_*storable';
if (glob $nuke) {
    docmd qq[sudo rm -v $nuke];
}

exit($ok ? 0 : 1);

sub db_and_owner {
    my ($db) = @_;

    chomp(my @out = qx[psql -l]);

    for (@out) {
        if (/^ \s+ ($db) \s+ \| \s+ (\S+) \b/) {
            return ($1, $2);
        }
    }

    return;
}
