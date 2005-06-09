

use strict;
use warnings;

use Test::More;
use Test::Exception;

if ( ! require DBD::SQLite2 ) 
{
    plan skip_all => "Couldn't load DBD::SQLite2";
}

plan tests => 5;

use DBI::Test; 

# Here we're checking a couple of bugs:
#   1. dies when generating an empty form because no options are returned (fixed)
#   2. when generating an empty form or a partial form without the has_many field - 
#       all fields generated anyway. 

my $select = qr(<select id="toys" multiple="multiple" name="toys"><option value="1">RedCar</option><option value="2">BlueBug</option><option value="3">GreenBlock</option><option value="4">YellowSub</option></select>);

my $empty_form;

lives_ok { $empty_form = Person->as_form( selectnum => 2,
                                          fields => [ ], 
                                          #debug => 1,
                                          ) };
                                          
lives_and( sub { unlike( $empty_form->render, qr(street) ) }, 'empty form - no street' ); # 2
                                            

# Build a form with the has_many column missing
my $partial_form;

lives_ok { $partial_form = Person->as_form( selectnum => 2,
                                            fields => [ qw( street name town ) ], # 
                                            #debug => 1,
                                            ) };
                                            
# doesn't have the select                                    
#unlike( $html_from_partial, $select );

# in fact, no mention of toys
lives_and( sub { like(   $partial_form->render, qr(street) ) }, 'partial form - has street' );
lives_and( sub { unlike( $partial_form->render, qr(toys) ) }, 'partial form - no toys' );  # 5

# -----

