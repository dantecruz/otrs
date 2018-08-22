# --
# Copyright (C) 2001-2018 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::PostMaster::LoopProtection;

use strict;
use warnings;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed  objects
    for (qw(DBObject LogObject ConfigObject MainObject)) {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }

    # load backend module
    my $BackendModule = $Self->{ConfigObject}->Get('LoopProtectionModule')
        || 'Kernel::System::PostMaster::LoopProtection::DB';
    if ( !$Self->{MainObject}->Require($BackendModule) ) {
        $Self->{MainObject}->Die("Can't load loop protection backend module $BackendModule! $@");
    }

    $Self->{Backend} = $BackendModule->new( %{$Self} );

    return $Self;
}

sub SendEmail {
    my ( $Self, %Param ) = @_;

    return $Self->{Backend}->SendEmail(%Param);
}

sub Check {
    my ( $Self, %Param ) = @_;

    return $Self->{Backend}->Check(%Param);
}

1;
