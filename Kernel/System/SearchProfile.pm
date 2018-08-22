# --
# Copyright (C) 2001-2018 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::SearchProfile;

use strict;
use warnings;

use Kernel::System::CacheInternal;

=head1 NAME

Kernel::System::SearchProfile - module to manage search profiles

=head1 SYNOPSIS

module with all functions to manage search profiles

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::Config;
    use Kernel::System::Encode;
    use Kernel::System::Log;
    use Kernel::System::Main;
    use Kernel::System::DB;
    use Kernel::System::SearchProfile;

    my $ConfigObject = Kernel::Config->new();
    my $EncodeObject = Kernel::System::Encode->new(
        ConfigObject => $ConfigObject,
    );
    my $LogObject = Kernel::System::Log->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
    );
    my $MainObject = Kernel::System::Main->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
    );
    my $DBObject = Kernel::System::DB->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
        MainObject   => $MainObject,
    );
    my $SearchProfileObject = Kernel::System::SearchProfile->new(
        ConfigObject => $ConfigObject,
        LogObject    => $LogObject,
        DBObject     => $DBObject,
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for (qw(DBObject ConfigObject LogObject EncodeObject MainObject )) {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }

    $Self->{CacheInternalObject} = Kernel::System::CacheInternal->new(
        %{$Self},
        Type => 'SearchProfile',
        TTL  => 60 * 60 * 24 * 20,
    );

    # set lower if database is case sensitive
    $Self->{Lower} = '';
    if ( $Self->{DBObject}->GetDatabaseFunction('CaseSensitive') ) {
        $Self->{Lower} = 'LOWER';
    }

    return $Self;
}

=item SearchProfileAdd()

to add a search profile item

    $SearchProfileObject->SearchProfileAdd(
        Base      => 'TicketSearch',
        Name      => 'last-search',
        Key       => 'Body',
        Value     => $String,    # SCALAR|ARRAYREF
        UserLogin => 123,
    );

=cut

sub SearchProfileAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Base Name Key UserLogin)) {
        if ( !defined $Param{$_} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # check value
    return 1 if !defined $Param{Value};

    # create login string
    my $Login = $Param{Base} . '::' . $Param{UserLogin};

    my @Data;
    if ( ref $Param{Value} eq 'ARRAY' ) {
        @Data = @{ $Param{Value} };
        $Param{Type} = 'ARRAY';
    }
    else {
        @Data = ( $Param{Value} );
        $Param{Type} = 'SCALAR';
    }

    for my $Value (@Data) {

        return if !$Self->{DBObject}->Do(
            SQL => "
                INSERT INTO search_profile
                (login, profile_name,  profile_type, profile_key, profile_value)
                VALUES (?, ?, ?, ?, ?)
                ",
            Bind => [
                \$Login, \$Param{Name}, \$Param{Type}, \$Param{Key}, \$Value,
            ],
        );
    }

    # reset cache
    my $CacheKey = $Login . '::' . $Param{Name};
    $Self->{CacheInternalObject}->Delete( Key => $Login );
    $Self->{CacheInternalObject}->Delete( Key => $CacheKey );

    return 1;
}

=item SearchProfileGet()

returns hash with search profile.

    my %SearchProfileData = $SearchProfileObject->SearchProfileGet(
        Base      => 'TicketSearch',
        Name      => 'last-search',
        UserLogin => 'me',
    );

=cut

sub SearchProfileGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Base Name UserLogin)) {
        if ( !defined( $Param{$_} ) ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # create login string
    my $Login = $Param{Base} . '::' . $Param{UserLogin};

    # check the cache
    my $CacheKey = $Login . '::' . $Param{Name};
    my $Cache = $Self->{CacheInternalObject}->Get( Key => $CacheKey );
    return %{$Cache} if $Cache;

    # get search profile
    return if !$Self->{DBObject}->Prepare(
        SQL => "
            SELECT profile_type, profile_key, profile_value
            FROM search_profile
            WHERE profile_name = ?
                AND $Self->{Lower}(login) = $Self->{Lower}(?)
            ",
        Bind => [ \$Param{Name}, \$Login ],
    );

    my %Result;
    while ( my @Data = $Self->{DBObject}->FetchrowArray() ) {
        if ( $Data[0] eq 'ARRAY' ) {
            push @{ $Result{ $Data[1] } }, $Data[2];
        }
        else {
            $Result{ $Data[1] } = $Data[2];
        }
    }
    $Self->{CacheInternalObject}->Set(
        TTL   => 60,
        Type  => 'SearchProfile',
        Key   => $CacheKey,
        Value => \%Result
    );

    return %Result;
}

=item SearchProfileDelete()

deletes a search profile.

    $SearchProfileObject->SearchProfileDelete(
        Base      => 'TicketSearch',
        Name      => 'last-search',
        UserLogin => 'me',
    );

=cut

sub SearchProfileDelete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Base Name UserLogin)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # create login string
    my $Login = $Param{Base} . '::' . $Param{UserLogin};

    # delete search profile
    return if !$Self->{DBObject}->Do(
        SQL => "
            DELETE
            FROM search_profile
            WHERE profile_name = ?
                AND $Self->{Lower}(login) = $Self->{Lower}(?)
            ",
        Bind => [ \$Param{Name}, \$Login ],
    );

    # delete cache
    my $CacheKey = $Login . '::' . $Param{Name};
    $Self->{CacheInternalObject}->Delete( Key => $Login );
    $Self->{CacheInternalObject}->Delete( Key => $CacheKey );
    return 1;
}

=item SearchProfileList()

returns a hash of all profiles for the given user.

    my %SearchProfiles = $SearchProfileObject->SearchProfileList(
        Base      => 'TicketSearch',
        UserLogin => 'me',
    );

=cut

sub SearchProfileList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Base UserLogin)) {
        if ( !defined( $Param{$_} ) ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # create login string
    my $Login = $Param{Base} . '::' . $Param{UserLogin};

    my $Cache = $Self->{CacheInternalObject}->Get( Key => $Login );
    return %{$Cache} if $Cache;

    # get search profile list
    return if !$Self->{DBObject}->Prepare(
        SQL => "
            SELECT profile_name
            FROM search_profile
            WHERE $Self->{Lower}(login) = $Self->{Lower}(?)
            ",
        Bind => [ \$Login ],
    );

    # fetch the result
    my %Result;
    while ( my @Data = $Self->{DBObject}->FetchrowArray() ) {
        $Result{ $Data[0] } = $Data[0];
    }
    $Self->{CacheInternalObject}->Set(
        Key   => $Login,
        Value => \%Result
    );
    return %Result;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<https://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut
