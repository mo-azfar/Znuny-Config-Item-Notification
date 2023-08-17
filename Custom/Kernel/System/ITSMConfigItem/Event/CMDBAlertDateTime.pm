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

    # as DefinitionCreate does not belong to an item, we don't execute on this
    if ( $Param{Event} && $Param{Event} eq 'DefinitionCreate' ) {
        return;
    }

	local $Kernel::OM = Kernel::System::ObjectManager->new(
        'Kernel::System::Log' => {
            LogPrefix => 'CMDBAlertDateTime', 
        },
    );
	
    NEEDED:
    for my $Needed (qw(Data Event UserID)) {

        next NEEDED if defined $Param{$Needed};

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need $Needed!",
        );
        return;
    }
	
	my $ConfigItemObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');
	
	my $VersionListRef = $ConfigItemObject->VersionList(
		ConfigItemID => $Param{Data}->{ConfigItemID},
	);
	
	my @VersionList = @{$VersionListRef};
	my $PreVersionID = $VersionList[-2];
	my $LastVersionID = $Param{Data}->{Comment};
	
	my $PreVersion = $ConfigItemObject->VersionGet(
		VersionID  => $PreVersionID,
		XMLDataGet => 1, 
	);
	
	my $LastVersion = $ConfigItemObject->VersionGet(
		ConfigItemID => $Param{Data}->{ConfigItemID},
		XMLDataGet   => 1,
	);
	
	my $PV	 		 = $PreVersion->{XMLData}->[1]->{Version}->[1];
	my $PreDateTime  = $PV->{AlertDateTime}->[1]->{Content};
	my $PreType      = $PV->{AlertDateTime}->[1]->{AlertType}->[1]->{Content};
	my $PreReceiver  = $PV->{AlertDateTime}->[1]->{AlertReceiver}->[1]->{Content};
		
	my $Number 		 = $LastVersion->{Number};
	my $Name 		 = $LastVersion->{Name};
	my $LV	 		 = $LastVersion->{XMLData}->[1]->{Version}->[1];
	my $NewDateTime  = $LV->{AlertDateTime}->[1]->{Content};
	my $NewType      = $LV->{AlertDateTime}->[1]->{AlertType}->[1]->{Content};
	my $NewReceiver  = $LV->{AlertDateTime}->[1]->{AlertReceiver}->[1]->{Content};
	
	return if !$NewDateTime;

	my $Event = 0;
    if ( $PreDateTime ne $NewDateTime )
	{
		$Event = 1;
	}
	
	if ( $PreType ne $NewType )
	{
		$Event = 1;
	}
	
	if ( $PreReceiver ne $NewReceiver )
	{
		$Event = 1;
	}
	
	return if !$Event;
	
	my $SchedulerObject = $Kernel::OM->Get('Kernel::System::Scheduler');
	
	#check existing task
	my @FutureTask = $SchedulerObject->FutureTaskList(
		Type => 'AsynchronousExecutor', 
	);
	
	my $TaskName = "AlertDateTime - ConfigItemID:$Param{Data}->{ConfigItemID}";
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
	
	my $GeneralCatalogObject = $Kernel::OM->Get('Kernel::System::GeneralCatalog');
	
	my $AlertTypeName = $GeneralCatalogObject->ItemGet(
		ItemID => $NewType,
	);

	if ( $AlertTypeName->{Name} eq "Email" )
	{
		my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
		
		my $HttpType = $ConfigObject->Get('HttpType');
		my $FQDN = $ConfigObject->Get('FQDN');
		my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
	
		my $ConfigItemURL = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentITSMConfigItemZoom;ConfigItemID='.$Param{Data}->{ConfigItemID};
		
		#validate email
		my $regex = $NewReceiver =~ /^[a-z0-9._]+\@[a-z0-9.-]+$/;

		if ( !$regex ) 
		{
			$Kernel::OM->Get('Kernel::System::Log')->Log(
				Priority => 'error',
				Message  => "ConfigItem#$Number: AlertType ($AlertTypeName->{Name}) value not correct: $NewReceiver!",
			);
			return;
		} 
	
		#create new task
		my $NewTask = $SchedulerObject->TaskAdd(
			ExecutionTime            => $NewDateTime,
			Type                     => 'AsynchronousExecutor',
			Name                     => $TaskName,
			Attempts                 =>  1,
			MaximumParallelInstances =>  1,
			Data                     => 
			{
				Object   => 'Kernel::System::Email',
				Function => 'Send',
				Params   => 
					{
						From => $ConfigObject->Get('NotificationSenderEmail'),
						To    => $NewReceiver,
						Subject  => "Alert: ConfigItem#$Number - $Name",
						Charset      => "iso-8859-15",
						MimeType      => "text/html",
						Body          => "<b>ConfigItem#$Number has reach its alert time.
						<br/><br/>Name: $Name<br/>Alert Time: $NewDateTime</b><br/><br/>$ConfigItemURL",
					},
			},
		);
	}
	
	elsif ( $AlertTypeName->{Name} eq "Telegram" )
	{
		#validate telegram chat id
		my $regex = $NewReceiver =~ /^[0-9]*$/;

		if ( !$regex ) 
		{
			$Kernel::OM->Get('Kernel::System::Log')->Log(
				Priority => 'error',
				Message  => "ConfigItem#$Number: AlertType ($AlertTypeName->{Name}) value not correct: $NewReceiver!",
			);
			return;
		} 
		
		my $Webservice = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice')->WebserviceGet(
			Name => $Param{Config}->{WebserviceName},
		);
	
		if ( !$Webservice->{ID} )
		{
			$Kernel::OM->Get('Kernel::System::Log')->Log(
				Priority => 'error',
				Message  => "ConfigItem#$Number. WebserviceName invalid in configuration!",
			);
			return;
		}
		
		#create new task
		my $NewTask = $SchedulerObject->TaskAdd(
			ExecutionTime            => $NewDateTime,  
			Type                     => 'AsynchronousExecutor',     
			Name                     => $TaskName,             
			Attempts                 => 1,                     
			MaximumParallelInstances => 1, 
			Data => {                                           
				Object   => 'Kernel::GenericInterface::Requester',
				Function => 'Run',
				Params   => 
					{
						WebserviceID => $Webservice->{ID},
						Invoker      => $Param{Config}->{Invoker},     	# Name of the Invoker to be used for sending the request
						Asynchronous => 1,                     			# Optional, 1 or 0, defaults to 0
						Data         => {                       		# Data payload for the Invoker request (remote web service)
							ConfigItemID => $Param{Data}->{ConfigItemID},
						},
					},
			},
		);
	}
	
	else
	{
		return;
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
