
use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Exception;

if ( ! require DBD::SQLite2 ) 
{
    plan skip_all => "Couldn't load DBD::SQLite2";
}

#plan tests => 5;

use DBI::Test; 


$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING}   = '';

# basic tests
{
    my $dbaird = Person->retrieve( 1 );
    
    isa_ok( $dbaird, 'Class::DBI' );
    
    my $form = $dbaird->as_form_with_related;
    
    use Data::Dumper;
    
    my $html = $form->render;
    
    # an extra pk field is getting added
    # ref: the test in 05.update_or_create.t confirms only 1 field is expected
    my @matches = $html =~ /(name="id")/g;
    is( scalar( @matches ), 1 );

    #warn Dumper( $html );
}