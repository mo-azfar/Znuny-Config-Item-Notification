# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# Copyright (C) 2023 mo-azfar, https://github.com/mo-azfar/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::ITSMConfigItem::Event::CMDBAlertDateTime;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::System::ITSMConfigItem',
    'Kernel::System::Log',
);

=head1 NAME

Kernel::System::ITSMConfigItem::Event::DoHistory - Event handler that does the history

=head1 PUBLIC INTERFACE

=head2 new()

create an object

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $DoHistoryObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem::Event::DoHistory');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 Run()

This method handles the event.

    $DoHistoryObject->Run(
        Event => 'ConfigItemCreate',
        Data  => {
            Comment      => 'new value: 1',
            ConfigItemID => 123,
        },
        UserID => 1,
    );

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # as DefinitionCreate does not belong to an item, we don't create
    # a history entry
    if ( $Param{Event} && $Param{Event} eq 'DefinitionCreate' ) {
        return;
    }

    NEEDED:
    for my $Needed (qw(Data Event UserID)) {

        next NEEDED if defined $Param{$Needed};

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need $Needed!",
        );
        return;
    }
	
	my @spl = split('%%', $Param{Data}->{Comment}); 
	my $FieldName = $spl[0];
	
	my $ExpectedField1 = "[1]{\'Version\'}[1]{\'$Param{Config}->{AlertField}\'}[1]";
	my $ExpectedField2 = "[1]{\'Version\'}[1]{\'$Param{Config}->{AlertField}\'}[1]{\'$Param{Config}->{EmailField}\'}[1]";
	
	#if config fieldname eq event field name
	if ( $FieldName eq $ExpectedField1 || $FieldName eq $ExpectedField2 )
	{
		my $ConfigItemObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');
		my $SchedulerObject = $Kernel::OM->Get('Kernel::System::Scheduler');
		
		my $LastVersion = $ConfigItemObject->VersionGet(
			ConfigItemID => $Param{Data}->{ConfigItemID},
			XMLDataGet   => 1,
		);
		
		my $Number 		 = $LastVersion->{Number};
		my $Name 		 = $LastVersion->{Name};
		my $Version 	 = $LastVersion->{XMLData}->[1]->{Version}->[1];		
		my $NewDateTime  = $Version->{$Param{Config}->{AlertField}}->[1]->{Content};
		my $AlertEmail 	 = $Version->{$Param{Config}->{AlertField}}->[1]->{$Param{Config}->{EmailField}}->[1]->{Content};
		
		my @FutureTask = $SchedulerObject->FutureTaskList(
			Type => 'AsynchronousExecutor', 
		);
		
		my $TaskName = "$Param{Config}->{AlertField} - ConfigItemID:$Param{Data}->{ConfigItemID}";
		my $TaskID = 0;
		TASK:
		
		foreach my $Task (@FutureTask)
		{
			if ( $Task->{Name} eq $TaskName )
			{
				$TaskID = $Task->{TaskID};
				
				#delete future task
				my $Delete = $SchedulerObject->FutureTaskDelete(
					TaskID => $TaskID,
				);
		
				last TASK;
			}
		}
		
		#only create new task if datetime has a value in it
		if ( $NewDateTime )
		{
			my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
			my $UserObject = $Kernel::OM->Get('Kernel::System::User');
			
			my $HttpType = $ConfigObject->Get('HttpType');
			my $FQDN = $ConfigObject->Get('FQDN');
			my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
			
			my $ConfigItemURL = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentITSMConfigItemZoom;ConfigItemID='.$Param{Data}->{ConfigItemID};
				
			#create new task
			my $NewTask = $SchedulerObject->TaskAdd(
				ExecutionTime            => $NewDateTime,
				Type                     => 'AsynchronousExecutor',
				Name                     => $TaskName,
				Attempts                 =>  1,
				MaximumParallelInstances =>  0,
				Data                     => 
				{
					Object   => 'Kernel::System::Email',
					Function => 'Send',
					Params   => 
							{
								From => $ConfigObject->Get('NotificationSenderEmail'),
								To    => $AlertEmail,
								Subject  => "Alert: ConfigItem#$Number - $Name",
								Charset      => "iso-8859-15",
								MimeType      => "text/html",
								Body          => "<b>ConfigItem#$Number has reach its alert time.
								<br/><br/>Name: $Name<br/>Alert Time: $NewDateTime</b><br/><br/>$ConfigItemURL",
							},
				},
			);
		}
		
	}
	else
	{
		return 1;
	}   

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<https://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut
