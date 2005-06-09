
use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Exception;


    
if ( ! require DBD::SQLite2 ) 
{
    plan skip_all => "Couldn't load DBD::SQLite2";
}

#plan tests => 5;

BEGIN { unlink 'test.db' };

use DBI::Test;

DBI::Test->db_Main->do("CREATE TABLE person (
    id integer not null primary key,
    name varchar(255),
    town integer,
    street varchar(255)        
);");

DBI::Test->db_Main->do("CREATE TABLE town (
    id integer not null primary key,
    name varchar,
    pop integer,
    lat numeric,
    long numeric,
    country text
);");

DBI::Test->db_Main->do("CREATE TABLE toy (
    id integer not null primary key,
    name varchar,
    person integer,
    descr text
);");

my @towns = ( [ qw( Trumpton 250 150.7 160.8 PlayLand ) ],      # 1
              [ qw( Uglyton  1000000 10.2 8.3 Yuckland ) ],     # 2
              [ qw( Toonton  500 100.5 200.9 Cartoonland ) ],   # 3
              [ qw( London   6000000 310.4 431 2 England ) ],   # 4
              );

foreach my $town ( @towns )
{
    my %data;
    @data{ qw( name pop lat long country ) } = @$town;
    #use Data::Dumper;
    #warn Dumper( \%data );
    Town->create( \%data );
}

ok(1);
