

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

# ----- add some toys -----
#id name person descr 
    
my @toys = ( [ qw( RedCar 1 car ) ],        # 1
             [ qw( BlueBug 1 animal ) ],    # 2
             [ qw( GreenBlock 1 lego ) ],   # 3
             [ qw( YellowSub 2 boat ) ],    # 4
             );

foreach my $toy ( @toys )
{
    my %data;
    @data{ qw( name person descr ) } = @$toy;
    #use Data::Dumper;
    #warn Dumper( \%data );
    Toy->create( \%data );
}

# -----

my $select = qr(<select id="toys" multiple="multiple" name="toys"><option value="1">RedCar</option><option value="2">BlueBug</option><option value="3">GreenBlock</option><option value="4">YellowSub</option></select>);

my $form  = Person->as_form( selectnum => 2 );

my $html  = $form->render;

# select, no option selected
# This was failing in first version, due to testing for $form->field( name => $field ); 
# instead of the existence of the field (the former returns its value, which is empty 
# in classes)
like( $html, $select, 'finding has_many rels' );


