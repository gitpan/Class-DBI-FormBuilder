
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
$ENV{QUERY_STRING}   = 'name=Brian&street=NastyStreet&town=2&_submitted=1';

my $data = { street => 'NastyStreet',
             name   => 'Brian',
             town   => 2,
             id     => undef,
             toys    => undef,
             };

my $form = Person->as_form;

is_deeply( scalar $form->field, $data );

my $obj;
lives_ok { $obj = Person->update_or_create_from_form( $form ) } 'update_or_create - create';
isa_ok( $obj, 'Class::DBI' );

my $id = $obj->id;

is( $id, 22 ); # 22 is a new id


my $obj_data = { map { $_ => $obj->$_ || undef } keys %$data };
$data->{id} = 22;    
$data->{town} = 'Uglyton';
is_deeply( $obj_data, $data );


    
    

    