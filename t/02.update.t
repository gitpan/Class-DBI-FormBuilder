
use strict;
use warnings;

# This would be easier if it could go in the same file as 01.create.t, 
# but something stops new forms with different values from being made 
# from new ENV{QUERY_STRING} values - the form always has the values 
# from the original query string.

use Test::More qw(no_plan);
use Test::Exception;


    
if ( ! require DBD::SQLite2 ) 
{
    plan skip_all => "Couldn't load DBD::SQLite2";
}

#plan tests => 5;

use DBI::Test; # also includes Bar
   


# ------------------------------------------------------------------------
{
    # Fake an update request, and supply an id (assume first object inserted 
    # in 01.create.t has id = 1)
    $ENV{REQUEST_METHOD} = 'GET';
    $ENV{QUERY_STRING}   = "name=DaveBaird&street=NiceStreet&town=1&id=1&_submitted=1";
    
    my $data = { street => 'NiceStreet',
                 name   => 'DaveBaird',
                 town   => 1,
                 id     => 1,
                 toys    => undef,
                 };

    my $form = Person->as_form;
    
    is_deeply( scalar $form->field, $data );
    
    my $obj;
    lives_ok { $obj = Person->retrieve_from_form( $form ) };
    isa_ok( $obj, 'Class::DBI' );

    is( $obj->id, 1, 'got correct object' );
    is( $obj->name, 'Dave', 'object not updated yet' );
    
    lives_ok { Person->update_from_form( $form ) } 'updated form';
    
    is( $obj->name, 'DaveBaird', 'object updated' );
}    
    

    
    