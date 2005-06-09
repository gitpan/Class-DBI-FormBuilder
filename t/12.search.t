
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
$ENV{QUERY_STRING}   = 'name=Winston&_submitted=1';

my $submitted_data = { street => undef,
                       name   => 'Winston',
                       town   => undef,
                       id     => undef,
                       toys    => undef,
                       };
                       
my $data = { street => 'DowningStreet',
             name   => 'Winston',
             town   => 'London',
             id     => 24,
             toys    => undef,
             };                       

my $form = Person->as_form;

is_deeply( scalar $form->field, $submitted_data );

my $iter;
lives_ok { $iter = Person->search_from_form( $form ) } 'search_from_form';
isa_ok( $iter, 'Class::DBI::Iterator' );

my $first = $iter->next;
isa_ok( $first, 'Class::DBI' );

my $obj;
lives_ok { ( $obj ) = Person->search_from_form( $form ) } 'search_from_form';
isa_ok( $obj, 'Class::DBI' );

my $obj_data = { map { $_ => $obj->$_ || undef } keys %$data };
is_deeply( $obj_data, $data );






