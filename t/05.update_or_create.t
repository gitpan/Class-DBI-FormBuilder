
use strict;
use warnings;

use Test::More;
use Test::Exception;

if ( ! DBD::SQLite2->require ) 
{
    plan skip_all => "Couldn't load DBD::SQLite2";
}

plan tests => 6;

use DBI::Test; # also includes Bar


$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING}   = 'name=Brian&street=NastyStreet&town=2&_submitted=1';

my $data = { street => 'NastyStreet',
             name   => 'Brian',
             town   => 2,
             id     => undef,
             toys    => undef,
             job => undef,
             };

my $form = Person->as_form;

# this is here just as a proof that there should only be 1 - in 51.related.t I was getting 
# 2 id widgets
my $html = $form->render;
my @matches = $html =~ /(name="id")/g;
is( scalar( @matches ), 1 );

is_deeply( scalar $form->field, $data );

my $obj;
lives_ok { $obj = Person->update_or_create_from_form( $form ) } 'update_or_create - create';
isa_ok( $obj, 'Class::DBI' );

my $id = $obj->id;

is( $id, 23 ); # 23 is a new id


my $obj_data = { map { $_ => $obj->$_ || undef } keys %$data };
$data->{id} = 23;    
$data->{town} = 'Uglyton';
is_deeply( $obj_data, $data );


    
    

    