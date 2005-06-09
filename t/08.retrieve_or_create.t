
use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Exception;


    
if ( ! require DBD::SQLite2 ) 
{
    plan skip_all => "Couldn't load DBD::SQLite2";
}

#plan tests => 5;

use DBI::Test; # also includes Bar


$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING}   = 'name=Scooby&street=SnackStreet&town=3&_submitted=1';

my $data = { street => 'SnackStreet',
             name   => 'Scooby',
             town   => 3,
             id     => undef,
             toys    => undef,
             };

my $form = Person->as_form;

is_deeply( scalar $form->field, $data );

# forms build from a class name should include the id field, but with no value, 
# which has the effect of sending an undef
my $html = $form->render;
like( $html, qr(<input id="id" name="id" type="hidden" />) );

my $obj;
lives_ok { $obj = Person->retrieve_or_create_from_form( $form ) } 'retrieve_or_create - create';
isa_ok( $obj, 'Class::DBI' );

$data->{id} = 23; # new id
$data->{town} = 'Toonton';
my $obj_data = { map { $_ => $obj->$_ || undef } keys %$data };
is_deeply( $obj_data, $data );





    
    

    